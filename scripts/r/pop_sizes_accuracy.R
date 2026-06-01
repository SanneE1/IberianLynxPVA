compare_pop_sizes <- function(size_file, sim_data) {
  
  obs_sizes <- read.csv(size_file)
  
  sim_sizes <- read.csv(file.path(sim_data, "lynx_pop_size.csv"), skip = 1, header = F) 
  
  b <- data.frame(Year = sim_sizes[,1],
                  N_sim = rowSums(sim_sizes[,-1], na.rm = T))
  
  a <- obs_sizes %>%
    group_by(Year) %>%
    summarise(N_obs = sum(`Total.ejemplares`, na.rm = T))
  
  # pops_lookup <- read.csv(file.path("data", "pop_id_lookup.csv"))
  
  df <- left_join(a,b)  %>%
    filter(Year < 2023)
  
  log_rmse = sqrt(mean((log(df$N_sim) - log(df$N_obs))^2))
  
  return(log_rmse)
  
  
}