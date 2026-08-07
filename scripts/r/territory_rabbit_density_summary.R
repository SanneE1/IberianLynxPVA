library(terra)

# ----------------------------------------------------------------------------
# Summarise rabbit density by territory polygon using the shapefiles in
# data/original_data/20250825_data_German/Presencias and the monthly rabbit
# population CSVs in data/Rabbit_output/NC_simulation_Complete_historic/
#
# Only *_projected.shp Presencias files are used, and no CRS reprojection is
# performed because the shapefiles already match the raster CRS.
#
# Output:
#   A data frame with one row per territory polygon and columns:
#     - source_shapefile
#     - year
#     - line_dir
#     - territory_id
#     - area_km2
#     - mean_density_year
#     - min_density_year
# ----------------------------------------------------------------------------

read_rabbit_csv_as_raster <- function(file_path, template_rast, template_crs) {
  mat <- as.matrix(read.csv(file_path, header = FALSE, stringsAsFactors = FALSE))
  mat <- apply(mat, 2, as.numeric)

  if (nrow(mat) != nrow(template_rast) || ncol(mat) != ncol(template_rast)) {
    stop(sprintf(
      "Matrix dimensions %d x %d do not match template raster %d x %d for %s",
      nrow(mat), ncol(mat), nrow(template_rast), ncol(template_rast), file_path
    ))
  }

  r <- rast(template_rast)
  crs(r) <- template_crs
  values(r) <- mat
  names(r) <- basename(file_path)
  r
}

extract_year_month_files <- function(base_dir, line_dir, year) {
  pattern <- sprintf("^Rabbit_Population_distribution_%d_.*\\.csv$", year)
  files <- list.files(file.path(base_dir, line_dir, "maps"),
                      pattern = pattern,
                      full.names = TRUE)
  sort(files)
}

extract_polygon_mean <- function(r, territories_vect, n_polygons) {
  ex <- tryCatch(
    terra::extract(r, territories_vect, fun = mean, na.rm = TRUE, exact = FALSE),
    error = function(e) NULL
  )

  if (is.null(ex) || nrow(ex) == 0) {
    return(rep(NA_real_, n_polygons))
  }

  if (ncol(ex) >= 2) {
    vals <- ex[[ncol(ex)]]
  } else {
    vals <- ex[[1]]
  }

  vals <- suppressWarnings(as.numeric(vals))
  if (length(vals) != n_polygons) {
    vals <- rep(NA_real_, n_polygons)
  }
  vals
}

build_territory_summary <- function(territories, rasters) {
  
  monthly_means <- lapply(rasters, extract_polygon_mean,
                          territories_vect = territories,
                          n_polygons = nrow(territories))
  monthly_means_mat <- do.call(cbind, monthly_means)

  mean_density_year <- apply(monthly_means_mat, 1, function(x) {
    x <- as.numeric(x)
    x <- x[!is.na(x)]
    if (length(x) == 0) {
      return(NA_real_)
    }
    mean(x)
  })

  min_density_year <- apply(monthly_means_mat, 1, function(x) {
    x <- as.numeric(x)
    x <- x[!is.na(x)]
    if (length(x) == 0) {
      return(NA_real_)
    }
    min(x)
  })

  summary_df <- data.frame(
    territory_id = seq_len(nrow(territories)),
    area_km2 = as.numeric(expanse(territories)) / 1e6,
    mean_density_year = mean_density_year,
    min_density_year = min_density_year
  )

  if ("territory_label" %in% names(territories)) {
    summary_df$territory_label <- territories$territory_label
  }

  summary_df
}

# Paths
rabbit_base_dir <- "data/Rabbit_output/NC_simulation_Complete_historic"
territory_root <- "data/GIS_maps/presence_vectors/"
template_path <- "data/GIS_maps/Peninsula_500_template.tif"
out_csv <- "results/population_rabbit_density_summary.csv"

line_dirs <- c("line12", "line13", "line14")

if (!dir.exists("results")) {
  dir.create("results", recursive = TRUE, showWarnings = FALSE)
}

template_rast <- rast(template_path)
template_crs <- terra::crs(template_rast)

# Use an equal-area CRS for area calculations and the raster CRS for extraction.
area_crs <- template_crs

shp_files <- list.files(territory_root, pattern = ".shp$", recursive = TRUE, full.names = TRUE)
shp_files <- sort(shp_files)

all_results <- list()

for (shp_path in shp_files) {
  territories <- vect(shp_path)
  
  # Preserve a readable territory identifier if one exists.
  id_candidates <- c("subpop_num")
  id_col <- intersect(id_candidates, names(territories))
  if (length(id_col) > 0) {
    territories$territory_label <- as.character(territories[[id_col[1]]])
  } else {
    territories$territory_label <- paste0("polygon_", seq_len(nrow(territories)))
  }

  # Restrict to territories that intersect the raster footprint.
  template_bbox <- as.polygons(ext(template_rast))
  crs(template_bbox) <- template_crs
  overlap_mask <- relate(territories, template_bbox, relation = "intersects")
  overlap_mask <- as.logical(overlap_mask)

  territories <- territories[overlap_mask]

  if (nrow(territories) == 0) {
    message("No overlapping territories for ", basename(shp_path))
    next
  }

  territories_extract <- territories

  year_match <- regmatches(basename(shp_path), regexec("([0-9]{4})", basename(shp_path)))[[1]]
  if (length(year_match) == 0) {
    message("Skipping shapefile with no year in name: ", shp_path)
    next
  }
  shp_year <- as.integer(year_match[length(year_match)])
  if (is.na(shp_year) || shp_year < 1900 || shp_year > 2100) {
    message("Invalid year extracted from shapefile name: ", basename(shp_path))
    next
  }

  for (line_dir in line_dirs) {
    month_files <- extract_year_month_files(rabbit_base_dir, line_dir, shp_year)
    if (length(month_files) == 0) {
      message("No rabbit maps found for ", line_dir, " year ", shp_year)
      next
    }

    rasters <- lapply(month_files, read_rabbit_csv_as_raster,
                      template_rast = template_rast,
                      template_crs = template_crs)
    territory_summary <- build_territory_summary(territories_extract, rasters)

    territory_summary$source_shapefile <- basename(shp_path)
    territory_summary$year <- shp_year
    territory_summary$line_dir <- line_dir
    territory_summary$territory_label <- territories$territory_label

    all_results[[length(all_results) + 1]] <- territory_summary
  }
}

if (length(all_results) == 0) {
  stop("No territory summaries were produced.")
}

out_df <- do.call(rbind, all_results)
rownames(out_df) <- NULL

write.csv(out_df, out_csv, row.names = FALSE)
message("Saved territory summary table to ", out_csv)
