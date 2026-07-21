# =============================================================================
# Dispersal Resistance ~ Land Cover: Correlation & Delta/Anomaly Projection
# =============================================================================
# Workflow:
#   1. Load inputs (fine resistance + coarse land cover stacks)
#   2. Aggregate resistance to coarse grid (zonal stats per LC cell)
#   3. Spatial correlation diagnostics (Moran's I)
#   4. Multiple linear regression: resistance ~ land cover %
#   5. Delta/anomaly projection → per-year fine-resolution resistance rasters
#   6. Save outputs + summary plots
#
# Input assumptions:
#   - resistance raster   : single-band GeoTIFF, fine resolution, single year
#   - land cover rasters  : one file per cover type × year, same coarse CRS/extent
#                           naming convention: "lc_<type>_<year>.tif"
#                           values are % cover (0–100)
#   - All rasters share the same CRS (reproject beforehand if not)
# =============================================================================

library(terra)       # raster I/O, resampling, algebra
library(dplyr)       # data wrangling
library(tidyr)       # pivoting
library(ggplot2)     # plotting
library(tidyterra)   # plotting for terra
library(ggcorrplot)  # correlation matrix plot
library(spdep)       # spatial autocorrelation (Moran's I)
library(car)         # VIF
library(patchwork)   # plot composition

# =============================================================================
# 0. Configuration — edit these paths and parameters
# =============================================================================

# --- Paths ---
template         <- "data/GIS_maps/Peninsula_500_template.tif"
resistance_path  <- "data/original_data/Lynx_movement_resistance_maps_Pablo_Cisneros/capas/res_lince_w_2025.tif"          # fine-resolution resistance
output_dir       <- "data/GIS_maps/resistance_LUCAS_scaling/"
dir.create(output_dir, showWarnings = FALSE)

nc_files <- list.files("data/original_data/LUC_future_landcover/", pattern = "ssp585.*\\.nc$", full.names = TRUE)

# Define the start year of each file so you can reconstruct absolute years:
file_start_years <- seq(2016, 2100, by = 10)   # one per nc file, in order

# --- Years available in the land cover dataset ---
lc_years <- 2016:2100

# --- Baseline year (should overlap or be closest to resistance raster year) ---
baseline_year <- 2016

# --- Projection method: "multiplicative" or "additive" ---
# multiplicative: projected = baseline_resistance × (pred_t / pred_baseline)
# additive:       projected = baseline_resistance + (pred_t − pred_baseline)
delta_method <- "multiplicative"

# --- Resampling method for coarse→fine delta surface ---
# "bilinear" (smooth, recommended) or "cubicspline" (slightly sharper)
resample_method <- "bilinear"

# --- Regression: drop one LC type as reference (avoids perfect multicollinearity) ---
n_cover_types    <- c(4:16)
reference_type   <- "lc3" 

# =============================================================================
# 1. Load rasters
# =============================================================================
cat("\n--- Loading NetCDF rasters ---\n")

resistance <- rast(resistance_path)
resistance <- app(resistance > 100, 100, resistance)

# Build lc_stack[[type_number]] = SpatRaster with layers named by absolute year
lc_stack <- vector("list", length(n_cover_types))

for (fi in seq_along(nc_files)) {
  r_all       <- rast(nc_files[fi])          # all layers in this .nc file
  layer_names <- names(r_all)
  start_yr    <- file_start_years[fi]
  
  # Parse cover type and within-file year index from layer names
  # Format: "landCoverFrac_lctype=<type>_<idx>"
  parsed <- regmatches(layer_names,
                       regexpr("lctype=(\\d+)_(\\d+)", layer_names))
  type_idx <- as.integer(sub("lctype=(\\d+)_.*",  "\\1", parsed))
  yr_idx   <- as.integer(sub("lctype=\\d+_(\\d+)", "\\1", parsed))
  abs_year <- start_yr + yr_idx - 1          # e.g. start 2016, idx 1 → 2016
  
  for (ct in seq_along(n_cover_types)) {
    match_layers <- which(type_idx == ct)
    if (length(match_layers) == 0) next
    
    r_ct       <- r_all[[match_layers]]
    names(r_ct) <- abs_year[match_layers]
    
    # Append to any layers already loaded from earlier files
    if (is.null(lc_stack[[ct]])) {
      lc_stack[[ct]] <- r_ct
    } else {
      lc_stack[[ct]] <- c(lc_stack[[ct]], r_ct)
    }
  }
  cat("  Loaded:", basename(nc_files[fi]), "— years",
      start_yr, "to", start_yr + 9, "\n")
}

