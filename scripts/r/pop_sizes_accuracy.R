#----------------------------------------
# Settings (defaults of compare_pop_sizes())
#----------------------------------------
# Only used if the object does not exist yet.

# Years compared with the census. The last year gets weight 4, the year before
# weight 2 and earlier years weight 1.
if (!exists("census_years")) census_years <- 2021:2024

compare_pop_sizes <- function(size_file, sim_data, years = census_years) {
  
  obs_sizes <- read.csv(size_file)
  
  sim_sizes <- read.csv(file.path(sim_data, "lynx_pop_size.csv"), skip = 1, header = F) 
  
  b <- data.frame(Year = sim_sizes[,1],
                  N_sim = rowSums(sim_sizes[,-1], na.rm = T))
  
  a <- obs_sizes %>%
    group_by(Year) %>%
    summarise(N_obs = sum(`Total.ejemplares`, na.rm = T))
  
  # pops_lookup <- read.csv(file.path("data", "pop_id_lookup.csv"))
  
  df <- left_join(a, b, by = "Year") %>%
  filter(Year %in% years) %>%
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