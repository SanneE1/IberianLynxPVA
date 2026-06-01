library(dplyr)
library(lubridate)
library(ggplot2)
library(terra)
library(sf)

# gps_file = "data/original_data/GPS_dispersal_data_Iberian_lynx_Cisneros-Araujo.csv"
# model_input_file = "data/model_input/calibration_dispersal_starting_locations.txt"
# result_dir = "results"
# hab_file = "data/GIS_maps/Lynx_HabitatMap_LUCAS_2015.asc"

df <- read.csv(gps_file, row.names = NULL) %>%
  tibble::column_to_rownames("X") %>%
  mutate(t = as.POSIXct(t, format = "%d/%m/%Y %H:%M"), 
         year = year(t),
         month = month(t),
         day = day(t),
         hour = as.integer(format(t, "%H")))


# ggplot(df %>% filter(id == "Bayon", year == 2013, month == 4), aes(x = x, y = y, colour = hour)) + geom_point() + geom_line() 

calculate_distance <- function(x1, y1, x2, y2) {
  return(sqrt((x2 - x1)^2 + (y2 - y1)^2))
}

df_movement_rates <- df %>%
  arrange(id, t) %>%  # Sort by individual and time
  group_by(id) %>%
  mutate(
    distance_moved = ifelse(row_number() == 1, 0, 
                            calculate_distance(lag(x), lag(y), x, y)),
    time_elapsed = ifelse(row_number() == 1, 0,
                          as.numeric(difftime(t, lag(t), units = "hours"))),
    movement_rate = ifelse(time_elapsed == 0, 0, distance_moved / time_elapsed)) %>%
  ungroup()

# ggplot() +
#   geom_smooth(data = df_movement_rates, aes(x = hour, y = movement_rate))

# Start day at 16:00 -------------------------------------------------------------------------------------------

df <- df %>%
  filter(hour == 16) %>%
  arrange(id, t) %>%  # Sort by individual and time
  group_by(id) %>%
  mutate(x_next = ifelse(row_number() == 1, NA, lead(x)),
         y_next = ifelse(row_number() == 1, NA, lead(y))) %>%
  ungroup() %>%
  filter(if_all(c(x, x_next, y, y_next), complete.cases))

habitat_rast <- rast(hab_file)

coor <- st_as_sf(df, coords = c('x','y'), crs = 32630) %>%
  st_transform(., crs = 3035) %>%
  st_coordinates(.)

coor_next <- st_as_sf(df, coords = c('x_next','y_next'), crs = 32630) %>%
  st_transform(., crs = 3035) %>%
  st_coordinates(.)

df$col0 <- colFromX(habitat_rast, x = coor[, "X"])
df$row0 <- rowFromY(habitat_rast, y = coor[, "Y"])

df$col1 <- colFromX(habitat_rast, x = coor_next[, "X"])
df$row1 <- rowFromY(habitat_rast, y = coor_next[, "Y"])

# There's a few instances (12 of the 2902) where the lynx is in a cell that's considered a barrier in my model,
# removing them to avoid  problems in the program
a <- extract(habitat_rast, as.matrix(coor[, c("X", "Y")]))
zero_coords <- coor[which(a == 0), ]

# plot(habitat_rast, main = "Habitat Raster with Zero-Value Points")
# points(zero_coords[,1], zero_coords[,2], 
#        col = "red", 
#        pch = 16, 
#        cex = 0.8)

df$habitat0 <- a$U2018_CLC2018_V2020_20u1
df$habitat1 <- extract(habitat_rast, as.matrix(coor_next[, c("X", "Y")]))$U2018_CLC2018_V2020_20u1

write.table(df[which(a != 0),c("col0", "row0")], file = model_input_file, row.names = F)
write.csv(df[which(a != 0),c("col0", "row0", "col1", "row1")], file = file.path(result_dir, "calibration_dispersal_observed.csv"), row.names = F)

write.csv(df, file = file.path(result_dir, "callibration_dispersal_full_table.csv"), row.names = F)
