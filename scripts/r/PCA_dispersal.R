# =============================================================================
# Habitat Suitability Model: PCA on Vegetation + GAM with s(x,y)
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

set.seed(2026)

source("scripts/r/function_predict_dispersal.R")
source("scripts/r/transform_maps_to_model_input.R")

# =============================================================================
# 1. PATHS AND SETTINGS
# =============================================================================

# --- File paths ---------------------------------------------------------------
template        <- "data/GIS_maps/Peninsula_500_template.tif"
habitat_path    <- "data/original_data/Lynx_movement_resistance_maps_Pablo_Cisneros/capas/res_lince_w_2025.tif"
elevation_path  <- "data/original_data/Copernicus_GLO90_Europe_250m.tif"
vegetation_path <- "data/original_data/LUC_historic_landcover/LUCAS_LUC_v1.1_historical_Europe_0.1deg_2010_2015.nc"

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

# Basis dimension for 1-D smooths (elevation, PCs). Default 10 is usually fine.
UNIVAR_K <- 10

# Proportion of cells to use for model fitting (1 = all; 0.1 = 10% sample).
# For continent-scale data, sampling 5–10% is much faster and still robust.
# Set to 1 to use all cells (slow for Europe).
SAMPLE_FRACTION <- 0.10

# --- Output directory ---------------------------------------------------------
OUT_DIR <- "results/PCA_dispersal"   # change to e.g. "outputs" if desired
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)


# =============================================================================
# 2.  SET UP HISTORICAL DATA
# =============================================================================
if(!exists("r_template")){
  r_template <- terra::rast(template)
}

r_habitat  <- terra::rast(habitat_path)  # Dispersal resistance was multiplied by 10000
# r_habitat  <- r_habitat / 10000          # returning it to the 0-1 scale

r_elev     <- terra::rast(elevation_path)
r_veg      <- terra::rast(vegetation_path)
r_veg      <- subset(r_veg, time(r_veg) == as.Date("2015-01-01"))
names(r_veg) <- lucas_categores

# CRS MATCHING ----------------------------------------------------------------

r_habitat <- terra::project(r_habitat, terra::crs(r_template), method = "bilinear")
r_elev <- terra::project(r_elev, terra::crs(r_template), method = "bilinear")
r_veg  <- terra::project(r_veg,  terra::crs(r_template), method = "bilinear")

# EXTENT CROPPING -------------------------------------------------------------

r_habitat <- terra::crop(r_habitat, r_template)
r_elev <- terra::crop(r_elev, r_template)
r_veg  <- terra::crop(r_veg,  r_template)

# RESCALE ---------------------------------------------------------------------

r_habitat <- terra::resample(r_habitat, r_template, method = "bilinear")
r_elev <- terra::resample(r_elev, r_template, method = "bilinear")
r_veg  <- terra::resample(r_veg,  r_template, method = "bilinear")

names(r_habitat)  <- "dispersal.resistance"
names(r_elev) <- "elevation"

# =============================================================================
# 3.  PCA
# =============================================================================

full_stack <- c(r_habitat, r_elev, r_veg)
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
  "log(dispersal.resistance) ~ s(elevation, k = %d, bs = 'cr') + %s + s(x, y, k = %d, bs = 'tp')",
  UNIVAR_K, pc_smooth_terms, SPATIAL_K
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

hist <- predict_dispersal(veg_rast = hist_r, elev_rast = dem, template_raster = r_template, 
                                    pca_path = pca, gam_path = gam, output_path = file.path(OUT_DIR, "dispersal_historic.tif")) 


lucas_fut_245  <- terra::crop(lucas_fut_245, ext(-11, 3.4, 34, 45))
lucas_fut_245  <- terra::project(lucas_fut_245,  terra::crs(r_template), method = "bilinear")
lucas_fut_245  <- terra::crop(lucas_fut_245,  r_template)

for(d in unique(time(lucas_fut_245))) {
  print(as.Date(d))
  fut_r <- subset(lucas_fut_245, time(lucas_fut_245) == as.Date(d))
  names(fut_r) <- lucas_categores
  output_file <- file.path(OUT_DIR, "ssp245", paste0("Lynx_dispersal_", year(as.Date(d)), ".tif"))
  predict_dispersal(veg_rast = fut_r, elev_rast = dem, template_raster = r_template,
                              pca_path = pca, gam_path = gam, output_path = output_file)
  
}