names(lc_stack) <- paste0("lc", n_cover_types)

# Derive lc_years and lc_types from what was actually loaded
lc_years <- sort(unique(as.integer(names(lc_stack[[1]]))))
lc_types  <- names(lc_stack)   # "1" through "16"

cat("Cover types loaded:", length(lc_stack), "\n")
cat("Years spanned     :", paste(range(lc_years), collapse = "–"), "\n")


cat("\n--- Aligning LC rasters to resistance ---\n")

# Step 1: project resistance extent into LC CRS
#   (cheaper to transform a bounding box than to reproject the whole fine raster)
resistance_bbox_in_lc_crs <- project(ext(resistance), 
                                     from = crs(resistance), 
                                     to   = crs(lc_stack[[1]]))

# Step 2: expand slightly to avoid edge-clipping after later reprojection
#   (reprojecting a raster can shift cells by up to ~1 coarse pixel at the edges)
coarse_res     <- res(lc_stack[[1]])
expanded_bbox  <- ext(resistance_bbox_in_lc_crs) + c(-coarse_res[1], coarse_res[1],
                                                     -coarse_res[2], coarse_res[2])

# Step 3: crop + reproject every LC layer stack
lc_stack <- lapply(lc_stack, function(r) {
  r_crop <- crop(r, expanded_bbox)                   # crop in native LC CRS
  project(r_crop, crs(resistance), method = "bilinear")  # reproject to resistance CRS
})

cat("  LC stack aligned. New extent:\n")
print(ext(lc_stack[[1]]))
cat("  Resistance extent:\n")
print(ext(resistance))

# =============================================================================
# 2. Reproject resistance to LC CRS if needed, then aggregate to coarse grid
# =============================================================================

cat("\n--- Aggregating resistance to coarse grid ---\n")
r_template <- rast(template)

# Reproject resistance to LC CRS if they differ
if (!same.crs(r_template, resistance)) {
  cat("  Reprojecting resistance to LC CRS...\n")
  resistance <- project(resistance, crs(r_template), method = "bilinear")
}

if (!same.crs(r_template, lc_stack[[1]])) {
  cat("  Reprojecting resistance to LC CRS...\n")
  resistance <- project(lc_stack, crs(r_template), method = "bilinear")
}

# Create a template at the coarse LC resolution/extent
coarse_template <- lc_stack[[1]][[1]]

# Aggregate: resample resistance to coarse grid (mean of fine pixels per cell)
# Using "average" in terra's resample; for a true zonal mean we use resample
# with method = "average" which correctly averages all fine cells per coarse cell
resistance_coarse <- resample(resistance, coarse_template, method = "average")
names(resistance_coarse) <- "resistance"

cat("  Aggregated resistance shape:",
    nrow(resistance_coarse), "×", ncol(resistance_coarse), "\n")

# Also compute SD of fine pixels per coarse cell (used later as a weight)
resistance_sd <- resample(resistance, coarse_template, method = "rms")
names(resistance_sd) <- "resistance_sd"

# =============================================================================
# 3. Build regression data frame (coarse cells, baseline year)
# =============================================================================

cat("\n--- Building regression dataset (baseline year:", baseline_year, ")---\n")

# Extract coarse resistance values
df_reg <- as.data.frame(resistance_coarse, na.rm = FALSE)
df_reg$resistance_sd <- as.vector(values(resistance_sd))

# Add LC % cover for the baseline year
for (type in lc_types) {
  yr_idx <- which(names(lc_stack[[type]]) == as.character(baseline_year))
  if (length(yr_idx) == 0) stop("Baseline year not found in LC stack for type: ", type)
  df_reg[[type]] <- as.vector(values(lc_stack[[type]][[yr_idx]]))
}

