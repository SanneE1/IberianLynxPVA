# Script loosely follows the method described in Cisneros-araujo et al., 2025 to determine habitat suitability for dispersal

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
library(osmextract)
library(sf)

set.seed(2026)


source("scripts/r/transform_maps_to_model_input.R")

# =============================================================================
# 1. PATHS AND SETTINGS
# =============================================================================

# --- File paths ---------------------------------------------------------------
template        <- "data/GIS_maps/Peninsula_500_template.tif"
dispersal_path  <- "data/original_data/Lynx_movement_resistance_maps_Pablo_Cisneros/capas/res_lince_w_2025.tif"
habitat_path    <- "data/original_data/Lynx_movement_resistance_maps_Pablo_Cisneros/capas/habitat_lince_PI_2025.tif"

elevation_path  <- "data/original_data/Copernicus_GLO90_Europe_250m.tif"
vegetation_path <- "data/original_data/LUC_historic_landcover/LUCAS_LUC_v1.1_historical_Europe_0.1deg_2010_2015.nc"
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

presence_dir   <- "data/original_data/20250825_data_German/Presencias/"

# --- GAM SETTINGS -------------------------------------------------------------
# Proportion of cells to use for model fitting (1 = all; 0.1 = 10% sample).
SAMPLE_FRACTION <- 0.30


# --- Output directory ---------------------------------------------------------
OUT_DIR <- "data/GIS_maps/Cisneros_habitat/"   # change to e.g. "outputs" if desired
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

dir.create(road_cache_dir, showWarnings = FALSE, recursive = TRUE)
options(osmextract_download_directory = road_cache_dir)

# =============================================================================
# 2.  SET UP HISTORICAL DATA
# =============================================================================
r_template <- terra::rast(template)

r_disp     <- terra::rast(dispersal_path)  # Dispersal resistance was multiplied by 10000
r_habitat  <- terra::rast(habitat_path)     # returning it to the 0-1 scale

r_elev     <- terra::rast(elevation_path)
r_veg      <- terra::rast(vegetation_path)
r_veg      <- subset(r_veg, time(r_veg) == as.Date("2015-01-01"))
names(r_veg) <- lucas_categores

r_tree   <- sum(r_veg[[c(1:6)]]) 
r_shrub  <- sum(r_veg[[c(7,8)]])
r_grass  <- sum(r_veg[[c(9,10)]])
r_imper  <- sum(r_veg[[c(15)]])
r_crop   <- sum(r_veg[[c(13,14)]])

names(r_tree)  <- "trees"
names(r_shrub) <- "shrubs"
names(r_grass) <- "grasses"
names(r_imper) <- "imperviousness"
names(r_crop)  <- "crops"


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
r_disp    <- terra::project(r_disp, terra::crs(r_template), method = "bilinear")
r_habitat <- terra::project(r_habitat, terra::crs(r_template), method = "bilinear")
r_elev    <- terra::project(r_elev, terra::crs(r_template), method = "bilinear")
r_tree    <- terra::project(r_tree, terra::crs(r_template), method = "bilinear")
r_shrub   <- terra::project(r_shrub, terra::crs(r_template), method = "bilinear")
r_grass   <- terra::project(r_grass, terra::crs(r_template), method = "bilinear")
r_imper   <- terra::project(r_imper, terra::crs(r_template), method = "bilinear")
r_crop    <- terra::project(r_crop, terra::crs(r_template), method = "bilinear")
r_road    <- terra::project(r_road, terra::crs(r_template), method = "bilinear")

# EXTENT CROPPING -------------------------------------------------------------
r_habitat <- terra::crop(r_habitat, r_template)
r_elev    <- terra::crop(r_elev, r_template)
r_tree    <- terra::crop(r_tree, r_template)
r_shrub   <- terra::crop(r_shrub, r_template)
r_grass   <- terra::crop(r_grass, r_template)
r_imper   <- terra::crop(r_imper, r_template)
r_crop    <- terra::crop(r_crop, r_template)
r_road    <- terra::crop(r_road, r_template)

# RESCALE ---------------------------------------------------------------------
r_habitat <- terra::resample(r_habitat, r_template, method = "bilinear")
r_elev    <- terra::resample(r_elev, r_template, method = "bilinear")
r_tree    <- terra::resample(r_tree, r_template, method = "bilinear")
r_shrub   <- terra::resample(r_shrub, r_template, method = "bilinear")
r_grass   <- terra::resample(r_grass, r_template, method = "bilinear")
r_imper   <- terra::resample(r_imper, r_template, method = "bilinear")
r_crop    <- terra::resample(r_crop, r_template, method = "bilinear")
r_road    <- terra::resample(r_road, r_template, method = "bilinear")

names(r_habitat)  <- "habitat.selection"
names(r_elev) <- "elevation"


