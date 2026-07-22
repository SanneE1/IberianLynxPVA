# =============================================================================
# Habitat suitability Model: PCA on Vegetation + GAM with s(x,y)
# =============================================================================

# =============================================================================
# 0.  PACKAGES
# =============================================================================
library(tidyverse)
library(terra)
library(geodata)
library(mgcv)
library(ggplot2)
library(tidyterra)
library(patchwork)
library(sf)
library(igraph)
library(rpart)

set.seed(2026)

source("scripts/r/function_predict_PCA_maps.R")
source("scripts/r/transform_maps_to_model_input.R")

# =============================================================================
# 1. PATHS AND SETTINGS
# =============================================================================

# --- File paths ---------------------------------------------------------------
template        <- "data/GIS_maps/Peninsula_500_template.tif"
habitat_path    <- "data/original_data/Lynx_movement_resistance_maps_Pablo_Cisneros/capas/res_lince_w_2025.tif"
elevation_path  <- "data/original_data/Copernicus_GLO90_Europe_250m.tif"
vegetation_path <- "data/original_data/LUC_historic_landcover/LUCAS_LUC_v1.1_historical_Europe_0.1deg_2010_2015.nc"
presence_dir    <- "data/original_data/20250825_data_German/Presencias/"
road_path       <- "data/original_data/OSM_road_density.tif"
road_cache_dir  <- "data/original_data/OSM_chache/"

lucas_categores <- c("Tropical.broadleaf.evergreen.trees",
                     "Tropical.deciduous.trees",
                     "Temperate.broadleaf.evergreen.trees",
                     "Temperate.deciduous.trees",
                     "Evergreen.coniferous.trees",
                     "Deciduous.coniferous.trees",
                     "Coniferous.shrubs",
                     "Deciduous.shrubs",
                     "C3.grass",
                     "C4.grass",
                     "Tundra",
                     "Swamp",
                     "Non.irrigated.crops",
                     "Irrigated.crops",
                     "Urban",
                     "Bare")

# --- PCA settings -------------------------------------------------------------
PCA_VAR_THRESHOLD <- 0.90
PCA_MAX_PCS <- 10

# --- GAM settings -------------------------------------------------------------
# Basis dimension for spatial smooth s(x,y). Larger k = more flexible but
# slower. For Europe at 1 km, 300–500 is reasonable; reduce if RAM is tight.
SPATIAL_K <- 400

# Basis dimension for 1-D smooths (elevation, PCs). 
UNIVAR_K <- 20

# Proportion of cells to use for model fitting (1 = all; 0.1 = 10% sample).
# For continent-scale data, sampling 5–10% is much faster and still robust.
# Set to 1 to use all cells (slow for Europe).
SAMPLE_FRACTION <- 0.10

# --- Output directory ---------------------------------------------------------
OUT_DIR <- "data/GIS_maps/PCA_habitat"   
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

dir.create(road_cache_dir, showWarnings = FALSE, recursive = TRUE)
options(osmextract_download_directory = road_cache_dir)

# =============================================================================
# 2.  SET UP HISTORICAL DATA
# =============================================================================
if(!exists("r_template")){
  r_template <- terra::rast(template)
}

r_habitat  <- terra::rast(habitat_path)  

r_elev     <- terra::rast(elevation_path)
r_veg      <- terra::rast(vegetation_path)

