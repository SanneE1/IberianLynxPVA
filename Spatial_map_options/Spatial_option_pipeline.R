# ----------------------------------------------------------------------------
# Spatial map options
#
# Creates the historical (2015) habitat and breeding habitat maps for each of
# the spatial methods in this repository, so they can be compared:
#   1. Revilla 2015 habitat (option 1 and 2)  - CORINE reclassification
#   2. Fordham 2013 breeding habitat          - CORINE reclassification
#   3. PCA dispersal                          - GAM on Cisneros dispersal resistance
#   4. PCA habitat                            - GAM on Cisneros surface, breeding habitat
#   5. Land cover prediction                  - GAM on Cisneros habitat selection
#
# Every map is saved in Spatial_map_options/data/ as .asc and as model input .txt.
# The GAM-based methods also save the continuous prediction as .tif, and their
# fitted model + cut-offs as .rds for the future projections.
#
# Run from the repository root:
#   Rscript Spatial_map_options/Spatial_option_pipeline.R
# ----------------------------------------------------------------------------

library(terra)

set.seed(2026)

#----------------------------------------
# Settings (update these)
#----------------------------------------

# Which methods to run
run_revilla     <- TRUE
run_fordham     <- TRUE
run_pca_disp    <- TRUE
run_pca_habitat <- TRUE
run_landcover   <- TRUE

# Input data
template_path   <- "data/GIS_maps/Peninsula_500_template.tif"
corine_path     <- "data/original_data/U2018_CLC2018_V2020_20u1.tif"
elevation_path  <- "data/original_data/Copernicus_GLO90_Europe_250m.tif"
vegetation_path <- "data/original_data/LUC_historic_landcover/LUCAS_LUC_v1.1_historical_Europe_0.1deg_2010_2015.nc"
road_path       <- "data/original_data/OSM_road_density.tif"
road_cache_dir  <- "data/original_data/OSM_chache/"
presence_dir    <- "data/original_data/20250825_data_German/Presencias/"

# Cisneros-Araujo et al. (2025) surfaces the GAMs are fitted to
dispersal_path   <- "data/original_data/Lynx_movement_resistance_maps_Pablo_Cisneros/capas/res_lince_w_2025.tif"
pca_habitat_path <- "data/original_data/Lynx_movement_resistance_maps_Pablo_Cisneros/capas/res_lince_w_2025.tif"  # as in the original PCA_habitat.R (possibly meant to be habitat_lince_PI_2025.tif)
landcover_path   <- "data/original_data/Lynx_movement_resistance_maps_Pablo_Cisneros/capas/habitat_lince_PI_2025.tif"

# Only observed values below these are used to find the breeding habitat cut-off
pca_habitat_max_value <- 100
landcover_max_value   <- 60

# Output folder
out_dir <- "Spatial_map_options/data"

lucas_categories <- c("Tropical.broadleaf.evergreen.trees", "Tropical.deciduous.trees",
                      "Temperate.broadleaf.evergreen.trees", "Temperate.deciduous.trees",
                      "Evergreen.coniferous.trees", "Deciduous.coniferous.trees",
                      "Coniferous.shrubs", "Deciduous.shrubs", "C3.grass", "C4.grass",
                      "Tundra", "Swamp", "Non.irrigated.crops", "Irrigated.crops",
                      "Urban", "Bare")

#----------------------------------------
# Functions and shared inputs
#----------------------------------------