# =============================================================================
# 3.  RUN GAM
# =============================================================================

full_rast <- c(r_habitat, r_elev, r_tree, r_shrub, r_grass, r_imper, r_crop, r_road)
df_full    <- as.data.frame(full_rast, xy = TRUE, na.rm = TRUE)

n_sample <- max(10000L, as.integer(nrow(df_full) * SAMPLE_FRACTION))
n_sample <- min(n_sample, nrow(df_full))
idx_train <- sample(nrow(df_full), n_sample)
df_train  <- df_full[idx_train, ]

habitat_formula <- as.formula("habitat.selection ~ s(x,y, bs = 'tp') + s(elevation) + 
                          s(trees) + s(shrubs) + s(grasses) + s(imperviousness) +
                          s(crops) + s(road_density_presence_3x3)")
  

gam_habitat <- mgcv::bam(              # bam() = memory-efficient for large n
  formula = habitat_formula,
  family  = gaussian(),
  data    = df_train,
  method  = "fREML",                 # fast REML — best for bam()
  discrete = TRUE,                   # discretise covariates → much faster
  nthreads = max(1L, parallel::detectCores() - 1L)
)

saveRDS(gam_habitat,  file.path(OUT_DIR, "gam_habitat_suitability.rds"))

gam_sum <- summary(gam_habitat)
print(gam_sum)

dev_expl <- (gam_sum$dev.expl) * 100
r2_adj   <- gam_sum$r.sq
gam_rmse <- sqrt(mean(residuals(gam_habitat, type = "response")^2))
cat(sprintf("  Deviance explained : %.2f%%\n", dev_expl))
cat(sprintf("  Adj. R²            : %.4f\n",   r2_adj))
cat(sprintf("  RMSE (response)    : %.4f\n",   gam_rmse))
cat(sprintf("  AIC                : %.2f\n",   AIC(gam_habitat)))

png( file.path(OUT_DIR, "gam_habitat_smooth_plots.png"), width = 1400,
     height = 400 * ceiling((8 + 2) / 3), res = 150)
par(mfrow = c(ceiling((8 + 2) / 3), 3))
plot(gam_habitat, residuals = TRUE, pch = ".", cex = 0.5,
     col = "#2166ac44", shade = TRUE, shade.col = "#2166ac22",
     seWithMean = TRUE)
dev.off()

# =============================================================================
# 5.  Create prediction maps
# =============================================================================

predict_gam_fun <- function(model, data, ...) {
  mgcv::predict.bam(model, newdata = data, type = "response", ...)
}

xy_all <- terra::xyFromCell(r_template, seq_len(terra::ncell(r_template)))

r_x <- r_template
terra::values(r_x) <- xy_all[, 1]
names(r_x) <- "x"

r_y <- r_template
terra::values(r_y) <- xy_all[, 2]
names(r_y) <- "y"

pred_stack <- c(full_rast, r_x, r_y)


r_pred <- terra::predict(pred_stack, gam_habitat,
                         fun = predict_gam_fun, na.rm = TRUE)

writeRaster(r_pred, filename = file.path(OUT_DIR, "historic_predictions.tif"))

ggplot() +
  geom_spatraster(data = r_pred) +
  scale_fill_viridis_c(limits = c(0,60),
                       oob = scales::squish,
                       na.value = NA) +
  theme_minimal()

# =============================================================================
# 6.  Get cut off value from obs. population
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


hist_predicted <- rast(file.path(OUT_DIR, "historic_predictions.tif"))
if(!exists("r_habitat")){
  r_habitat  <- terra::rast(habitat_path)  # habitat resistance was multiplied by 10000
  r_habitat <- terra::project(r_habitat, terra::crs(r_template), method = "bilinear")
  r_habitat <- terra::crop(r_habitat, r_template)
  r_habitat <- terra::resample(r_habitat, r_template, method = "bilinear")
  names(r_habitat)  <- "habitat"
}
COR <- rast("data/GIS_maps/Lynx_HabitatMap_500_Peninsula_Revilla_2015_1.asc")

df <- data.frame(
  hab_selection = values(r_habitat),
  corine = values(COR),
  hab_pred = values(hist_predicted),
  obs = as.factor(values(r_presence))
) 

df$obs <- factor(df$obs, ordered = TRUE)

tree <- rpart(habitat ~ U2018_CLC2018_V2020_20u1, data = df %>% filter(habitat < 60), method = "class",
              control = rpart.control(maxdepth = 2, cp = 0, minbucket = 5))

print(tree) 
splits <- tree$splits[, "index"]
splits <- sort(unique(splits))


ggplot() +
  geom_spatraster(data = crop(hist_predicted, presence_vect)) +
  geom_spatvector(data = presence_vect, fill = "transparent", colour = "red") +
  scale_fill_viridis_b(limits = c(0, 60),
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