# Download the OSM road map
if(!file.exists(road_path)){
  road_classes <- c("motorway","motorway_link","trunk","trunk_link",
                    "primary","primary_link","secondary","secondary_link",
                    "tertiary","tertiary_link","unclassified")
  
  class_sql <- paste0("'", road_classes, "'", collapse = ", ")
  sql_query <- paste0(
    "SELECT highway, geometry FROM 'lines' WHERE highway IN (", class_sql, ")"
  )
  roads_spain <- oe_get(
    place = "Spain",
    layer = "lines",
    query = sql_query,
    quiet = FALSE,
    download_directory = road_cache_dir
  )
  
  roads_portugal <- oe_get(
    place = "Portugal",
    layer = "lines",
    query = sql_query,
    quiet = FALSE,
    download_directory = road_cache_dir
  )
  
  roads <- bind_rows(roads_spain, roads_portugal)
  rm(roads_spain, roads_portugal)
  gc()
  
  roads <- st_transform(roads, crs(r_template))
  
  template_ext_poly <- as.polygons(ext(r_template), crs = crs(r_template))
  template_ext_sf   <- st_as_sf(template_ext_poly)
  
  buffer_m <- 1000   # match your focal window radius
  aoi_buffered <- st_buffer(template_ext_sf, buffer_m)
  
  roads_crop <- st_intersection(roads, aoi_buffered)
  
  roads_vect <- vect(roads_crop)
  rm(roads_crop)
  gc()
  
  road_presence <- rasterize(roads_vect, r_template, field = 1, background = 0, touches = TRUE)
  road_presence <- mask(road_presence, r_template)   # restore template's own NA pattern
  
  w <- matrix(1, nrow = 3, ncol = 3)
  presence_count <- focal(road_presence, w = w, fun = "sum", na.rm = TRUE)
  
  road_density <- presence_count / 9
  
  road_density <- mask(road_density, r_template)
  names(road_density) <- "road_density_presence_3x3"
  
  writeRaster(road_density, road_path, overwrite = TRUE)
  r_road <- road_density
  
  rm(road_density, presence_count, w, road_presence, roads_vect, roads_crop, aoi_buffered,
     buffer_m, template_ext_sf, template_ext_poly, roads, road_classes, 
     class_sql, sql_query)
  gc()
  
} else {
  r_road <- rast(road_path)
}

# CRS MATCHING ----------------------------------------------------------------
r_habitat <- terra::project(r_habitat, terra::crs(r_template), method = "bilinear")
r_elev <- terra::project(r_elev, terra::crs(r_template), method = "bilinear")
r_veg  <- terra::project(r_veg,  terra::crs(r_template), method = "bilinear")
r_road    <- terra::project(r_road, terra::crs(r_template), method = "bilinear")

# GETTING ONLY LAST YEAR FOR VEGITATION RASTER --------------------------------
r_veg      <- subset(r_veg, time(r_veg) == as.Date("2015-01-01"))
names(r_veg) <- lucas_categores

# EXTENT CROPPING -------------------------------------------------------------
r_habitat <- terra::crop(r_habitat, r_template)
r_elev <- terra::crop(r_elev, r_template)
r_veg  <- terra::crop(r_veg,  r_template)
r_road    <- terra::crop(r_road, r_template)

# RESCALE ---------------------------------------------------------------------
r_habitat <- terra::resample(r_habitat, r_template, method = "bilinear")
r_elev <- terra::resample(r_elev, r_template, method = "bilinear")
r_veg  <- terra::resample(r_veg,  r_template, method = "bilinear")
r_road    <- terra::resample(r_road, r_template, method = "bilinear")

names(r_habitat)  <- "habitat"
names(r_elev) <- "elevation"

# =============================================================================
# 3.  PCA
# =============================================================================

full_stack <- c(r_habitat, r_elev, r_veg, r_road)
df_full    <- as.data.frame(full_stack, xy = TRUE, na.rm = TRUE)

veg_matrix <- as.matrix(df_full[, colnames(df_full) %in% lucas_categores])

# remove near-zero variance columns
col_vars <- apply(veg_matrix, 2, var, na.rm = TRUE)
zero_var  <- names(col_vars[col_vars < 1e-10])
veg_matrix <- veg_matrix[, !colnames(veg_matrix) %in% zero_var, drop = FALSE]
veg_cols   <- colnames(veg_matrix)

# Fit PCA
pca_fit <- prcomp(veg_matrix, center = TRUE, scale. = TRUE)

# PCA axis
pca_var      <- pca_fit$sdev^2
pca_var_prop <- pca_var / sum(pca_var)
pca_var_cum  <- cumsum(pca_var_prop)

n_pcs <- min(
  which(pca_var_cum >= PCA_VAR_THRESHOLD)[1],  # threshold rule
  PCA_MAX_PCS,                                  # hard cap
  ncol(pca_fit$rotation)                        # can't exceed n layers
)

