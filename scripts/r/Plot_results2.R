template        <- "data/GIS_maps/Peninsula_500_template.tif"
source("scripts/r/Rasterize_output_maps.R")

r <- terra::rast(template)

files_all <- list.files("results/rabbit_simulation_summary_maps/", 
                        pattern = ".csv",
                        recursive = T, full.names = T)
std_files <- list.files("results/rabbit_simulation_summary_maps/", 
                        pattern = "std.csv",
                        recursive = T,  full.names = T)

files <- setdiff(files_all, std_files)


for (f in files) {
  csvToRaster(fileName = f, habitat_raster = r, 
              save_tiff = T, tiff_name = gsub(".csv", ".tif", f))
}


hist_sim <- list.files("results/simulations/historic_06.19/summary_maps/", 
                       full.names = T)

for (f in hist_sim) {
  csvToRaster(f, r, save_tiff = T, tiff_name = gsub(".csv", ".tif", f))
}


## SSP historic --------------------------------------------------------------------------------------------
status_files <- list.files("results/simulations/simulation_runs/historic/", 
                           pattern = "FemalesMap_status_yr_2024",
                           recursive = T, full.names = T)
sum_file <- c(list.files("results/simulations/simulation_runs/historic/summary/", 
                           recursive = T, full.names = T),
              list.files("results/simulations/simulation_runs/historic/summary_maps/", 
                         recursive = T, full.names = T))

status_files <- setdiff(status_files, sum_file)

traveledF_files <- list.files("results/simulations/simulation_runs/historic/", 
                             pattern = "FemalesMap_traveled",
                             recursive = T, full.names = T)
traveledM_files <- list.files("results/simulations/simulation_runs/historic/", 
                              pattern = "MalesMap_traveled",
                              recursive = T, full.names = T)

traveledF_files <- setdiff(traveledF_files, sum_file)
traveledM_files <- setdiff(traveledM_files, sum_file)

rast_outFiles <- function(f, rast_template = r){
  mat_status <- as.matrix(read.csv(f, header = F))
  df <- terra::rasterize(mat_status, rast_template)
  values(df) <- mat_status
  return(df)}


status_rast <- lapply(status_files, rast_outFiles) %>%
  rast(.)
presence_rast <- status_rast > -1
prob_rast <- mean(presence_rast)
writeRaster(prob_rast, filename = "results/simulations/simulation_runs/FemalePresenceProb_historic_2025.tif")

travF_rast <- lapply(traveledF_files, rast_outFiles) %>%
  rast(.) %>% mean(.)
travM_rast <- lapply(traveledM_files, rast_outFiles) %>%
  rast(.) %>% mean(.)
writeRaster(travF_rast, filename = "results/simulations/simulation_runs/FemaleTraveled_historic_2025.tif")
writeRaster(travM_rast, filename = "results/simulations/simulation_runs/MaleTraveled_historic_2025.tif")


size_obs <- read.csv("data/original_data/Population_sizes_IUCN.csv")
size_obs$obs_size <- size_obs$Vale.do.Guadiana + size_obs$Doñana + size_obs$Matachel + size_obs$Sierra.Morena + size_obs$Toledo.Mountains

size_files <- list.files("results/simulations/simulation_runs/historic/", 
                           pattern = "lynx_biopop_size.csv",
                           recursive = T, full.names = T)

size_hist <- setdiff(size_files, sum_file)
size_hist <- lapply(size_hist, read.csv) %>%
  bind_rows(.id = "id") %>%
  filter(year < 2023)
size_hist$tot_size <- rowSums(size_hist[,-c(1,2,9)], na.rm = T)

ggplot() +
  geom_line(data = size_hist, 
            aes(x = year, y = tot_size, group = id, colour = "Simulations")) +
  geom_line(data = size_obs, 
            aes(x = Year, y = obs_size, colour = "Observed"), size = 2) +
  scale_colour_manual(name = NULL,
                      values = c("Simulations" = "black", "Observed" = "red")) +
  xlab("Population size") + ylab("Year") +
  theme_minimal() + 
  theme(text = element_text(size = 14), legend.position = "bottom")


