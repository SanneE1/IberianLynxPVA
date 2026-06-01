library(dplyr)
library(ggplot2)
library(tidyterra)
library(sf)
library(rnaturalearth)

source(file.path("scripts", "r", "Rasterize_output_maps.R"))


filesO <- list.files("results/calibration/", 
                     pattern = "original",
                     recursive = T, full.names = T)
fileR <- list.files("results/calibration/", 
                    pattern = "ratefixed",
                    recursive = T, full.names = T)

dfO <- lapply(filesO, read.csv) %>% bind_rows() %>% mutate(type = "O")
dfR <- lapply(fileR, read.csv) %>% bind_rows() %>% mutate(type = "R")

df <- bind_rows(dfO, dfR)

df <- df %>% group_by(Tsize, threshold, n_months, type) %>%
  summarise(mean_500 = mean(MCC_500m, na.rm = T),
            mean_5k = mean(MCC_5km, na.rm = T),
            mean_10k = mean(MCC_10km, na.rm = T),
            mean_pop = mean(Pop_sizes, na.rm = T),
            max_500 = max(MCC_500m, na.rm = T),
            max_5k = max(MCC_5km, na.rm = T),
            max_10k = max(MCC_10km, na.rm = T),
            max_pop = max(Pop_sizes, na.rm = T)) %>%
  arrange(desc(mean_5k))





