# ----------------------------------------------------------------------------
# Turn the GPS tracks (Cisneros-Araujo) into daily dispersal steps on the model
# grid: the position at 16:00 and the position at the next 16:00 fix.
# ----------------------------------------------------------------------------

prepare_gps_dispersal <- function(gps_file, habitat_file) {
  df <- read.csv(gps_file, row.names = NULL) %>%
    tibble::column_to_rownames("X") %>%
    mutate(t = as.POSIXct(t, format = "%d/%m/%Y %H:%M"),
           year = as.integer(format(t, "%Y")),
           month = as.integer(format(t, "%m")),
           day = as.integer(format(t, "%d")),
           hour = as.integer(format(t, "%H")))

  # One fix per day (16:00), paired with the next fix of the same individual
  df <- df %>%
    filter(hour == 16) %>%
    arrange(id, t) %>%
    group_by(id) %>%
    mutate(x_next = ifelse(row_number() == 1, NA, lead(x)),
           y_next = ifelse(row_number() == 1, NA, lead(y))) %>%
    ungroup() %>%
    filter(if_all(c(x, x_next, y, y_next), complete.cases))

  # GPS coordinates are UTM 30N (EPSG:32630); the model grid is LAEA Europe (EPSG:3035)
  start <- sf::st_as_sf(df, coords = c("x", "y"), crs = 32630) %>%
    sf::st_transform(crs = 3035) %>%
    sf::st_coordinates()
  end <- sf::st_as_sf(df, coords = c("x_next", "y_next"), crs = 32630) %>%
    sf::st_transform(crs = 3035) %>%
    sf::st_coordinates()

  habitat <- rast(habitat_file)

  df$col0 <- colFromX(habitat, start[, "X"])
  df$row0 <- rowFromY(habitat, start[, "Y"])
  df$col1 <- colFromX(habitat, end[, "X"])
  df$row1 <- rowFromY(habitat, end[, "Y"])

  df$habitat0 <- terra::extract(habitat, start[, c("X", "Y")])[, 1]
  df$habitat1 <- terra::extract(habitat, end[, c("X", "Y")])[, 1]

  df
}

# Write the model and ABC input files. Steps that start in a barrier cell
# (habitat 0) are removed, as the model cannot place an individual there.
write_dispersal_inputs <- function(df, starting_file, observed_file, full_table_file) {
  keep <- which(df$habitat0 != 0)

  write.table(df[keep, c("col0", "row0")], file = starting_file, row.names = FALSE)
  write.csv(df[keep, c("col0", "row0", "col1", "row1")], file = observed_file, row.names = FALSE)
  write.csv(df, file = full_table_file, row.names = FALSE)

  cat("  ", length(keep), "of", nrow(df), "steps kept (", nrow(df) - length(keep), "start in a barrier cell )\n")
  length(keep)
}
