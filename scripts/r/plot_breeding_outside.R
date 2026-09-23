# --------------------------------------------------------------------
# Create a heatmap (event-count raster) from a CSV of events with X/Y
# pixel coordinates, using an existing raster as the spatial template.
#
# Requirements:
#   install.packages("terra")
#   install.packages("readr")   # optional, for faster CSV reading
# --------------------------------------------------------------------

library(terra)


# ------------------------------------------------------------------------
plot_outside_breeding <- function(summary_file,
                                  save_rast = F, rast_path = NULL,
                                  save_plot = F, save_path = NULL){

  # 1. Load events
  df <- read.csv(summary_file)
  
  # 2. Load template raster (gives us dimensions, extent, CRS, resolution)
  template <- rast(here::here("data/GIS_maps/Peninsula_500_template.tif"))
  n_rows <- nrow(template)
  n_cols <- ncol(template)
  
  # 3. Build an empty count grid (same geometry as template)
  heatmap <- rast(template)
  values(heatmap) <- 0
  
  # 4. Pull out X/Y (assumed 0-indexed col/row, matching Python convention)
  x <- df[["X"]]
  y <- df[["Y"]]
  
  # 5. Keep only events that fall inside the raster extent
  valid <- x >= 0 & x < n_cols & y >= 0 & y < n_rows
  n_dropped <- sum(!valid, na.rm = T)
  
  if (n_dropped > 0) {
    warning(sprintf("%d event(s) fall outside the raster extent and were dropped.", n_dropped))
  }
  
  x <- x[valid]
  y <- y[valid]
  
  # 6. Convert 0-indexed (col, row) -> terra's 1-indexed cell numbers
  #    terra::cellFromRowCol expects row, col starting at 1
  cell_ids <- cellFromRowCol(heatmap, row = y + 1, col = x + 1)
  
  # 7. Count events per cell (table() handles duplicate coords correctly)
  counts <- table(cell_ids)
  cell_idx <- as.integer(names(counts))
  heatmap[cell_idx] <- as.integer(counts)
  
  if (save_rast){
  # 8. Write output raster, matching template's spatial reference
  writeRaster(
    heatmap,
    rast_path,
    datatype = "INT4S",
    overwrite = TRUE,
    NAflag = 0
  )
  
  }
  
  
  # 2. Replace 0s with NA so empty cells are transparent instead of
  #    dominating the color scale (optional, but usually looks better)
  heatmap_plot_data <- heatmap
  heatmap_plot_data <- aggregate(heatmap_plot_data,
                                 fact = 10, fun = "sum", na.rm = TRUE)
  heatmap_plot_data[heatmap_plot_data == 0] <- NA
  
  pops_raster <- rast(here("data/GIS_maps/Lynx_populations_2022_buffered.asc"))
  pops <- pops_raster %>%
    as.polygons(dissolve = TRUE) %>%
    st_as_sf()
  
  
  pops <- sf::st_transform(pops, crs(heatmap_plot_data))
  
  # 3. Build the plot
  p <- ggplot() +
    geom_sf(data = world_cropped, fill = "grey")+
    geom_sf(data = pops, fill = "black", color = "black") +
    geom_spatraster(data = heatmap_plot_data) +
    scale_fill_viridis_c(
      name = "Event count",
      na.value = "transparent"
    ) +
    labs(
      title = "Event Heatmap",
      subtitle = "Number of events per grid cell"
    ) +
    theme_minimal() +
    theme(
      axis.title = element_blank()
    )
  

  if(save_plot){
  # 4. Save to file
  ggsave(save_path, plot = p, width = 8, height = 6, dpi = 300)
  cat(sprintf("Plot saved to %s\n", output_plot))
  }
  
  return(p)
  
}
