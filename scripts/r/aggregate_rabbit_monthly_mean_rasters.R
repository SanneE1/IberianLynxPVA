library(terra)

# ----------------------------------------------------------------------------
# Aggregate monthly rabbit population maps across years into 12 monthly mean rasters
# for each simulation line folder.
#
# Input structure expected:
#   data/Rabbit_output/NC_simulation_Complete_historic/line12/maps/
#   data/Rabbit_output/NC_simulation_Complete_historic/line13/maps/
#   data/Rabbit_output/NC_simulation_Complete_historic/line14/maps/
#
# Output structure:
#   data/Rabbit_output/NC_simulation_Complete_historic/line12/monthly_mean_rasters/
#   .../line13/monthly_mean_rasters/
#   .../line14/monthly_mean_rasters/
# ----------------------------------------------------------------------------

read_rabbit_csv_as_raster <- function(file_path, template_rast) {
  mat <- as.matrix(read.csv(file_path, header = FALSE))
  r <- rast(template_rast)
  values(r) <- mat
  names(r) <- basename(file_path)
  r
}

parse_year_month <- function(file_path) {
  name <- basename(file_path)
  m <- regexec("^Rabbit_Population_distribution_(\\d+)_(\\d+)\\.csv$", name)
  parts <- regmatches(name, m)[[1]]
  if (length(parts) != 3) {
    stop("Unexpected filename format: ", name)
  }
  list(year = as.integer(parts[2]), month = as.integer(parts[3]))
}

base_dir <- "data/Rabbit_output/NC_simulation_Complete_historic"
line_dirs <- c("line12", "line13", "line14")
template_path <- "data/GIS_maps/Peninsula_500_template.tif"

template_rast <- rast(template_path)

for (line_dir in line_dirs) {
  maps_dir <- file.path(base_dir, line_dir, "maps")
  out_dir <- file.path(base_dir, line_dir, "monthly_mean_rasters")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  csv_files <- list.files(maps_dir, pattern = "^Rabbit_Population_distribution_.*\\.csv$",
                          full.names = TRUE)
  csv_files <- sort(csv_files)

  if (length(csv_files) == 0) {
    message("No CSV files found in ", maps_dir)
    next
  }

  month_groups <- split(csv_files, sapply(csv_files, function(x) parse_year_month(x)$month))

  for (month in 1:12) {
    month_files <- month_groups[[as.character(month)]]
    if (is.null(month_files) || length(month_files) == 0) {
      next
    }

    message("Processing ", line_dir, " month ", sprintf("%02d", month), " (", length(month_files), " files)")

    rasters <- lapply(month_files, read_rabbit_csv_as_raster, template_rast = template_rast)
    monthly_stack <- rast(rasters)
    monthly_mean <- app(monthly_stack, fun = mean, na.rm = TRUE)

    out_file <- file.path(out_dir, sprintf("%s_month_%02d_mean.tif", line_dir, month))
    writeRaster(monthly_mean, filename = out_file, overwrite = TRUE)
    message("Saved: ", out_file)
  }
}
