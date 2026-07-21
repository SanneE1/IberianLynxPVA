## ============================================================
## Emigration flow map: arrows between population polygons
## ============================================================
## Requires: terra, sf, dplyr, ggplot2, tidyr
## install.packages(c("terra", "sf", "dplyr", "ggplot2", "tidyr"))

library(terra)
library(sf)
library(dplyr)
library(ggplot2)
library(tidyr)

## ------------------------------------------------------------
## 1. Load your data
## ------------------------------------------------------------

# Your population grid is an ESRI ASCII raster (.asc), where each
# cell's value is the population/zone ID (0 = outside any zone).
# st_read() is for vector data, so it can't open this — use terra
# instead, then dissolve cells into polygons per zone ID.
pops_raster <- rast("data/GIS_maps/Lynx_populations_2022_buffered.asc")

# Convert to polygons, one (multi)polygon per unique population ID,
# then to sf so it plays nicely with ggplot2::geom_sf() and st_centroid()
pops <- pops_raster %>%
  as.polygons(dissolve = TRUE) %>%
  st_as_sf()

# The value/ID column from the raster is usually named after the
# raster layer itself (check with names(pops) if this errors)
POP_FIELD <- names(pops)[1]

# Your emigration events table
event_files <- list.files("results/simulation_runs/ssp585",
                          pattern = "lynx_migration_settled.csv", recursive = T, full.names = T)
events <- lapply(event_files, read.csv) %>% bind_rows()
colnames(events) <- colnames(events)[-2]
events[,8] <- NULL

## ------------------------------------------------------------
## 2. Get centroid coordinates for each numbered population
## ------------------------------------------------------------

centroids <- pops %>%
  st_centroid() %>%
  st_coordinates() %>%
  as_tibble() %>%
  mutate(Population = pops[[POP_FIELD]])

## ------------------------------------------------------------
## 3. Add a manual point for Population 0 ("outside" the study area)
## ------------------------------------------------------------
## Population 0 was NA in the raster, so it has no polygon and no
## centroid from step 2 — add a point for it yourself, e.g. just
## outside the bounding box of your study area. Adjust as you like.

bbox <- st_bbox(pops)
centroids <- centroids %>%
  bind_rows(tibble(
    Population = "0",
    X = bbox["xmin"] - 0.1 * (bbox["xmax"] - bbox["xmin"]),  # left of map
    Y = mean(c(bbox["ymin"], bbox["ymax"]))                   # vertical middle
  ))

## ------------------------------------------------------------
## 3b. Population ID -> name lookup key
## ------------------------------------------------------------

pop_key <- tribble(
  ~number, ~Population,
  22, "Vale do Guadiana",
  2, "Campo de Montiel",
  6, "Guadalmez",
  1, "ANDUJAR_CARDENA_MONT",
  13, "Montes de Toledo",
  4, "DONANA",
  10, "LAS MINAS",
  17, "RIO SOTILLO",
  18, "SETEFILLA",
  5, "GUADALMELLATO",
  7, "GUARRIZAS",
  8, "GUAZUJEROS",
  16, "PEGALAJAR_CONEX",
  19, "SIERRA ARANA",
  15, "PEGALAJAR",
  3, "Cornalvo",
  11, "Matachel",
  21, "Valdecigüeñas",
  12, "Monfrague",
  14, "Ortigas",
  20, "Valdecañas",
  9, "Ibores"
) %>%
  bind_rows(tibble(number = 0, Population = "Outside"))  # add a label for pop 0

# Attach names to centroids for labeling on the map
centroids <- centroids %>%
  left_join(pop_key, by = "Population")

## ------------------------------------------------------------
## 4. Aggregate flows (counts of moves between each pop pair)
## ------------------------------------------------------------
## Using Natal_pop -> New_pop here (change to Old_pop if you want
## "realized" moves rather than birthplace-based moves)

flows <- events %>%
  count(Natal_pop, New_pop, name = "n_events") %>%
  filter(Natal_pop != New_pop)     # drop non-movements (optional)

## ------------------------------------------------------------
## 5. Join centroid coordinates onto the flow table
## ------------------------------------------------------------

flows <- flows %>%
  left_join(centroids, by = c("Natal_pop" = "number")) %>%
  rename(x_start = X, y_start = Y, label_start = Population) %>%
  left_join(centroids, by = c("New_pop" = "number")) %>%
  rename(x_end = X, y_end = Y, label_end = Population)

## ------------------------------------------------------------
## 6. Plot: base map + curved arrows scaled by event count
## ------------------------------------------------------------

ggplot() +
  geom_sf(data = pops, fill = "grey95", color = "grey60") +
  geom_curve(
    data = flows %>% filter(Natal_pop != 0 & New_pop != 0),
    aes(x = x_start, y = y_start, xend = x_end, yend = y_end,
        linewidth = n_events, color = n_events),
    curvature = 0.2,
    arrow = arrow(length = unit(0.2, "cm"), type = "closed"),
    alpha = 0.8
  ) +
  # geom_text(
  #   data = centroids %>% filter(number != 0),
  #   aes(x = X, y = Y, label = Population),
  #   size = 4, color = "black", check_overlap = TRUE, nudge_y = 0.02
  # ) +
  scale_linewidth(range = c(0.3, 3), name = "# events") +
  scale_color_viridis_c(name = "# events", transform = "log") +
  theme_minimal() +
  labs(
    title = "Emigration between populations",
    subtitle = "Natal to settled"
  ) + theme(text = element_text(size = 14), axis.title = element_blank())

ggsave("results/simulation_runs/Between_Population_Emigration_2050_ssp585.png")
## ------------------------------------------------------------
## Optional: facet by Sex or Year to compare subgroups
## ------------------------------------------------------------
# flows_by_sex <- events %>%
#   count(Sex, Natal_pop, New_pop, name = "n_events") %>%
#   filter(Natal_pop != New_pop) %>%
#   left_join(centroids, by = c("Natal_pop" = "Population")) %>%
#   rename(x_start = X, y_start = Y) %>%
#   left_join(centroids, by = c("New_pop" = "Population")) %>%
#   rename(x_end = X, y_end = Y)
#
# ggplot() +
#   geom_sf(data = pops, fill = "grey95", color = "grey60") +
#   geom_curve(data = flows_by_sex,
#              aes(x = x_start, y = y_start, xend = x_end, yend = y_end,
#                  linewidth = n_events, color = n_events),
#              curvature = 0.2,
#              arrow = arrow(length = unit(0.15, "cm"), type = "closed")) +
#   facet_wrap(~Sex) +
#   scale_linewidth(range = c(0.3, 3)) +
#   scale_color_viridis_c() +
#   theme_minimal()