cat(sprintf("  Retaining %d PC(s) — explains %.1f%% of vegetation variance\n",
            n_pcs, pca_var_cum[n_pcs] * 100))
cat("  Variance per PC:\n")

for (i in seq_len(n_pcs)){
  cat(sprintf("    PC%d: %.1f%%  (cumulative: %.1f%%)\n",
              i, pca_var_prop[i]*100, pca_var_cum[i]*100))
}

# Project all cells onto the retained PCs -------------------------------------
pc_scores      <- predict(pca_fit, newdata = veg_matrix)[, seq_len(n_pcs), drop = FALSE]
pc_names       <- paste0("PC", seq_len(n_pcs))
colnames(pc_scores) <- pc_names

df_full <- cbind(df_full, as.data.frame(pc_scores))

# Save PCA object (for future prediction) -------------------------------------
saveRDS(pca_fit, file.path(OUT_DIR, "veg_pca.rds"))

# --- PCA summary plot ---------------------------------------------------------
cat("  Generating PCA summary plot ...\n")

scree_df <- data.frame(
  PC       = seq_along(pca_var_prop),
  Variance = pca_var_prop * 100,
  Cumulative = pca_var_cum * 100
)

p_scree <- ggplot(scree_df, aes(x = PC)) +
  geom_col(aes(y = Variance), fill = "#2166ac", alpha = 0.8) +
  geom_line(aes(y = Cumulative), colour = "#d73027", linewidth = 0.8) +
  geom_point(aes(y = Cumulative), colour = "#d73027", size = 2) +
  geom_hline(yintercept = PCA_VAR_THRESHOLD * 100, linetype = "dashed",
             colour = "grey40") +
  geom_vline(xintercept = n_pcs + 0.5, linetype = "dotted", colour = "#4dac26") +
  annotate("text", x = n_pcs + 0.6, y = 5,
           label = paste0("Retained: ", n_pcs, " PCs"),
           hjust = 0, size = 3, colour = "#4dac26") +
  scale_x_continuous(breaks = seq_along(pca_var_prop)) +
  scale_y_continuous(sec.axis = sec_axis(~., name = "Cumulative variance (%)")) +
  labs(title = "PCA Scree Plot — Vegetation Layers",
       x = "Principal Component", y = "Variance explained (%)") +
  theme_minimal(base_size = 10) +
  theme(plot.title = element_text(face = "bold"))

# Biplot of loadings for PC1 vs PC2
load_df <- as.data.frame(pca_fit$rotation[, 1:min(2, n_pcs)])
load_df$variable <- rownames(load_df)
names(load_df)[1:2] <- c("PC1", "PC2")

p_biplot <- ggplot(load_df, aes(x = PC1, y = PC2, label = variable)) +
  geom_segment(aes(x = 0, y = 0, xend = PC1, yend = PC2),
               arrow = arrow(length = unit(0.2, "cm")), colour = "#2166ac") +
  geom_text(size = 2.8, hjust = -0.15, colour = "grey20") +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey70") +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey70") +
  labs(title = "PC Loadings Biplot (PC1 vs PC2)",
       x = sprintf("PC1 (%.1f%%)", pca_var_prop[1]*100),
       y = sprintf("PC2 (%.1f%%)", pca_var_prop[min(2,n_pcs)]*100)) +
  theme_minimal(base_size = 10) +
  theme(plot.title = element_text(face = "bold"))

pca_plot <- p_scree | p_biplot
ggsave(file.path(OUT_DIR, "pca_summary.png"), pca_plot, width = 12, height = 5,
       dpi = 180, bg = "white")


# =============================================================================
# 4.  GAM fitting
# =============================================================================

n_sample <- max(10000L, as.integer(nrow(df_full) * SAMPLE_FRACTION))
n_sample <- min(n_sample, nrow(df_full))
idx_train <- sample(nrow(df_full), n_sample)
df_train  <- df_full[idx_train, ]