## SSP 585
status_files <- list.files("results/simulations/simulation_runs/ssp585/", 
                           pattern = "FemalesMap_status_yr_2050",
                           recursive = T, full.names = T)
sum_file <- c(list.files("results/simulations/simulation_runs/ssp585/summary/", 
                         recursive = T, full.names = T),
              list.files("results/simulations/simulation_runs/ssp585/summary_maps/", 
                         recursive = T, full.names = T))

status_files <- setdiff(status_files, sum_file)

traveledF_files <- list.files("results/simulations/simulation_runs/ssp585/", 
                              pattern = "FemalesMap_traveled",
                              recursive = T, full.names = T)
traveledM_files <- list.files("results/simulations/simulation_runs/ssp585/", 
                              pattern = "MalesMap_traveled",
                              recursive = T, full.names = T)

traveledF_files <- setdiff(traveledF_files, sum_file)
traveledM_files <- setdiff(traveledM_files, sum_file)

rast_outFiles <- function(f, rast_template = r){
  mat_status <- as.matrix(read.csv(f, header = F))
  df <- terra::rasterize(mat_status, rast_template)
  values(df) <- mat_status
  return(df)}


status_rast <- lapply(status_files, rast_outFiles) %>%
  rast(.)
presence_rast <- status_rast > -1
prob_rast <- mean(presence_rast)
writeRaster(prob_rast, filename = "results/simulations/simulation_runs/FemalePresenceProb_ssp585_2050.tif", overwrite=T)

travF_rast <- lapply(traveledF_files, rast_outFiles) %>%
  rast(.) %>% mean(.)
travF_rast_sd <- lapply(traveledF_files, rast_outFiles) %>%
  rast(.) %>% app(., fun = sd, na.rm = TRUE)

travF_rast_U <- travF_rast + 1.96 * travF_rast_sd
travF_rast_L <- travF_rast - 1.96 * travF_rast_sd

travM_rast <- lapply(traveledM_files, rast_outFiles) %>%
  rast(.) %>% mean(.)
travM_rast_sd <- lapply(traveledM_files, rast_outFiles) %>%
  rast(.) %>% app(., fun = sd, na.rm = TRUE)

travM_rast_U <- travM_rast + 1.96 * travM_rast_sd
travM_rast_L <- travM_rast - 1.96 * travM_rast_sd

writeRaster(travF_rast, filename = "results/simulation_runs/FemaleTraveled_ssp585_2050.tif")
writeRaster(travM_rast, filename = "results/simulation_runs/MaleTraveled_ssp585_2050.tif")

writeRaster(travF_rast_U, filename = "results/simulation_runs/FemaleTraveled_ssp585_2050_CIUpper.tif")
writeRaster(travF_rast_L, filename = "results/simulation_runs/FemaleTraveled_ssp585_2050_CILower.tif")

# Population sizes
size_obs <- read.csv("data/original_data/Population_sizes_IUCN.csv")
size_obs$obs_size <- size_obs$Vale.do.Guadiana + size_obs$Doñana + size_obs$Matachel + size_obs$Sierra.Morena + size_obs$Toledo.Mountains

size_files <- list.files("results/simulation_runs/ssp585/", 
                         pattern = "lynx_biopop_size.csv",
                         recursive = T, full.names = T)


size_hist <- setdiff(size_files, sum_file)
size_hist <- lapply(size_hist, read.csv) %>%
  bind_rows(.id = "id") %>%
  filter(year < 2050)
size_hist$tot_size <- rowSums(size_hist[,-c(1,2,9)], na.rm = T)

fut_plot <- ggplot() +
  geom_line(data = size_hist, 
            aes(x = year, y = tot_size, group = id, colour = "Simulations")) +
  geom_line(data = size_obs, 
            aes(x = Year, y = obs_size, colour = "Observed"), size = 2) +
  scale_colour_manual(name = NULL,
                      values = c("Simulations" = "black", "Observed" = "red")) +
  ylab("Population size") + xlab("Year") +
  theme_minimal() + 
  theme(text = element_text(size = 14), legend.position = "bottom")

ggsave(fut_plot, filename = "results/simulation_runs/Tot_pop_projections_2050.png") 
