# Remove cells where any layer is NA
complete_mask <- complete.cases(df_reg)
df_complete   <- df_reg[complete_mask, ]
cat("  Cells used for regression:", nrow(df_complete),
    "(", round(100 * mean(complete_mask), 1), "% of coarse grid )\n")

# Drop reference LC type to avoid perfect multicollinearity
predictors    <- setdiff(lc_types, reference_type)
formula_str   <- paste("resistance ~", paste(predictors, collapse = " + "))
cat("  Formula:", formula_str, "\n")

# =============================================================================
# 4. Spatial autocorrelation check (Moran's I on OLS residuals)
# =============================================================================

cat("\n--- Spatial autocorrelation diagnostics ---\n")

# Preliminary OLS
ols_fit <- lm(as.formula(formula_str), data = df_complete)

# Get cell coordinates for the non-NA coarse cells
coarse_coords <- as.data.frame(xyFromCell(resistance_coarse,
                                          which(complete_mask)))

# Build spatial weights (queen contiguity, k=8 neighbours)
nb   <- spdep::knearneigh(as.matrix(coarse_coords), k = 8)
nb   <- spdep::knn2nb(nb)
wts  <- spdep::nb2listw(nb, style = "W")

# Moran's I on OLS residuals
moran_result <- spdep::moran.test(residuals(ols_fit), wts)
cat("  Moran's I =", round(moran_result$estimate["Moran I statistic"], 4),
    " p =", format.pval(moran_result$p.value, digits = 3), "\n")

if (moran_result$p.value < 0.05) {
  cat("  ** Significant spatial autocorrelation detected.\n")
  cat("     Using spatial lag model (lagsarlm) for final regression.\n")
  use_spatial_model <- TRUE
} else {
  cat("  No significant spatial autocorrelation — using OLS.\n")
  use_spatial_model <- FALSE
}

# =============================================================================
# 5. Final regression model
# =============================================================================

cat("\n--- Fitting regression model ---\n")

if (use_spatial_model) {
  library(spatialreg)
  final_fit <- spatialreg::lagsarlm(as.formula(formula_str),
                                    data  = df_complete,
                                    listw = wts,
                                    method = "eigen")
  # Fitted values for later prediction
  fitted_vals <- fitted(final_fit)
} else {
  final_fit   <- ols_fit
  fitted_vals <- fitted(ols_fit)
}

cat("\n  Model summary:\n")
print(summary(final_fit))

# --- VIF (only meaningful for OLS) ---
if (!use_spatial_model) {
  cat("\n  Variance Inflation Factors:\n")
  print(car::vif(final_fit))
}

# Extract coefficients (works for both lm and lagsarlm)
coefs <- coef(final_fit)
cat("\n  Coefficients:\n")
print(round(coefs, 5))

# =============================================================================
# 6. Predict baseline resistance at coarse resolution
# =============================================================================

cat("\n--- Computing coarse predicted surfaces ---\n")

predict_coarse_year <- function(year) {
  # Build a SpatRaster with one band per predictor at the given year
  pred_layers <- lapply(predictors, function(type) {
    yr_idx <- which(names(lc_stack[[type]]) == as.character(year))
    if (length(yr_idx) == 0) {
      warning("Year ", year, " not found for type '", type, "' — using NA layer")
      r_na <- coarse_template
      values(r_na) <- NA
      return(r_na)
    }
    lc_stack[[type]][[yr_idx]]
  })
  names(pred_layers) <- predictors
  
  # Intercept + Σ βᵢ × coverᵢ
  pred_rast <- coarse_template
  values(pred_rast) <- coefs["(Intercept)"]
  
  for (type in predictors) {
    b <- if (type %in% names(coefs)) coefs[type] else 0
    pred_rast <- pred_rast + b * pred_layers[[type]]
  }
  
  # Spatial lag correction (ρ × Wy): approximate via global mean adjustment
  # Full correction requires matrix operations — for raster workflow we apply
  # the lag term as a spatially-smoothed adjustment using the lag parameter (ρ)
  if (use_spatial_model && "rho" %in% names(coefs)) {
    rho <- coefs["rho"]
    # Smooth predicted surface to approximate Wy (spatial lag of y)
    wy <- focal(pred_rast, w = matrix(1/8, 3, 3), fun = "mean", na.policy = "omit")
    pred_rast <- pred_rast + rho * wy
  }
  
  names(pred_rast) <- as.character(year)
  pred_rast
}

