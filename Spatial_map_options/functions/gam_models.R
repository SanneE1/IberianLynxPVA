# ----------------------------------------------------------------------------
# GAM models that predict the Cisneros-Araujo et al. (2025) surfaces from land
# cover, elevation and road density:
#   - PCA option:        vegetation layers summarised by a PCA (PCA dispersal / PCA habitat)
#   - Land cover option: vegetation layers grouped into 5 cover types (land cover prediction)
# ----------------------------------------------------------------------------

# Predict a fitted GAM onto the template grid (x and y are added for the spatial smooth)
predict_gam_map <- function(gam, predictors, template) {
  x <- init(template, "x")
  y <- init(template, "y")
  names(x) <- "x"
  names(y) <- "y"

  predict_fun <- function(model, data, ...) {
    mgcv::predict.bam(model, newdata = data, type = "response", ...)
  }

  terra::predict(c(predictors, x, y), gam, fun = predict_fun, na.rm = TRUE)
}

# Keep only mainland Spain and Portugal
mask_to_iberia <- function(r, cache_dir = tempdir()) {
  iberia <- rbind(geodata::gadm("ESP", level = 0, path = cache_dir),
                  geodata::gadm("PRT", level = 0, path = cache_dir))
  mask(r, project(iberia, crs(r)))
}

#----------------------------------------
# PCA option
#----------------------------------------

# log(response) ~ s(elevation) + s(road density) + s(PC1) + ... + s(x, y)
fit_pca_gam <- function(response, elev, veg, road,
                        var_threshold = 0.90, max_pcs = 10,
                        spatial_k = 400, univar_k = 20, sample_fraction = 0.10) {
  names(response) <- "response"
  df_full <- as.data.frame(c(response, elev, veg, road), xy = TRUE, na.rm = TRUE)

  # PCA on the vegetation layers (dropping layers without variation)
  veg_matrix <- as.matrix(df_full[, names(veg)])
  veg_matrix <- veg_matrix[, apply(veg_matrix, 2, var) >= 1e-10, drop = FALSE]
  pca <- prcomp(veg_matrix, center = TRUE, scale. = TRUE)

  var_cum <- cumsum(pca$sdev^2) / sum(pca$sdev^2)
  n_pcs <- min(which(var_cum >= var_threshold)[1], max_pcs, ncol(pca$rotation))
  pc_names <- paste0("PC", seq_len(n_pcs))
  cat(sprintf("  Retaining %d PC(s), explaining %.1f%% of vegetation variance\n",
              n_pcs, var_cum[n_pcs] * 100))

  pc_scores <- predict(pca, newdata = veg_matrix)[, seq_len(n_pcs), drop = FALSE]
  colnames(pc_scores) <- pc_names
  df_full <- cbind(df_full, pc_scores)

  # Fit the GAM on a random sample of cells
  n_sample <- min(max(10000L, as.integer(nrow(df_full) * sample_fraction)), nrow(df_full))
  df_train <- df_full[sample(nrow(df_full), n_sample), ]

  gam_formula <- as.formula(sprintf(
    "log(response) ~ s(elevation, k = %d, bs = 'cr') + s(road_density_presence_3x3, k = 10, bs = 'cr') + %s + s(x, y, k = %d, bs = 'tp')",
    univar_k,
    paste(sprintf("s(%s, k = %d, bs = 'cr')", pc_names, univar_k), collapse = " + "),
    spatial_k))

  gam <- mgcv::bam(gam_formula, family = gaussian(), data = df_train,
                   method = "fREML", discrete = TRUE,
                   nthreads = max(1L, parallel::detectCores() - 1L))
  cat(sprintf("  Deviance explained: %.2f%%\n", summary(gam)$dev.expl * 100))

  # pc_center and pc_cov describe the training data in PC space; they are used
  # to calculate the extrapolation risk of future land cover (see pca_extrapolation_risk)
  list(pca = pca, veg_cols = colnames(veg_matrix), pc_names = pc_names, gam = gam,
       pc_center = colMeans(df_train[, pc_names, drop = FALSE]),
       pc_cov = cov(df_train[, pc_names, drop = FALSE]))
}

# Project the vegetation layers onto the PCs retained in the fit.
# Vegetation layers must be named as in the training data (the LUCAS categories).
project_veg_to_pcs <- function(fit, veg, template) {
  veg_vals <- values(veg[[fit$veg_cols]])
  ok <- complete.cases(veg_vals)
  pcs <- matrix(NA_real_, nrow(veg_vals), length(fit$pc_names))
  pcs[ok, ] <- predict(fit$pca, newdata = veg_vals[ok, , drop = FALSE])[, seq_along(fit$pc_names)]

  r_pcs <- rast(template, nlyrs = length(fit$pc_names))
  values(r_pcs) <- pcs
  names(r_pcs) <- fit$pc_names
  r_pcs
}

# Prediction on the original scale (the GAM is fitted on log(response))
predict_pca_gam <- function(fit, elev, veg, road, template) {
  r_pcs <- project_veg_to_pcs(fit, veg, template)
  pred <- exp(predict_gam_map(fit$gam, c(elev, road, r_pcs), template))
  mask_to_iberia(pred)
}

# Extrapolation risk: Mahalanobis distance of each cell's vegetation (in PC space)
# to the training data. Large values = land cover unlike anything the GAM was fitted on.
pca_extrapolation_risk <- function(fit, veg, template) {
  pcs <- values(project_veg_to_pcs(fit, veg, template))
  ok <- complete.cases(pcs)

  risk <- rast(template)
  risk_vals <- rep(NA_real_, nrow(pcs))
  risk_vals[ok] <- mahalanobis(pcs[ok, , drop = FALSE], center = fit$pc_center, cov = fit$pc_cov)
  values(risk) <- risk_vals
  names(risk) <- "mahalanobis_distance"

  mask_to_iberia(risk)
}

#----------------------------------------
# Land cover option
#----------------------------------------

# Group the 16 LUCAS layers into 5 cover types
group_landcover <- function(veg) {
  lc <- c(sum(veg[[1:6]]),     # trees
          sum(veg[[7:8]]),     # shrubs
          sum(veg[[9:10]]),    # grasses
          veg[[15]],           # urban
          sum(veg[[13:14]]))   # crops
  names(lc) <- c("trees", "shrubs", "grasses", "imperviousness", "crops")
  lc
}

# response ~ s(x, y) + s(elevation) + s(each cover type) + s(road density)
fit_landcover_gam <- function(response, elev, landcover, road, sample_fraction = 0.30) {
  names(response) <- "response"
  df_full <- as.data.frame(c(response, elev, landcover, road), xy = TRUE, na.rm = TRUE)

  n_sample <- min(max(10000L, as.integer(nrow(df_full) * sample_fraction)), nrow(df_full))
  df_train <- df_full[sample(nrow(df_full), n_sample), ]

  gam <- mgcv::bam(response ~ s(x, y, bs = "tp") + s(elevation) +
                     s(trees) + s(shrubs) + s(grasses) + s(imperviousness) +
                     s(crops) + s(road_density_presence_3x3),
                   family = gaussian(), data = df_train,
                   method = "fREML", discrete = TRUE,
                   nthreads = max(1L, parallel::detectCores() - 1L))
  cat(sprintf("  Deviance explained: %.2f%%\n", summary(gam)$dev.expl * 100))
  gam
}
