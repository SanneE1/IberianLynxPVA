# Predict habitat suitability from PCA axis based on LUCAS vegetation categories and elevation using a GAM

predict_habitat_suitability <- function(
    veg_rast,
    elev_rast,
    template_raster,
    pca_path     = "veg_pca.rds",
    gam_path     = "gam_model.rds",
    output_path  = "predicted_habitat.tif",
    pca_var_threshold = PCA_VAR_THRESHOLD,
    pca_max_pcs       = PCA_MAX_PCS
) {
  
  cat("\n=== Prediction ===\n")
  
  # Load saved objects
  pca_obj  <- readRDS(pca_path)
  gam_obj  <- readRDS(gam_path)
  r_tmpl   <- template_raster
  
  # Determine how many PCs the GAM was trained on
  gam_pc_terms <- grep("^PC[0-9]+$", names(gam_obj$var.summary), value = TRUE)
  n_pc_gam     <- length(gam_pc_terms)
  cat(sprintf("  GAM expects %d PC(s): %s\n", n_pc_gam,
              paste(gam_pc_terms, collapse = ", ")))
  
  # Load rasters
  r_veg  <- veg_rast
  r_elev <- elev_rast
  
  if (!terra::same.crs(r_veg,  r_tmpl)) r_veg  <- terra::project(veg_rast,  terra::crs(r_tmpl), method = "bilinear")
  if (!terra::same.crs(r_elev, r_tmpl)) r_elev <- terra::project(r_elev, terra::crs(r_tmpl), method = "bilinear")
  
  r_veg  <- terra::crop(r_veg,  r_tmpl)
  r_elev <- terra::crop(r_elev, r_tmpl)
  
  xy_all <- terra::xyFromCell(r_tmpl, seq_len(terra::ncell(r_tmpl)))
  
  r_x <- terra::rast(r_tmpl); terra::values(r_x) <- xy_all[, 1]; names(r_x) <- "x"
  r_y <- terra::rast(r_tmpl); terra::values(r_y) <- xy_all[, 2]; names(r_y) <- "y"
  
  
  # Resample to template resolution
  r_veg  <- terra::resample(r_veg,  r_tmpl, method = "bilinear")
  r_elev <- terra::resample(r_elev, r_tmpl, method = "bilinear")
  names(r_elev) <- "elevation"
  
  # Apply the same veg_cols filter used during training
  current_veg_cols <- veg_cols  # captured from parent environment
  veg_names <- make.names(names(r_veg))
  names(r_veg) <- veg_names
  
  missing_cols <- setdiff(current_veg_cols, veg_names)
  if (length(missing_cols) > 0) {
    cat("  WARNING: Future vegetation raster is missing layers present during training:\n")
    cat("  ", paste(missing_cols, collapse = ", "), "\n")
    cat("  These will be treated as 0 (absent).\n")
    for (mc in missing_cols) {
      r_zero <- r_tmpl; terra::values(r_zero) <- 0; names(r_zero) <- mc
      r_veg <- c(r_veg, r_zero)
    }
  }
  r_veg <- r_veg[[current_veg_cols]]  # enforce column order
  
  # Project to PCA space
  veg_vals <- terra::values(r_veg)
  na_rows_f <- apply(is.na(veg_vals), 1, any)
  
  fpc_vals  <- matrix(NA_real_, nrow = nrow(veg_vals), ncol = n_pc_gam)
  if (any(!na_rows_f)) {
    fpc_vals[!na_rows_f, ] <- predict(pca_obj, newdata = veg_vals[!na_rows_f, ])[, seq_len(n_pc_gam)]
  }
  
  r_fpcs <- terra::rast(
    lapply(seq_len(n_pc_gam), function(i) {
      r_tmp <- terra::rast(r_tmpl)
      terra::values(r_tmp) <- fpc_vals[, i]
      names(r_tmp) <- gam_pc_terms[i]
      r_tmp
    })
  )
  
  # Extrapolation risk for future data
  full_pcs  <- fpc_vals[!na_rows_f, , drop = FALSE]
  mahal_all <- rep(NA_real_, nrow(veg_vals))
  if (nrow(full_pcs) > 0) {
    pc_cov   <- cov(as.matrix(df_train[, gam_pc_terms]))
    pc_cent  <- colMeans(as.matrix(df_train[, gam_pc_terms]))
    mahal_all[!na_rows_f] <- mahalanobis(full_pcs, center = pc_cent, cov = pc_cov)
  }
  
  r_mahal <- r_tmpl
  terra::values(r_mahal) <- mahal_all
  names(r_mahal) <- "mahalanobis_distance"
  
  # Predict
  pred_stack <- c(r_elev, r_fpcs, r_x, r_y)
  
  predict_gam_fun <- function(model, data, ...) {
    mgcv::predict.bam(model, newdata = data, type = "response", ...)
  }
  
  r_pred <- terra::predict(pred_stack, gam_obj,
                           fun = predict_gam_fun, na.rm = TRUE)
  names(r_pred) <- "predicted_habitat_suitability"
  
  # Only keep the mainland iberia area's (spain/portugal)
  iberia <- rbind(gadm("ESP", level = 0, path = tempdir()),
                  gadm("PRT", level = 0, path = tempdir())) 
  iberia <- project(iberia, crs(template_raster))  
  
  r_pred  <- terra::mask(r_pred, iberia)
  r_mahal <- terra::mask(r_mahal, iberia)
  
  
  terra::writeRaster(r_pred,   output_path, overwrite = TRUE)
  terra::writeRaster(r_mahal,  sub("\\.tif", "_extrapolation_risk.tif", output_path), overwrite = TRUE)
  
  cat(sprintf("  Saved future prediction → %s\n", output_path))
  cat(sprintf("  Saved extrapolation risk → %s\n",
              sub("\\.tif", "_extrapolation_risk.tif", output_path)))
  
  return(list(predicted = r_pred,
              extrapolation_risk = r_mahal))
  # return(plot(r_pred))
}