# -----------------------------------------------------------------------------
# Model:
#   disp.res ~ s(elevation)             — nonlinear elevation response
#              + s(PC1) + s(PC2) + ...  — nonlinear vegetation PC responses
#              + s(x, y, k=SPATIAL_K)   — 2D spatial smooth (absorbs autocorr.)
#
# family = betar() 
# -----------------------------------------------------------------------------


# Build formula string dynamically
pc_smooth_terms <- paste(
  sprintf("s(%s, k = %d, bs = 'cr')", pc_names, UNIVAR_K),
  collapse = " + "
)

gam_formula <- as.formula(sprintf(
  "log(habitat) ~ s(elevation, k = %d, bs = 'cr') + s(road_density_presence_3x3, k = %d, bs = 'cr') + %s + s(x, y, k = %d, bs = 'tp') ",
  UNIVAR_K, 10, pc_smooth_terms, SPATIAL_K
))


gam_model <- mgcv::bam(              # bam() = memory-efficient for large n
  formula = gam_formula,
  family  = gaussian(),
  data    = df_train,
  method  = "fREML",                 # fast REML — best for bam()
  discrete = TRUE,                   # discretise covariates → much faster
  nthreads = max(1L, parallel::detectCores() - 1L)
)

# Save model
saveRDS(gam_model,  file.path(OUT_DIR, "gam_model.rds"))

gam_sum <- summary(gam_model)
print(gam_sum)

dev_expl <- (gam_sum$dev.expl) * 100
r2_adj   <- gam_sum$r.sq
gam_rmse <- sqrt(mean(residuals(gam_model, type = "response")^2))
cat(sprintf("  Deviance explained : %.2f%%\n", dev_expl))
cat(sprintf("  Adj. R²            : %.4f\n",   r2_adj))
cat(sprintf("  RMSE (response)    : %.4f\n",   gam_rmse))
cat(sprintf("  AIC                : %.2f\n",   AIC(gam_model)))

png( file.path(OUT_DIR, "gam_smooth_plots.png"), width = 1400,
     height = 400 * ceiling((n_pcs + 2) / 3), res = 150)
par(mfrow = c(ceiling((n_pcs + 2) / 3), 3))
plot(gam_model, residuals = TRUE, pch = ".", cex = 0.5,
     col = "#2166ac44", shade = TRUE, shade.col = "#2166ac22",
     seWithMean = TRUE)
dev.off()


gc()

# =============================================================================
# 5.  Create Suitability maps
# =============================================================================

lucas_hist <- rast("data/original_data/LUC_historic_landcover/LUCAS_LUC_v1.1_historical_Europe_0.1deg_2010_2015.nc")
lucas_fut_245  <- lapply(list.files("data/original_data/LUC_future_landcover/", pattern = "ssp245", full.names = T), 
                         rast) %>%
  rast(.)
lucas_fut_585  <- lapply(list.files("data/original_data/LUC_future_landcover/", pattern = "ssp585", full.names = T), 
                         rast) %>%
  rast(.)

if(exists("r_elev")) { 
  dem <- r_elev
} else {
  dem <- rast(elevation_path)
  if (!terra::same.crs(dem, r_template)) dem <- terra::project(dem, terra::crs(r_template), method = "bilinear")
  dem <- terra::crop(dem, r_template)
  
}

pca <-  file.path(OUT_DIR, "veg_pca.rds")
gam <-  file.path(OUT_DIR, "gam_model.rds")


if (!terra::same.crs(lucas_hist,  r_template)) lucas_hist  <- terra::project(lucas_hist,  terra::crs(r_template), method = "bilinear")
lucas_hist  <- terra::crop(lucas_hist,  r_template)

# Last historical data
hist_r <- subset(lucas_hist, time(lucas_hist) == as.Date("2015-01-01"))
names(hist_r) <- lucas_categores

hist <- predict_PCA_maps(veg_rast = hist_r, elev_rast = dem, road_rast = r_road,
                         template_raster = r_template,
                         name_prediction_type = "predicted_habitat",
                         pca_path = pca, gam_path = gam, 
                         output_path = file.path(OUT_DIR, "habitat_historic.tif")) 

