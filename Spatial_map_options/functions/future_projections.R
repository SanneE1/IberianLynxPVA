# ----------------------------------------------------------------------------
# Future projections (2016-2100) for the GAM-based spatial methods
#
# The GAMs are fitted once on the historical data (Spatial_option_pipeline.R,
# which saves each fit and its cut-offs as .rds in Spatial_map_options/data/).
# For the future, only the land cover changes: elevation and road density are
# kept at their current values, and the vegetation layers are replaced by the
# LUCAS land cover projections for SSP2-4.5 or SSP5-8.5.
#
# Required inputs:
#   future_dir  folder with the LUCAS projections, one .nc file per decade, e.g.
#               data/original_data/LUC_future_landcover/LUCAS_LUC_v1.1_ssp585_Europe_0.1deg_2016_2025.nc
#               Each year has 16 layers, in the same order as lucas_categories.
#
# Typical use (after running Spatial_option_pipeline.R; objects as defined there):
#
#   lucas_585 <- load_lucas_future("data/original_data/LUC_future_landcover", "ssp585", template)
#   # or only some years: load_lucas_future(..., years = c(2025, 2050, 2100))
#
#   # PCA dispersal: continuous prediction, extrapolation risk and 0/1/2 categories
#   pca_disp <- readRDS("Spatial_map_options/data/PCA_dispersal_fit.rds")
#   pred <- predict_pca_gam_future(pca_disp$fit, elev, road, lucas_585, template)
#   risk <- pca_extrapolation_risk_future(pca_disp$fit, lucas_585, template)
#   maps <- apply_dispersal_cutoffs(pred, pca_disp$cutoffs)
#   write_future_maps(maps, "Spatial_map_options/data/SSP585/PCA_dispersal", "Lynx_HabitatMap")
#
#   # PCA habitat: breeding habitat 0/1
#   pca_hab <- readRDS("Spatial_map_options/data/PCA_habitat_fit.rds")
#   pred <- predict_pca_gam_future(pca_hab$fit, elev, road, lucas_585, template)
#   maps <- apply_breeding_cutoff(pred, pca_hab$cutoff, low_is_suitable = TRUE)
#   write_future_maps(maps, "Spatial_map_options/data/SSP585/PCA_habitat", "Lynx_BreedingMap")
#
#   # Land cover prediction: breeding habitat 0/1
#   lc <- readRDS("Spatial_map_options/data/LandCover_fit.rds")
#   pred <- predict_landcover_gam_future(lc$gam, elev, road, lucas_585, template)
#   maps <- apply_breeding_cutoff(pred, lc$cutoff, low_is_suitable = FALSE)
#   write_future_maps(maps, "Spatial_map_options/data/SSP585/LandCover", "Lynx_BreedingMap")
#
# Model file names: the IBM reads yearly maps from a folder, named
#   habitat_folder  -> Lynx_HabitatMap_<year>.txt   (dispersal habitat, 0/1/2)
#   breeding_folder -> Lynx_BreedingMap_<year>.txt  (breeding habitat, 0/1)
# so use those prefixes in write_future_maps() if the maps are used in the model.
#
# Each year takes a full GAM prediction over the peninsula, so a full scenario
# (85 years) takes a long time; run it on the HPC.
# ----------------------------------------------------------------------------

#----------------------------------------
# Input data
#----------------------------------------

# Load the LUCAS land cover projections for one scenario ("ssp245" or "ssp585"),
# cropped to Iberia and aligned to the template grid. Returns a stack with 16
# layers per year; the year of each layer is stored in time().
# years: optional subset, e.g. c(2025, 2050, 2100). Loading all 85 years is slow.
load_lucas_future <- function(future_dir, scenario, template, years = NULL) {
  files <- list.files(future_dir, pattern = paste0(scenario, ".*\\.nc$"), full.names = TRUE)
  lucas <- rast(lapply(files, rast))

  if (!is.null(years)) {
    lucas <- subset(lucas, as.integer(format(time(lucas), "%Y")) %in% years)
  }

  # Crop in lon/lat first (much faster than projecting the whole of Europe)
  lucas <- crop(lucas, ext(-11, 3.4, 34, 45))
  lucas <- align_to_template(lucas, template)

  cat("  Loaded", scenario, "land cover for", length(unique(time(lucas))), "years\n")
  lucas
}

# The 16 vegetation layers of one year, named as in the training data
lucas_year <- function(lucas, date, categories = lucas_categories) {
  veg <- subset(lucas, time(lucas) == date)
  names(veg) <- categories
  veg
}

# Apply a function to each year of the land cover projection and return a stack
# with one layer per year (the year is stored in time() and in the layer name)
map_over_years <- function(lucas, year_fun, categories = lucas_categories) {
  dates <- sort(unique(time(lucas)))

  out <- lapply(dates, function(d) {
    cat("  ", format(d, "%Y"), "\n")
    wrap(year_fun(lucas_year(lucas, d, categories)))
  })

  out <- rast(lapply(out, unwrap))
  time(out) <- dates
  names(out) <- format(dates, "%Y")
  out
}

#----------------------------------------
# Predictions
#----------------------------------------

# PCA methods (PCA dispersal, PCA habitat): prediction on the original scale
predict_pca_gam_future <- function(fit, elev, road, lucas, template, categories = lucas_categories) {
  map_over_years(lucas, function(veg) predict_pca_gam(fit, elev, veg, road, template), categories)
}

# PCA methods: extrapolation risk per year (Mahalanobis distance to the training data)
pca_extrapolation_risk_future <- function(fit, lucas, template, categories = lucas_categories) {
  map_over_years(lucas, function(veg) pca_extrapolation_risk(fit, veg, template), categories)
}

# Land cover method: the 16 LUCAS layers are grouped into 5 cover types each year
predict_landcover_gam_future <- function(gam, elev, road, lucas, template, categories = lucas_categories) {
  map_over_years(lucas, function(veg) {
    predict_gam_map(gam, c(elev, group_landcover(veg), road), template)
  }, categories)
}

#----------------------------------------
# Output
#----------------------------------------

# Save each year of a categorised stack as <prefix>_<year>.asc and .txt
write_future_maps <- function(maps, out_dir, prefix) {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  years <- format(time(maps), "%Y")

  for (i in seq_len(nlyr(maps))) {
    write_model_map(maps[[i]], paste0(prefix, "_", years[i]), out_dir, NAflag = -9999)
  }
}