# Baseline predicted surface
pred_baseline <- predict_coarse_year(baseline_year)
cat("  Baseline predicted surface computed.\n")

# =============================================================================
# 7. Delta / anomaly projection at fine resolution
# =============================================================================

cat("\n--- Projecting resistance for all years (delta method) ---\n")

projected_list <- list()

for (yr in lc_years) {
  cat("  Year", yr, "... ")
  
  # Coarse predicted surface for this year
  pred_yr <- predict_coarse_year(yr)
  
  # Compute delta at coarse resolution
  if (delta_method == "multiplicative") {
    # Guard against division by zero
    delta_coarse <- ifel(pred_baseline == 0, 1, pred_yr / pred_baseline)
  } else {
    delta_coarse <- pred_yr - pred_baseline
  }
  
  # Resample delta to fine resolution (smooth interpolation — no false precision)
  delta_fine <- resample(delta_coarse, resistance, method = resample_method)
  
  # Apply delta to fine resistance raster
  if (delta_method == "multiplicative") {
    projected <- resistance * delta_fine
    # Clamp to sensible range: resistance cannot be negative
    projected <- ifel(projected < 0, 0, projected)
  } else {
    projected <- resistance + delta_fine
    projected <- ifel(projected < 0, 0, projected)
  }
  
  names(projected) <- paste0("resistance_", yr)
  projected_list[[as.character(yr)]] <- projected
  
  # Write to disk
  # out_path <- file.path(output_dir, paste0("resistance_projected_", yr, ".tif"))
  # writeRaster(projected, out_path, overwrite = TRUE)
  # 
  # cat("saved →", basename(out_path), "\n")
}

# Stack all projected years into a single multi-band raster
projected_stack <- rast(projected_list)
writeRaster(projected_stack, file.path("data", "GIS_maps", "resistance_LUCAS_scaling", "projected_stack.tiff"))

cat("\n  Full projected stack dimensions:", dim(projected_stack), "\n")

# =============================================================================
# 8. Diagnostics & visualisation
# =============================================================================

cat("\n--- Generating diagnostic plots ---\n")

# --- 8a. Correlation matrix (LC types + aggregated resistance, baseline year) ---
cor_data <- df_complete[, c("resistance", lc_types)]
cor_mat  <- cor(cor_data, use = "complete.obs")

p_corr <- ggcorrplot(cor_mat,
                     method   = "square",
                     type     = "lower",
                     lab      = TRUE,
                     lab_size = 3,
                     title    = paste("Correlation matrix — baseline", baseline_year),
                     ggtheme  = theme_minimal())

# --- 8b. Observed vs fitted (baseline) ---
obs_vs_fit <- data.frame(
  observed = df_complete$resistance,
  fitted   = fitted_vals
)

p_fit <- ggplot(obs_vs_fit, aes(x = fitted, y = observed)) +
  geom_hex(bins = 50) +
  geom_abline(slope = 1, intercept = 0, colour = "firebrick", linewidth = 0.8) +
  scale_fill_viridis_c(option = "magma", trans = "log1p") +
  labs(title = "Observed vs. fitted resistance (coarse, baseline year)",
       x = "Fitted (model)", y = "Observed (aggregated)") +
  theme_minimal()

# --- 8c. Residual map at coarse resolution ---
resid_rast <- resistance_coarse
resid_vals <- rep(NA, ncell(resid_rast))
resid_vals[complete_mask] <- residuals(final_fit)
values(resid_rast) <- resid_vals

p_resid_df <- as.data.frame(resid_rast, xy = TRUE, na.rm = TRUE)
names(p_resid_df) <- c("x", "y", "residual")

p_resid <- ggplot(p_resid_df, aes(x = x, y = y, fill = residual)) +
  geom_raster() +
  scale_fill_gradient2(low = "#2166ac", mid = "white", high = "#d6604d",
                       midpoint = 0, name = "Residual", transform = "pseudo_log") +
  coord_equal() +
  labs(title = "Regression residuals (coarse grid)") +
  theme_minimal() +
  theme(axis.title = element_blank())

