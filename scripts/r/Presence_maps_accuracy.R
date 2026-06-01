library(dplyr)
library(terra)

# obs_data <- readRDS("data/GIS_maps/presence_vector.rds")
# # sim_data <- Folder path here
# hab_rast <- rast("data/GIS_maps/Lynx_HabitatMap_LUCAS_2015.asc")

mean_MCC <- function(obs_dir, sim_data, hab_rast) {
  source(file.path("scripts", "r", "Rasterize_output_maps.R"))
  
  obs_files <- list.files(obs_dir,pattern = ".shp", full.names = T)
  obs_data <- lapply(obs_files, vect)
  names(obs_data) <- gsub(".shp", "", basename(obs_files))
  
  hab_raster <- rast(hab_rast)

  mcc <- c()
  mcc5 <- c()
  mcc10 <- c()
  
  
  for(n in names(obs_data)) {
    
    obs_pr <- project(obs_data[[n]], crs(hab_raster))
    obs_rast <- rasterize(obs_pr, hab_raster, field = 1, background = 0)  
    
    sim_file <- list.files(sim_data, pattern = n, full.names = T, recursive = T)
    if(length(sim_file) == 0) {next}
    
    sim_rast <- csvToRaster(sim_file[grep("FemalesMap_status", sim_file)], hab_raster, return_df = T, plot = F)
    sim_rast <- ifel(sim_rast == -1, 0, 1)
    
    # 500m resolution ---------------------------------------------------------------------------------------------------
    pred <- values(sim_rast, na.rm = FALSE)
    obs  <- values(obs_rast, na.rm = FALSE)
    
    valid <- !is.na(pred) & !is.na(obs)
    pred  <- pred[valid]
    obs   <- obs[valid]
    
    obsP <- sum(obs == 1) # Observed Positives
    obsN <- sum(obs == 0) # Observed Negatives
    
    TP <- sum(pred == 1 & obs == 1) # True Positive
    FP <- sum(pred == 1 & obs == 0) # False Positive
    FN <- sum(pred == 0 & obs == 1) # False Negative
    TN <- sum(pred == 0 & obs == 0) # True Negative
    
    TPR <- TP / obsP # True Positive Rate
    TNR <- TN / obsN # True Negative Rate
    FPR <- FP / obsP # False positive Rate
    FNR <- FN / obsN # False Negative Rate
    
    PPV <- ifelse((TP + FP) == 0, 0, TP / (TP + FP)) # Postive Predictive Value
    NPV <- ifelse((TN + FN) == 0, 0, TN / (TN + FN)) # Negative Predictive Value
    
    FOR <- 1 - NPV # False Omision Rate
    FDR <- 1 - PPV # False Detection Rate
    
    # INF <- TPR + TNR - 1 # Informedness  
    # MK <- PPV + NPV - 1 # Markedness
    phi <- sqrt(TPR * TNR * PPV * NPV) - sqrt(FNR * FPR * FOR * FDR) # Mathews Correlation Coefficient
    
    mcc <- c(mcc, phi)
    
    # 5km resolution ---------------------------------------------------------------------------------------------------
    sim_5 <- terra::aggregate(sim_rast, fact = 10, fun = max)
    obs_5 <- obs_rast <- rasterize(obs_pr, sim_5, field = 1, background = 0)
    
    pred <- values(sim_5, na.rm = FALSE)
    obs  <- values(obs_5, na.rm = FALSE)
    
    valid <- !is.na(pred) & !is.na(obs)
    pred  <- pred[valid]
    obs   <- obs[valid]
    
    obsP <- sum(obs == 1) # Observed Positives
    obsN <- sum(obs == 0) # Observed Negatives
    
    TP <- sum(pred == 1 & obs == 1) # True Positive
    FP <- sum(pred == 1 & obs == 0) # False Positive
    FN <- sum(pred == 0 & obs == 1) # False Negative
    TN <- sum(pred == 0 & obs == 0) # True Negative
    
    TPR <- TP / obsP # True Positive Rate
    TNR <- TN / obsN # True Negative Rate
    FPR <- FP / obsP # False positive Rate
    FNR <- FN / obsN # False Negative Rate
    
    PPV <- ifelse((TP + FP) == 0, 0, TP / (TP + FP)) # Postive Predictive Value
    NPV <- ifelse((TN + FN) == 0, 0, TN / (TN + FN)) # Negative Predictive Value
    
    FOR <- 1 - NPV # False Omision Rate
    FDR <- 1 - PPV # False Detection Rate
    
    # INF <- TPR + TNR - 1 # Informedness  
    # MK <- PPV + NPV - 1 # Markedness
    phi <- sqrt(TPR * TNR * PPV * NPV) - sqrt(FNR * FPR * FOR * FDR) # Mathews Correlation Coefficient
    
    mcc5 <- c(mcc5, phi)
    
    # 10km resolution ---------------------------------------------------------------------------------------------------
    sim_10 <- terra::aggregate(sim_rast, fact = 20, fun = max)
    obs_10 <- obs_rast <- rasterize(obs_pr, sim_10, field = 1, background = 0)
    
    pred <- values(sim_10, na.rm = FALSE)
    obs  <- values(obs_10, na.rm = FALSE)
    
    valid <- !is.na(pred) & !is.na(obs)
    pred  <- pred[valid]
    obs   <- obs[valid]
    
    obsP <- sum(obs == 1) # Observed Positives
    obsN <- sum(obs == 0) # Observed Negatives
    
    TP <- sum(pred == 1 & obs == 1) # True Positive
    FP <- sum(pred == 1 & obs == 0) # False Positive
    FN <- sum(pred == 0 & obs == 1) # False Negative
    TN <- sum(pred == 0 & obs == 0) # True Negative
    
    TPR <- TP / obsP # True Positive Rate
    TNR <- TN / obsN # True Negative Rate
    FPR <- FP / obsP # False positive Rate
    FNR <- FN / obsN # False Negative Rate
    
    PPV <- ifelse((TP + FP) == 0, 0, TP / (TP + FP)) # Postive Predictive Value
    NPV <- ifelse((TN + FN) == 0, 0, TN / (TN + FN)) # Negative Predictive Value
    
    FOR <- 1 - NPV # False Omision Rate
    FDR <- 1 - PPV # False Detection Rate
    
    # INF <- TPR + TNR - 1 # Informedness  
    # MK <- PPV + NPV - 1 # Markedness
    phi <- sqrt(TPR * TNR * PPV * NPV) - sqrt(FNR * FPR * FOR * FDR) # Mathews Correlation Coefficient
    
    mcc10 <- c(mcc10, phi)
  }
  
  return(data.frame(mcc_500m = mean(mcc, na.rm = T),
                    mcc_5km = mean(mcc5, na.rm = T),
                    mcc_10km = mean(mcc10, na.rm = T))
         )
} 