writeRaster(hist$predicted, filename = file.path(OUT_DIR, "historic_PCA_prediction_habitat.tif"), overwrite = T)
writeRaster(hist$extrapolation_risk, filename = file.path(OUT_DIR, "historic_PCA_prediction_habitat_exprisk.tif"), overwrite = T)



lucas_fut_245  <- terra::crop(lucas_fut_245, ext(-11, 3.4, 34, 45))
lucas_fut_245  <- terra::project(lucas_fut_245,  terra::crs(r_template), method = "bilinear")
lucas_fut_245  <- terra::crop(lucas_fut_245,  r_template)

fut_245_stack_pred <- list()
fut_245_stack_risk <- list()

for(d in unique(time(lucas_fut_245))) {
  print(as.Date(d))
  fut_r <- subset(lucas_fut_245, time(lucas_fut_245) == as.Date(d))
  names(fut_r) <- lucas_categores
  map <- predict_PCA_maps(veg_rast = fut_r, elev_rast = dem, road_rast = r_road,
                          template_raster = r_template,
                          name_prediction_type = "predicted_habitat",
                          pca_path = pca, gam_path = gam)
  fut_245_stack_pred[[length(fut_245_stack_pred) + 1]] <- wrap(map$predicted)
  fut_245_stack_risk[[length(fut_245_stack_risk) + 1]] <- wrap(map$extrapolation_risk)
}

fut_245_stack_pred <- rast(lapply(fut_245_stack_pred, unwrap))
fut_245_stack_risk <- rast(lapply(fut_245_stack_risk, unwrap))

time(fut_245_stack_pred) <- unique(time(lucas_fut_245))
time(fut_245_stack_risk) <- unique(time(lucas_fut_245))

writeRaster(fut_245_stack_pred, filename = file.path(OUT_DIR, "SSP245_PCA_prediction_habitat.tif"))
writeRaster(fut_245_stack_pred, filename = file.path(OUT_DIR, "SSP245_PCA_prediction_habitat_exprisk.tif"))



lucas_fut_585  <- terra::crop(lucas_fut_585, ext(-11, 3.4, 34, 45))
lucas_fut_585  <- terra::project(lucas_fut_585,  terra::crs(r_template), method = "bilinear")
lucas_fut_585  <- terra::crop(lucas_fut_585,  r_template)

fut_585_stack_pred <- list()
fut_585_stack_risk <- list()

for(d in unique(time(lucas_fut_585))) {
  print(as.Date(d))
  fut_r <- subset(lucas_fut_585, time(lucas_fut_585) == as.Date(d))
  names(fut_r) <- lucas_categores
  map <- predict_PCA_maps(veg_rast = fut_r, elev_rast = dem, road_rast = r_road,
                          template_raster = r_template,
                          name_prediction_type = "predicted_habitat",
                          pca_path = pca, gam_path = gam)
  fut_585_stack_pred[[length(fut_585_stack_pred) + 1]] <- wrap(map$predicted)
  fut_585_stack_risk[[length(fut_585_stack_risk) + 1]] <- wrap(map$extrapolation_risk)
}


fut_585_stack_pred <- rast(lapply(fut_585_stack_pred, unwrap))
fut_585_stack_risk <- rast(lapply(fut_585_stack_risk, unwrap))

time(fut_585_stack_pred) <- unique(time(lucas_fut_585))
time(fut_585_stack_risk) <- unique(time(lucas_fut_585))

writeRaster(fut_585_stack_pred, filename = file.path(OUT_DIR, "SSP585_PCA_prediction_habitat.tif"), overwrite=T)
writeRaster(fut_585_stack_risk, filename = file.path(OUT_DIR, "SSP585_PCA_prediction_habitat_exprisk.tif"), overwrite=T)

# 
# world <- ne_countries(scale = "medium", returnclass = "sf")
# world_cropped <- world %>%
#   st_transform(crs(template_raster)) %>%
#   st_crop(ext(template_raster))

