library(dplyr)
library(ggplot2)
library(tidyterra)
library(sf)
library(rnaturalearth)

source(file.path("scripts", "r", "Rasterize_output_maps.R"))

hab_rast = rast(file.path("data", "GIS_maps", "Peninsula_500_template.tif"))
world <- ne_countries(scale = "medium", returnclass = "sf")
world_cropped <- world %>%
  st_transform(crs(hab_rast)) %>%
  st_crop(ext(hab_rast))

# Breeding habitat ---------------------------------------------------------------------------------------------------

# bh22mean <- csvToRaster("results/rabbit_simulation_summary_maps/Lynx_BreedingMap_2022_mean.csv", hab_rast)
# bh22lower <- csvToRaster("results/rabbit_simulation_summary_maps/Lynx_BreedingMap_2022_lower_ci.csv", hab_rast)
# bh22upper <- csvToRaster("results/rabbit_simulation_summary_maps/Lynx_BreedingMap_2022_upper_ci.csv", hab_rast)

# Historic simulations -----------------------------------------------------------------------------------------------

occ_map_2022 <- csvToRaster("results/simulations/simulation_runs/historic/summary_maps/FemalesMap_status_yr_2022_occupancy_prob.csv", 
                            hab_rast)
occ_map_2022 <- ifel(occ_map_2022 < 0.01, NA, occ_map_2022)

# Spatial distribution
obs_22 <- vect("data/GIS_maps/presence_vectors/2022.shp")
obs_22 <- project(obs_22, crs(hab_rast))
ext_22 <- ext(obs_22)

ggplot() +
  geom_sf(data = world_cropped, fill = "grey90", color = "white", linewidth = 0.3) +
  geom_spatraster(data = occ_map_2022) +
  geom_spatvector(data = aggregate(obs_22), fill = "transparent", color = "red") +
  scale_fill_viridis_c(na.value = NA)+
  theme_light() +
  coord_sf(xlim = c(ext_22[1], ext_22[2]), 
                  ylim = c(ext_22[3], ext_22[4]))
  


# Population sizes
size_obs <- read.csv("data/original_data/Population_sizes_IUCN.csv")
size_obs$obs_size <- size_obs$Vale.do.Guadiana + size_obs$Doñana + size_obs$Matachel + size_obs$Sierra.Morena + size_obs$Toledo.Mountains

size_sim <- read.csv("results/simulations/simulation_runs/historic/summary/all_lynx_biopop_size.csv")
size_sim$tot_size <- rowSums(size_sim[,c(2:7)])
size_sim <- size_sim %>% filter(year < 2025)

ggplot() +
  geom_line(data = size_sim, aes(x = year, y = tot_size, group = source_run, colour = "darkblue")) +
  geom_line(data = size_obs, aes(x = Year, y = obs_size), colour = "grey40", linewidth = 2) 





# Plot Rabbit density averages

R25 <- csvToRaster("results/rabbit_simulation_summary_maps/Rabbit_Population_distribution_2025_5_presence_prob.csv",
                   habitat_raster = hab_rast)
R21 <- csvToRaster("results/rabbit_simulation_summary_maps/Rabbit_Population_distribution_2100_5_presence_prob.csv",
                   habitat_raster = hab_rast)

hist_plot <- (ggplot() +
                geom_sf(data = world_cropped, fill = "grey90", color = "grey30", linewidth = 0.3) +
                geom_spatraster(data = mean_hist) +
                scale_fill_gradientn(colours = c("transparent", "lightgreen", "darkgreen"),
                                     values = c(0, 1/25, 1),
                                     limits = c(0, 25),
                                     na.value = NA) +
                theme_minimal() +
                labs(title = "Average population size") +
                theme(legend.position = "right")) + 
  (ggplot() +
     geom_sf(data = world_cropped, fill = "grey90", color = "grey30", linewidth = 0.3) +
     geom_spatraster(data = std_hist) +
     scale_fill_gradientn(colours = c("transparent", "lightgreen", "darkgreen"),
                          values = c(0, 1/25, 1),
                          limits = c(0, 25),
                          na.value = NA) +
     theme_minimal() +
     labs(title = "Standard deviation") +
     theme(legend.position = "right")) +
  plot_layout(guides = "collect")




### compare breeding habitats  -- Run on an R session on DRAGO
library(dplyr)
library(ggplot2)
library(tidyterra)
library(sf)
library(rnaturalearth)

source(file.path("scripts", "r", "Rasterize_output_maps.R"))

hab_rast = rast(file.path("data", "GIS_maps", "Lynx_HabitatMap_LUCAS_2015.asc"))
world <- ne_countries(scale = "medium", returnclass = "sf")
world_cropped <- world %>%
  st_transform(crs(hab_rast)) %>%
  st_crop(ext(hab_rast))


bh_2022 <- lapply(list.files("data/model_input/maps", pattern = "Lynx_BreedingMap_2022", full.names = T, recursive = T), 
                  function(x) {  
                    a <- read.table(x, skip = 1, header = F)
                    b <- hab_rast
                    values(b) <- a
                    return(b)
                  })

r22 <- app(rast(bh_2022), mean)

p22 <- ggplot() +
  geom_sf(data = world_cropped, fill = "grey90", color = "grey30", linewidth = 0.3) +
  geom_spatraster(data = r22) +
  scale_fill_gradientn(colours = c("transparent", "lightgreen", "darkgreen"),
                       values = c(0, 0.0001, 1),
                       limits = c(0, 1),
                       na.value = NA)

ggsave(filename = "breeding_habitat_2022_summary.png", plot = p22)  


bh_2100 <- lapply(list.files("data/model_input/maps", pattern = "Lynx_BreedingMap_2100", full.names = T, recursive = T), 
                  function(x) {  
                    a <- read.table(x, skip = 1, header = F)
                    b <- hab_rast
                    values(b) <- a
                    return(b)
                  })

r21 <- app(rast(bh_2100), mean)

p21 <- ggplot() +
  geom_sf(data = world_cropped, fill = "grey90", color = "grey30", linewidth = 0.3) +
  geom_spatraster(data = r21) +
  scale_fill_gradientn(colours = c("transparent", "lightgreen", "darkgreen"),
                       values = c(0, 0.0001, 1),
                       limits = c(0, 1),
                       na.value = NA)

ggsave(filename = "breeding_habitat_2100_summary.png", plot = p21)  

