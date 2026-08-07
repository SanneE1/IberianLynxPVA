# ---------------------------------------------------------------------------
# River width raster pipeline
# Filters the GRWL (Global River Widths from Landsat) dataset to rivers wider
# than a threshold, and rasterizes the result onto a template grid.
# ---------------------------------------------------------------------------

library(sf)
library(terra)
source("scripts/r/transform_asc_to_input_maps.R")

template_path <- "data/GIS_maps/Peninsula_500_template.tif"

OUT_DIR <- "data/GIS_maps/"
TXT_DIR <- "data/model_input/maps"

#folder to store/cache the downloaded GRWL data
grwl_dir <- "data/original_data/grwl_data"

# Width threshold in meters — keep rivers wider than this
width_threshold_m <- 5

# Which width statistic to FILTER on (from the simplified
# GRWL product, since this script auto-downloads that one). Options:
#     "width_min", "width_max", "width_mean"
filter_stat <- "width_mean"

# Width statistic to use for the BUFFER/raster value.
raster_stat <- "width_mean"

# ---------------------------------------------------------------------------

# 1. Load the template raster (defines extent, resolution, CRS for output)
template <- rast(template_path)

# 2. Download the GRWL Simplified Vector Product (single global shapefile,
#    ~43 MB) if not already cached locally.
#    Source: Allen & Pavelsky (2018), https://zenodo.org/records/1297434
#    NOTE: this product summarizes width per river SEGMENT (width_min/med/
#    mean/max), not per point. For exact point-level clipping of "only the
#    sections wider than X", swap zip_url/zip_name below for the full Vector
#    Product (GRWL_vector_V01.01.zip, 3.1 GB, 829 tile shapefiles) — the
#    same download code works, but you'll need to pick out the tile(s)
#    covering your extent after unzipping, since it's split by region.
zip_url  <- "https://zenodo.org/records/1297434/files/GRWL_summaryStats_V01.01.zip?download=1"
zip_name <- "GRWL_summaryStats_V01.01.zip"

dir.create(grwl_dir, showWarnings = FALSE)
zip_path <- file.path(grwl_dir, zip_name)

if (!file.exists(zip_path)) {
  download.file(zip_url, zip_path, mode = "wb")
}

zip_contents <- unzip(zip_path, list = TRUE)$Name
shp_file <- zip_contents[grepl("\\.shp$", zip_contents)][1]

if (!file.exists(file.path(grwl_dir, shp_file))) {
  unzip(zip_path, exdir = grwl_dir)
}

grwl_path <- file.path(grwl_dir, shp_file)

# 3. Load GRWL and reproject to match the template
grwl <- st_read(grwl_path, quiet = TRUE)
grwl <- st_transform(grwl, crs(template))

# 4. Clip to the template extent
template_bbox <- st_as_sfc(st_bbox(ext(template), crs = crs(template)))
grwl <- st_filter(grwl, template_bbox)

# 5. Filter by width threshold using the chosen filter statistic
wide_rivers <- grwl[grwl[[filter_stat]] > width_threshold_m, ]

if (nrow(wide_rivers) == 0) {
  stop("No river segments exceed the width threshold in this extent — check units/threshold.")
}

# 6. Buffer the centerlines by half the chosen raster statistic, so the
#    raster shows a representative river footprint rather than a thin line.
min_buffer <- min(res(template)) / 2
wide_rivers_buf <- st_buffer(
  wide_rivers,
  dist = pmax(wide_rivers[[raster_stat]] / 2, min_buffer)
)

# 7. Rasterize onto the template grid
river_raster <- rasterize(
  vect(wide_rivers_buf),
  template,
  field = 0,
  background = 1,
  touches = T
)

# 8. (Optional) mask/crop to the exact template extent just to be safe
river_raster <- mask(river_raster, template)

# 9. Write output
writeRaster(river_raster, file.path(OUT_DIR, "Lynx_BreedingHabitat_rivers.asc"), overwrite = TRUE,
            NAflag = -9999, datatype = "INT2S")

transform_asc_file(input_path = file.path(OUT_DIR, "Lynx_BreedingHabitat_rivers.asc"),
                   output_path =  file.path(TXT_DIR, "Lynx_BreedingHabitat_rivers.txt"))

plot(river_raster, main = paste0("Rivers wider than ", width_threshold_m, " m"))
