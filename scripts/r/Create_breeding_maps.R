library(dplyr)
library(lubridate)
# library(reticulate)

# density_threshold = 5
# n_months = 12
# rabbit_folder = "data/Rabbit_output/"
# asc_dir = "data/GIS_maps/breeding_maps1"

source(file.path("scripts", "r", "Rasterize_output_maps.R"))
source(file.path("scripts", "r", "transform_asc_to_input_maps.R"))

#----------------------------------------
# Settings (defaults of Create_breeding_maps())
#----------------------------------------
# Only used if the object does not exist yet. Settings saved by
# scripts/Run_pipeline.R (path in the environment variable LYNX_PIPELINE_SETTINGS)
# are loaded first, so they also apply when the simulation step calls this script.

pipeline_settings <- Sys.getenv("LYNX_PIPELINE_SETTINGS")
if (nzchar(pipeline_settings) && file.exists(pipeline_settings)) {
  list2env(readRDS(pipeline_settings), envir = environment())
}

if (!exists("template_file"))  template_file  <- file.path("data", "GIS_maps", "Peninsula_500_template.tif")
if (!exists("model_maps_dir")) model_maps_dir <- file.path("data", "model_input", "maps")   # output when no output_dir is given
# A lynx year runs from June to May: months before this one belong to the same year
if (!exists("lynx_year_start_month")) lynx_year_start_month <- 6

Create_breeding_maps <- function(rabbit_folder,
                                 density_threshold,
                                 n_months,
                                 asc_dir = NULL,
                                 output_dir = NULL,
                                 hab_file = template_file,
                                 keep_asc = FALSE) {

  if (is.null(output_dir)) {
    if (missing(asc_dir) || nchar(asc_dir) == 0) {
      stop("Either asc_dir or output_dir must be provided")
    }
    output_dir <- file.path(model_maps_dir, basename(asc_dir))
  }

  if (dir.exists(output_dir)) {
    cat("Breeding maps already exist in the model input folder. Skipping creation.\n")
    return(normalizePath(output_dir, winslash = "/", mustWork = FALSE))
  }

  if (!dir.exists(asc_dir)) {
    dir.create(asc_dir, recursive = TRUE)
  }

  hab_rast <- rast(hab_file)

  Rdens_files <- list.files(rabbit_folder, full.names = TRUE, recursive = TRUE)
  dates <- stringr::str_extract(Rdens_files, pattern = "\\d{4}_\\d{1,2}")
  dates <- as.Date(paste0(dates, "_1"), format = "%Y_%m_%d")

  yrs_model <- ifelse(month(dates) < lynx_year_start_month, year(dates), year(dates) + 1)

  for (y in unique(yrs_model)) {
    if (length(which(yrs_model == y)) != 12) {
      next
    }

    dens <- lapply(as.list(Rdens_files[which(yrs_model == y)]), function(x) csvToRaster(x, hab_rast))
    dens <- rast(dens)

    threshold_reached <- app(dens, fun = function(x) sum(x >= density_threshold, na.rm = TRUE))
    breeding_habitat <- app(threshold_reached, fun = function(x) as.integer(x >= n_months))

    writeRaster(breeding_habitat,
                file.path(asc_dir, paste0("Lynx_PreyMap_", y, ".asc")),
                overwrite = TRUE,
                datatype = "INT1U")
  }

  process_folder(asc_dir, output_dir)

  if (!keep_asc) {
    unlink(asc_dir, recursive = TRUE)
  }

  return(normalizePath(output_dir, winslash = "/", mustWork = FALSE))
}


