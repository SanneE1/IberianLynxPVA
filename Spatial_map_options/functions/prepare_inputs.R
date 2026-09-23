# ----------------------------------------------------------------------------
# Functions to load and align the input rasters to the 500 m template grid
# ----------------------------------------------------------------------------

# Project, crop and resample a raster onto the template grid
align_to_template <- function(r, template, method = "bilinear") {
  if (!same.crs(r, template)) r <- project(r, crs(template), method = method)
  r <- crop(r, template)
  resample(r, template, method = method)
}

# Elevation (Copernicus DEM)
load_elevation <- function(elevation_path, template) {
  elev <- align_to_template(rast(elevation_path), template)
  names(elev) <- "elevation"
  elev
}

# LUCAS land cover fractions for 2015 (last historical year)
load_lucas_2015 <- function(vegetation_path, categories, template) {
  veg <- rast(vegetation_path)
  veg <- subset(veg, time(veg) == as.Date("2015-01-01"))
  names(veg) <- categories
  veg <- align_to_template(veg, template)
  names(veg) <- categories
  veg
}

# Road density: share of road cells in a 3x3 window, based on OpenStreetMap.
# Downloads the OSM roads for Spain and Portugal the first time and caches the
# result in road_path.
get_road_density <- function(road_path, cache_dir, template) {
  if (!file.exists(road_path)) {
    dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)

    road_classes <- c("motorway", "motorway_link", "trunk", "trunk_link",
                      "primary", "primary_link", "secondary", "secondary_link",
                      "tertiary", "tertiary_link", "unclassified")
    sql_query <- paste0("SELECT highway, geometry FROM 'lines' WHERE highway IN (",
                        paste0("'", road_classes, "'", collapse = ", "), ")")

    roads <- dplyr::bind_rows(
      osmextract::oe_get(place = "Spain", layer = "lines", query = sql_query,
                         download_directory = cache_dir),
      osmextract::oe_get(place = "Portugal", layer = "lines", query = sql_query,
                         download_directory = cache_dir))
    roads <- sf::st_transform(roads, crs(template))

    aoi <- sf::st_buffer(sf::st_as_sf(as.polygons(ext(template), crs = crs(template))), 1000)
    roads <- vect(sf::st_intersection(roads, aoi))

    road_presence <- rasterize(roads, template, field = 1, background = 0, touches = TRUE)
    road_presence <- mask(road_presence, template)

    road_density <- focal(road_presence, w = matrix(1, 3, 3), fun = "sum", na.rm = TRUE) / 9
    road_density <- mask(road_density, template)
    writeRaster(road_density, road_path, overwrite = TRUE)
  }

  road <- align_to_template(rast(road_path), template)
  names(road) <- "road_density_presence_3x3"
  road
}

# Observed lynx presence (all presence polygons combined): 1 = present, 0 = absent
get_presence_raster <- function(presence_dir, template) {
  files <- list.files(presence_dir, pattern = "\\.shp$", recursive = TRUE, full.names = TRUE)
  presence <- lapply(files, function(f) {
    rasterize(project(vect(f), crs(template)), template, field = 1, background = 0)
  })
  presence <- max(rast(presence))
  names(presence) <- "presence"
  presence
}
