library(dplyr)
library(lubridate)
# library(reticulate)

# density_threshold = 5
# n_months = 12
# rabbit_folder = "data/Rabbit_output/"
# asc_dir = "data/GIS_maps/breeding_maps1"

source(file.path("scripts", "r", "Rasterize_output_maps.R"))
source(file.path("scripts", "r", "transform_asc_to_input_maps.R"))

Create_breeding_maps <- function(rabbit_folder, density_threshold, n_months, asc_dir,
                                 hab_file = file.path("data", "GIS_maps", "Lynx_HabitatMap_LUCAS_2015.asc")) {
  
 if(!dir.exists(asc_dir)){
   dir.create(asc_dir, recursive = T)
 }

 hab_rast <- rast(hab_file)

 Rdens_files <- list.files(rabbit_folder, full.names = T, recursive = T)

 dates <- stringr::str_extract(Rdens_files, pattern = "\\d{4}_\\d{1,2}")
 dates <- as.Date(paste0(dates, "_1"), format = "%Y_%m_%d")

 yrs_model <- ifelse(month(dates) < 6, year(dates), year(dates) + 1)

 for (y in unique(yrs_model)) {

   if(length(which(yrs_model == y)) != 12) {next}

   dens <- lapply(as.list(Rdens_files[which(yrs_model == y)]), function(x) csvToRaster(x, hab_rast))
   dens <- rast(dens)

   threshold_reached <- app(dens, fun = function(x) sum (x >= density_threshold, na.rm = T))
   breeding_habitat <- app(threshold_reached, fun = function(x) as.integer(x >= n_months))

   writeRaster(breeding_habitat, file.path(asc_dir, paste0("Lynx_BreedingMap_", y, ".asc")), overwrite = TRUE, datatype = "INT1U")
  }

  process_folder(asc_dir, file.path("data", "model_input", "maps", basename(asc_dir)))
  
  return(file.path("data", "model_input", "maps", basename(asc_dir)))
}

if (identical(environment(), globalenv())) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 3) {
    message("Usage: Rscript scripts/r/Create_breeding_maps.R <rabbit_folder> <density_threshold> <n_months> [asc_dir]")
  } else {
    rabbit_folder <- args[1]
    density_threshold <- as.numeric(args[2])
    n_months <- as.integer(args[3])
    asc_dir <- if (length(args) >= 4) args[4] else paste0("data/GIS_maps/breeding_maps_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    Create_breeding_maps(rabbit_folder, density_threshold, n_months, asc_dir)
  }
}