# --- 8d. Mean projected resistance per year (time series) ---
yearly_means <- sapply(lc_years, function(yr) {
  global(projected_list[[as.character(yr)]], fun = "mean", na.rm = TRUE)[[1]]
})

p_timeseries <- ggplot(data.frame(year = lc_years, mean_resistance = yearly_means),
                       aes(x = year, y = mean_resistance)) +
  geom_line(colour = "#2166ac", linewidth = 1) +
  geom_point(colour = "#2166ac", size = 2) +
  geom_vline(xintercept = baseline_year, linetype = "dashed",
             colour = "firebrick", linewidth = 0.7) +
  annotate("text", x = baseline_year + 0.3, y = min(yearly_means),
           label = "baseline", hjust = 0, colour = "firebrick", size = 3) +
  labs(title = "Mean projected dispersal resistance over time",
       x = "Year", y = "Mean resistance") +
  theme_minimal()

# --- 8e. Coefficient bar chart ---
coef_df <- data.frame(
  type        = names(coefs)[names(coefs) %in% lc_types],
  coefficient = coefs[names(coefs) %in% lc_types]
)

p_coefs <- ggplot(coef_df, aes(x = reorder(type, coefficient),
                               y = coefficient,
                               fill = coefficient > 0)) +
  geom_col(width = 0.6) +
  scale_fill_manual(values = c("TRUE" = "#d6604d", "FALSE" = "#2166ac"),
                    guide = "none") +
  coord_flip() +
  labs(title = "Regression coefficients by land cover type",
       x = NULL, y = "Coefficient (effect on resistance)") +
  theme_minimal()

# --- Combine and save ---
layout <- (p_corr | p_coefs) / (p_fit | p_resid) / p_timeseries
layout <- p_corr + p_coefs + p_resid + p_timeseries + plot_layout()

ggsave(file.path(output_dir, "diagnostic_plots.pdf"),
       plot   = layout,
       width  = 14,
       height = 16,
       device = "pdf")

cat("  Saved: diagnostic_plots.pdf\n")


# =============================================================================
# 8. Change to dispersal categories
# =============================================================================
r_temp <- rast(template)

disp_for <- rast(file.path("data", "GIS_maps", "resistance_LUCAS_scaling", "projected_stack.tiff"))
COR <- rast("data/GIS_maps/Lynx_HabitatMap_500_Peninsula_Revilla_2015_1.asc")
COR <- project(COR, crs(disp_for), method = "max")
r_temp <- rast(template)
r_temp <- project(r_temp, crs(disp_for))

disp_for <- resample(disp_for, r_temp)

COR <- resample(COR, r_temp)

ggplot() +
  geom_spatraster(data = disp_for$`2016`) + 
  scale_fill_viridis_c(transform = "sqrt",
                       limits   = c(0, 100),
                       oob      = scales::squish)

df <- data.frame(
  disp_pred = values(disp_for$`2016`),
  corine = as.factor(values(COR))
) %>% 
  rename(disp_pred = X2016) 

ppred <- MASS::polr(corine ~ disp_pred, data = df%>%
                      na.omit(), Hess=T)



for (n in names(disp_for)) {
  df_new <- data.frame(
    disp_pred = values(disp_for[[n]]),
    corine = as.factor(values(COR))
  ) 
  colnames(df_new)[1] <- "disp_pred"
  
  vpPred <- rep(NA, nrow(df_new))
  vpPred[!is.na(df_new$disp_pred)] <- predict(ppred, newdata = df_new[!is.na(df_new$disp_pred), , drop = FALSE], type = "class")
  
  r <- disp_for[[n]]
  values(r) <- as.integer(vpPred)
  
  f <- file.path("data", "GIS_maps", "Delta_dispersal", paste0("Lynx_HabitatMap_", n, ".asc"))
  finput <- file.path("data", "model_input", "maps", "Delta_dispersal", paste0("Lynx_HabitatMap_", n, ".txt"))
  
  writeRaster(r, f, datatype = "INT2S", overwrite = TRUE, NAflag = -9999)
  
  transform_asc_file(f, finput)
}