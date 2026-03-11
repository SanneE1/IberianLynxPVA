library(dplyr)
library(ggplot2)
library(tidyterra)
library(sf)
library(rnaturalearth)

source("R/Rasterize_output_maps.R")

sim_size_format <- function(folder) { 
  lapply(list.files(file.path("results", "simulations", folder, "all_lynx_biopop/"), full.names = T), 
         function(x) {
           s <- stringr::str_split(x, pattern = "/")
           s <- stringr::str_split(s[[1]][5], pattern = "_")
           
           a <- read.csv(x)
           a$sim_size <- rowSums(a[,-1])
           a$Rsim <- as.integer(s[[1]][2])
           a$Tsize <- as.integer(s[[1]][3])
           a$threshold <- as.integer(s[[1]][4])
           a$months <- as.integer(s[[1]][5])
           a$rep  <- as.integer(s[[1]][6])
           return(a)
         }) %>%
    bind_rows() %>%
    filter(year != 2023)
}

hab_rast = rast(file.path("data", "GIS_maps", "Lynx_HabitatMap_LUCAS_2015.asc"))
world <- ne_countries(scale = "medium", returnclass = "sf")
world_cropped <- world %>%
  st_transform(crs(hab_rast)) %>%
  st_crop(ext(hab_rast))

# Historic simulations -----------------------------------------------------------------------------------------------

folders <- c("Historical_simulations", "Historical_simulations_rate", 
             "Historical_simulations_CORINE", "Historical_simulations_rate_CORINE")

# Spatial distribution
for(f in folders){
  obs_22 <- vect("data/GIS_maps/presence_vectors/2022.shp")
  obs_22 <- project(obs_22, crs(hab_rast))
  
  map22_file = file.path("results", "simulations", f, "FemalesMap_status_yr_2022_presence_prob.csv")
  map22 <- csvToRaster(map22_file, hab_rast)
  map22 <- ifel(map22 == 0, NA, map22)
  
  p <- ggplot() +
          geom_sf(data = world_cropped, fill = "grey90", color = "grey30", linewidth = 0.3) +
          geom_spatvector(data = obs_22, fill = "grey100", color = "grey100") +
          geom_spatraster(data = map22) +
          scale_fill_gradientn(colours = c("transparent", "blue", "red"),
                               values = c(0, 0.0001, 1),
                               limits = c(0, 1),
                               na.value = NA)
  print(p)
  ggsave(paste0("results/", f, "_distribution_2022.png"), p)
  
}


# Population sizes
size_obs <- read.csv("data/original_data/Population_sizes_IUCN.csv")
size_obs$obs_size <- size_obs$Vale.do.Guadiana + size_obs$Doñana + size_obs$Matachel + size_obs$Sierra.Morena + size_obs$Toledo.Mountains

size_simO <- sim_size_format("Historical_simulations")
size_simR <- sim_size_format("Historical_simulations_rate")
size_simOC <- sim_size_format("Historical_simulations_CORINE")
size_simRC <- sim_size_format("Historical_simulations_rate_CORINE")


p_sizes <- ggplot() +
  geom_line(data = size_simO, aes(x = year, y = sim_size, group = interaction(Rsim, Tsize, threshold, months, rep), colour = "Original_LUCAS")) +
  geom_line(data = size_simR, aes(x = year, y = sim_size, group = interaction(Rsim, Tsize, threshold, months, rep), colour = "rate_LUCAS")) +
  geom_line(data = size_simOC, aes(x = year, y = sim_size, group = interaction(Rsim, Tsize, threshold, months, rep), colour = "Original_CORINE")) +
  geom_line(data = size_simRC, aes(x = year, y = sim_size, group = interaction(Rsim, Tsize, threshold, months, rep), colour = "rate_CORINE")) +
  geom_line(data = size_obs, aes(x = Year, y = obs_size), colour = "grey40", size = 2) 
  
ggsave("results/population_sizes_calibration_comparisons.png", p_sizes, width = 5.5, height = 6.1)


# Future simulations ----------------------------------------------------------------------------------------------------------------------------------------

folders <- c("Future_simulations", "Future_simulations_rate", "Future_simulations_rate_CORINE")

# Spatial distribution
for(f in folders){
  obs_22 <- vect("data/GIS_maps/presence_vectors/2022.shp")
  obs_22 <- project(obs_22, crs(hab_rast))
  
  map22_file = file.path("results", "simulations", f, "FemalesMap_status_yr_2050_presence_prob.csv")
  map22 <- csvToRaster(map22_file, hab_rast)
  map22 <- ifel(map22 == 0, NA, map22)
  
  p <- ggplot() +
    geom_sf(data = world_cropped, fill = "grey90", color = "grey30", linewidth = 0.3) +
    geom_spatvector(data = obs_22, fill = "grey100", color = "grey100") +
    geom_spatraster(data = map22) +
    scale_fill_gradientn(colours = c("transparent", "blue", "red"),
                         values = c(0, 0.0001, 1),
                         limits = c(0, 1),
                         na.value = NA)
  print(p + ggtitle(f))
  
  ggsave(paste0("results/", f, "_distribution_2050.png"), p)
  
}


# size_simO <- sim_size_format("Future_simulations")
# size_simR <- sim_size_format("Future_simulations_rate")
size_simRC <- sim_size_format("Future_simulations_rate_CORINE")
size_simRC$Rsim <- size_simRC$threshold 
size_simRC$rep <- size_simRC$months
size_simRC$threshold <- 1
size_simRC$months <- as.integer(gsub("61", "", size_simRC$Tsize))
size_simRC$Tsize <- 6

size_simRC <- size_simRC %>% filter(year < 2101)

future_sizes_plot <- ggplot(size_simRC) + 
  geom_line(aes(x = year, y = sim_size, group = interaction(Rsim, Tsize, threshold, months, rep)), alpha = 0.5)

ggsave("results/total_size_graph_Future_rate_CORINE.png", future_sizes_plot,
       width = 6.5, height = 4.3)








### compare breeding habitats  -- Run on an R session on DRAGO
library(dplyr)
library(ggplot2)
library(tidyterra)
library(sf)
library(rnaturalearth)

source("R/Rasterize_output_maps.R")

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

