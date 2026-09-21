compare_pop_sizes <- function(size_file, sim_data) {
  
  obs_sizes <- read.csv(size_file)
  
  sim_sizes <- read.csv(file.path(sim_data, "lynx_pop_size.csv"), skip = 1, header = F) 
  
  b <- data.frame(Year = sim_sizes[,1],
                  N_sim = rowSums(sim_sizes[,-1], na.rm = T))
  
  a <- obs_sizes %>%
    group_by(Year) %>%
    summarise(N_obs = sum(`Total.ejemplares`, na.rm = T))
  
  # pops_lookup <- read.csv(file.path("data", "pop_id_lookup.csv"))
  
  df <- left_join(a, b, by = "Year") %>%
  filter(Year >= 2021, Year <= 2024) %>%
  mutate(
    error = N_sim - N_obs,
    year_weight = if_else(Year == max(Year), 4,
                   if_else(Year >= max(Year) - 1, 2, 1))
  )

 rmse_weighted <- sqrt(
   weighted.mean(df$error^2, df$year_weight, na.rm = TRUE)
)

  return(rmse_weighted)
  
}