lucas_fut_585  <- terra::crop(lucas_fut_585, ext(-11, 3.4, 34, 45))
lucas_fut_585  <- terra::project(lucas_fut_585,  terra::crs(r_template), method = "bilinear")
lucas_fut_585  <- terra::crop(lucas_fut_585,  r_template)

for(d in unique(time(lucas_fut_585))[c(42:85)]) {
  print(as.Date(d))
  fut_r <- subset(lucas_fut_585, time(lucas_fut_585) == as.Date(d))
  names(fut_r) <- lucas_categores
  output_file <- file.path(OUT_DIR, "ssp585", paste0("Lynx_dispersal_", year(as.Date(d)), ".tif"))
  predict_dispersal(veg_rast = fut_r, elev_rast = dem, template_raster = r_template,
                              pca_path = pca, gam_path = gam, output_path = output_file)
  
}


# ggplot() +
#   geom_sf(data = world_cropped, fill = "grey90", color = "grey30", linewidth = 0.3) +
#   geom_spatraster(data = hist$predicted) +
#   scale_fill_viridis_b(limits = c(0, 0.9),
#                        # oob = scales::oob_squish,
#                        na.value = NA) +
#   theme_minimal()

# =============================================================================
# 6.  Create Category Maps
# =============================================================================

COR <- rast("data/GIS_maps/Lynx_HabitatMap_500_Peninsula_Revilla_2015_1.asc")
df <- data.frame(
  disp_res = values(r_habitat),
  disp_pred = values(hist$predicted),
  corine = as.factor(values(COR))
) %>% 
  rename(disp_res = dispersal.resistance,
         disp_pred = predicted_dispersal) 

# pres <- MASS::polr(corine ~ disp_res, data = df%>%
#                      na.omit(), Hess=T)
# vpRes  <- rep(NA, nrow(pred_df))
# vpRes[!is.na(df$disp_res)] <- predict(pres, newdata = df[!is.na(df$disp_res), , drop = FALSE], type = "class")
# r_notit <- rast(r_habitat)  # copy extent, resolution, CRS
# values(r_notit) <- as.integer(vpRes)
# plot(r_notit)


ppred <- MASS::polr(corine ~ disp_pred, data = df%>%
                      na.omit(), Hess=T)

vpPred <- rep(NA, nrow(df))
vpPred[!is.na(df$disp_pred)] <- predict(ppred, newdata = df[!is.na(df$disp_pred), , drop = FALSE], type = "class")
r_hist_cat <- rast(r_habitat)  # copy extent, resolution, CRS
values(r_hist_cat) <- vpPred
r_hist_cat <- r_hist_cat - 1
plot(r_hist_cat)



pred_files <- setdiff(list.files(file.path(OUT_DIR), pattern = ".tif", recursive = T, full.names = T),
                      list.files(file.path(OUT_DIR), pattern = "extrapolation_risk.tif", recursive = T, full.names = T))


df_new <- data.frame(
  corine = as.factor(values(COR))
)


lapply(pred_files, function(x) {
  r <- rast(x)
  
  df_new$disp_pred = values(r)[,1]
  
  vpPred <- rep(NA, nrow(df_new))
  vpPred[!is.na(df_new$disp_pred)] <- predict(ppred, newdata = df_new[!is.na(df_new$disp_pred), , drop = FALSE], type = "class")
  values(r) <- as.integer(vpPred)
  r <- r - 1
  
  f <- gsub(OUT_DIR, "data/GIS_maps/PCA_dispersal", tools::file_path_sans_ext(x))
  f <- paste0(f, ".asc")
  
  writeRaster(r, f, datatype = "INT2S", overwrite = TRUE, NAflag = -9999)
  
  finput <- gsub(OUT_DIR, "data/model_input/maps", tools::file_path_sans_ext(x))
  finput <- paste0(finput, ".txt")
  
  transform_asc_file(f, finput)
})