ggplot() +
  # geom_sf(data = world_cropped, fill = "grey90", color = "grey30", linewidth = 0.3) +
  geom_spatraster(data = hist$predicted) +
  # geom_spatvector(data = pops, color = "red", fill = "red", alpha = 0.1) +
  scale_fill_viridis_c(limits = c(0,40),
                       oob = scales::squish,
                       na.value = NA) +
  theme_minimal()

# =============================================================================
# 6.  Create Category Maps
# =============================================================================

if(!exists("r_template")){
  r_template <- rast(template)
}

presence_files <- list.files(presence_dir, pattern = ".shp$",
                             recursive = T, full.names = T)

all_polys <- lapply(presence_files, function(f) {
  x <- st_read(f, quiet = TRUE)
  st_geometry(x)   # keep ONLY the geometry, drop all attribute columns
})

combined <- do.call(c, all_polys)   # combine geometries (sfc objects use c(), not rbind())
combined <- st_sf(geometry = combined)   # turn back into an sf object
combined <- st_make_valid(combined)

adj_list <- st_intersects(combined)

# Convert to a graph and find connected components
g <- graph_from_adj_list(adj_list, mode = "all")
components <- components(g)$membership
combined$cluster_id <- components

presence_vect <- combined %>%
  group_by(cluster_id) %>%
  summarise(geometry = st_union(geometry), .groups = "drop") %>%
  st_make_valid() %>%
  terra::vect(.) %>%
  terra::project(., crs(r_template))

r_presence <- terra::rasterize(presence_vect, r_template,
                               field = 1, background = 0)


hist_predicted <- rast(file.path(OUT_DIR, "habitat_historic.tif"))
if(!exists("r_habitat")){
  r_habitat  <- terra::rast(habitat_path)  # habitat resistance was multiplied by 10000
  r_habitat <- terra::project(r_habitat, terra::crs(r_template), method = "bilinear")
  r_habitat <- terra::crop(r_habitat, r_template)
  r_habitat <- terra::resample(r_habitat, r_template, method = "bilinear")
  names(r_habitat)  <- "habitat"
}

df <- data.frame(
  hab_selection = values(r_habitat),
  hab_pred = values(hist_predicted),
  obs = as.factor(values(r_presence))
) 

df$obs <- factor(df$obs, ordered = TRUE)

tree <- rpart(obs ~ habitat, data = df %>% filter(habitat < 100), method = "class",
              control = rpart.control(maxdepth = 1, cp = -1, minsplit = 2, minbucket = 1))

print(tree) 
splits <- tree$splits[, "index"]
splits <- sort(unique(splits))


ggplot() +
  # geom_sf(data = world_cropped, fill = "grey90", color = "grey30", linewidth = 0.3) +
  geom_spatraster(data = hist_predicted) +
  scale_fill_viridis_b(limits = c(0, 40),
                       breaks = splits,
                       oob = scales::oob_squish,
                       na.value = NA) +
  theme_minimal()



pred_files_585 <- rast(file.path(OUT_DIR, "SSP585_PCA_prediction_habitat.tif"))

if(!dir.exists(file.path(OUT_DIR, "SSP585"))) {dir.create(file.path(OUT_DIR, "SSP585"))}
if(!dir.exists(gsub("GIS_maps", "model_input/maps", file.path(OUT_DIR, "SSP585")))) {
  dir.create(gsub("GIS_maps", "model_input/maps", file.path(OUT_DIR, "SSP585")),
             recursive = T)
  }



for(t in seq_along(time(pred_files_585))){
  r <- pred_files_585[[t]]
  
  r <- ifel(r < splits[1], 1, 0)
  
  f <- file.path(OUT_DIR, "SSP585", paste0("Lynx_DispersalMap_", 
                                           year(time(pred_files_585)[t]), 
                                           ".asc"))
  
  writeRaster(r, f, datatype = "INT2S", overwrite = TRUE, NAflag = -9999)
  
  finput <- paste0(tools::file_path_sans_ext(f), ".txt")
  finput <- gsub("GIS_maps", "model_input/maps", finput)
  
  transform_asc_file(f, finput)
}
