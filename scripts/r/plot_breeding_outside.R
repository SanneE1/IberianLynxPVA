# --------------------------------------------------------------------
# Create a heatmap (event-count raster) from a CSV of events with X/Y
# pixel coordinates, using an existing raster as the spatial template.
#
# Requirements:
#   install.packages("terra")
#   install.packages("readr")   # optional, for faster CSV reading
# --------------------------------------------------------------------

library(terra)

breed_files <- list.files("results/simulation_runs/historic/", 
                           pattern = "lynx_reproduction_outside_populations.csv",
                           recursive = T, full.names = T)
sum_file <- c(list.files("results/simulation_runs/historic/summary/", 
                         recursive = T, full.names = T),
              list.files("results/simulation_runs/historic/summary_maps/", 
                         recursive = T, full.names = T))

csv_path <- setdiff(breed_files, sum_file)

template_raster_path  <- "data/GIS_maps/Peninsula_500_template.tif"      # raster that defines the grid
output_raster_path    <- "results/simulation_runs/breeding_outside_pop_2050_spp585.tif"       # output heatmap
output_plot_path      <- "results/simulation_runs/breeding_outside_pop_2050_spp585.png"
x_col                 <- "X"                 # column index (col number)
y_col                 <- "Y"                 # row index (row number)

# ------------------------------------------------------------------------

  # 1. Load events
  df <- lapply(csv_path, read.csv) %>% bind_rows()
  
  # 2. Load template raster (gives us dimensions, extent, CRS, resolution)
  template <- rast(template_raster_path)
  n_rows <- nrow(template)
  n_cols <- ncol(template)
  
  # 3. Build an empty count grid (same geometry as template)
  heatmap <- rast(template)
  values(heatmap) <- 0
  
  # 4. Pull out X/Y (assumed 0-indexed col/row, matching Python convention)
  x <- df[[x_col]]
  y <- df[[y_col]]
  
  # 5. Keep only events that fall inside the raster extent
  valid <- x >= 0 & x < n_cols & y >= 0 & y < n_rows
  n_dropped <- sum(!valid)
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
  
  # 8. Write output raster, matching template's spatial reference
  writeRaster(
    heatmap,
    output_raster_path,
    datatype = "INT4S",
    overwrite = TRUE,
    NAflag = 0
  )
  
  cat(sprintf("Heatmap written to %s\n", output_raster_path))
  cat(sprintf("Total events counted: %d (grid size: %d x %d)\n",
              sum(values(heatmap), na.rm = TRUE), n_cols, n_rows))


# --------------------------------------------------------------------
# Plot the event-count heatmap raster using tidyterra + ggplot2
#
# Requirements:
#   install.packages("terra")
#   install.packages("tidyterra")
#   install.packages("ggplot2")
# --------------------------------------------------------------------

library(terra)
library(tidyterra)
library(ggplot2)

# ---- CONFIG ------------------------------------------------------------
heatmap_path <- output_raster_path   # output from make_heatmap.R
output_plot  <- output_plot_path
# --------------------------------------------------------------------------

# 1. Load the heatmap raster
heatmap <- rast(heatmap_path)

# 2. Replace 0s with NA so empty cells are transparent instead of
#    dominating the color scale (optional, but usually looks better)
heatmap_plot_data <- heatmap
heatmap_plot_data <- aggregate(heatmap_plot_data, 
                               fact = 10, fun = "sum", na.rm = TRUE)
heatmap_plot_data[heatmap_plot_data == 0] <- NA


pops <- sf::st_transform(pops, crs(heatmap_plot_data))

# 3. Build the plot
p <- ggplot() +
  geom_sf(data = pops, fill = "grey95", color = "grey60") +
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

print(p)

# 4. Save to file
ggsave(output_plot, plot = p, width = 8, height = 6, dpi = 300)
cat(sprintf("Plot saved to %s\n", output_plot))