for (f in list.files("Spatial_map_options/functions", pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

template <- rast(template_path)

# The GAM methods share the same predictors (elevation, 2015 land cover, road density)
if (run_pca_disp || run_pca_habitat || run_landcover) {
  elev <- load_elevation(elevation_path, template)
  veg  <- load_lucas_2015(vegetation_path, lucas_categories, template)
  road <- get_road_density(road_path, road_cache_dir, template)
}

#----------------------------------------
# 1. Revilla 2015 habitat
#----------------------------------------
# CORINE classes reclassified to 0 = barrier, 1 = matrix, 2 = dispersal habitat.
# Option 1 is also used as the reference categories for the PCA dispersal map.

if (run_revilla || run_pca_disp) {
  corine <- crop(rast(corine_path), template)

  revilla_1 <- reclassify_revilla(corine, rast(template), option = 1)
  revilla_2 <- reclassify_revilla(corine, rast(template), option = 2)

  if (run_revilla) {
    write_model_map(revilla_1, "Lynx_HabitatMap_Revilla_2015_1", out_dir)
    write_model_map(revilla_2, "Lynx_HabitatMap_Revilla_2015_2", out_dir)
  }
}

#----------------------------------------
# 2. Fordham 2013 breeding habitat
#----------------------------------------
# CORINE classes 28 and 29 = breeding habitat (1), everything else 0.

if (run_fordham) {
  if (!exists("corine")) corine <- crop(rast(corine_path), template)

  fordham <- reclassify_fordham(corine, rast(template))
  write_model_map(fordham, "Lynx_BreedingHabitat_Fordham_2013", out_dir)
}

#----------------------------------------
# 3. PCA dispersal
#----------------------------------------
# GAM predicting the Cisneros dispersal resistance from vegetation PCs,
# elevation and roads. The prediction is split into 0/1/2 with the resistance
# cut-offs that best match the Revilla (option 1) categories.

if (run_pca_disp) {
  cat("== PCA dispersal\n")
  observed <- align_to_template(rast(dispersal_path), template)

  fit  <- fit_pca_gam(observed, elev, veg, road)
  pred <- predict_pca_gam(fit, elev, veg, road, template)
  writeRaster(pred, file.path(out_dir, "PCA_dispersal_resistance_historic.tif"), overwrite = TRUE)

  cutoffs  <- find_dispersal_cutoffs(observed, revilla_1)
  pca_disp <- apply_dispersal_cutoffs(pred, cutoffs)
  write_model_map(pca_disp, "Lynx_HabitatMap_PCA_dispersal_historic", out_dir, NAflag = -9999)

  # Fit and cut-offs, for the future projections (functions/future_projections.R)
  saveRDS(list(fit = fit, cutoffs = cutoffs), file.path(out_dir, "PCA_dispersal_fit.rds"))
}

#----------------------------------------
# 4. PCA habitat
#----------------------------------------
# Same GAM approach, fitted to the surface in pca_habitat_path. The prediction is
# split into breeding habitat (1) / other (0) with the cut-off that best separates
# cells with and without observed lynx presence.

if (run_pca_habitat || run_landcover) {
  presence <- get_presence_raster(presence_dir, template)
}

if (run_pca_habitat) {
  cat("== PCA habitat\n")
  observed <- align_to_template(rast(pca_habitat_path), template)

  fit  <- fit_pca_gam(observed, elev, veg, road)
  pred <- predict_pca_gam(fit, elev, veg, road, template)
  writeRaster(pred, file.path(out_dir, "PCA_habitat_prediction_historic.tif"), overwrite = TRUE)

  cutoff  <- find_breeding_cutoff(observed, presence, max_value = pca_habitat_max_value)
  pca_hab <- apply_breeding_cutoff(pred, cutoff, low_is_suitable = TRUE)
  write_model_map(pca_hab, "Lynx_BreedingHabitat_PCA_habitat_historic", out_dir, NAflag = -9999)

  saveRDS(list(fit = fit, cutoff = cutoff), file.path(out_dir, "PCA_habitat_fit.rds"))
}

#----------------------------------------
# 5. Land cover prediction
#----------------------------------------
# GAM predicting the Cisneros habitat selection surface from 5 grouped land
# cover types, elevation and roads. High values = selected habitat, so cells
# above the presence-based cut-off become breeding habitat (1).

if (run_landcover) {
  cat("== Land cover prediction\n")
  observed  <- align_to_template(rast(landcover_path), template)
  landcover <- group_landcover(veg)

  gam  <- fit_landcover_gam(observed, elev, landcover, road)
  pred <- predict_gam_map(gam, c(elev, landcover, road), template)
  writeRaster(pred, file.path(out_dir, "LandCover_habitat_prediction_historic.tif"), overwrite = TRUE)

  cutoff <- find_breeding_cutoff(observed, presence, max_value = landcover_max_value)
  lc_hab <- apply_breeding_cutoff(pred, cutoff, low_is_suitable = FALSE)
  write_model_map(lc_hab, "Lynx_BreedingHabitat_LandCover_historic", out_dir, NAflag = -9999)

  saveRDS(list(gam = gam, cutoff = cutoff), file.path(out_dir, "LandCover_fit.rds"))
}

cat("\nDone. Maps saved in", out_dir, "\n")

#----------------------------------------
# Future projections
#----------------------------------------
# Not run here. The fits saved above can be projected onto the LUCAS land cover
# scenarios (SSP2-4.5, SSP5-8.5) with the functions in functions/future_projections.R;
# see the header of that file for how to use them.
