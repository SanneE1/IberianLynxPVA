library(dplyr)
library(ggplot2)
library(tidyterra)
library(sf)
library(rnaturalearth)

source(file.path("scripts", "r", "Rasterize_output_maps.R"))


files <- list.files("results/calibration/", 
                     recursive = T, full.names = T)

df <- lapply(files, function(x) {
  tryCatch(
  read.csv(x) %>% 
    mutate(type = stringr::str_split_i(basename(x), "_", 1)),
    error = function(e) NULL)
}) %>% bind_rows()


df1 <- df %>%
  mutate(RMSEpop_norm = scale(Pop_sizes)[,1],
         MCC_5k_norm = scale(-MCC_5km)[,1],
         score = RMSEpop_norm + MCC_5k_norm) %>%
  group_by(type, Tsize, threshold, n_months) %>%
  summarise(mean_score = mean(score, na.rm = T),
            best_score = min(score, na.rm = T),
            mean_500 = mean(MCC_500m, na.rm = T),
            mean_5k = mean(MCC_5km, na.rm = T),
            mean_10k = mean(MCC_10km, na.rm = T),
            mean_pop = mean(Pop_sizes, na.rm = T),
            best_500 = max(MCC_500m, na.rm = T),
            best_5k = max(MCC_5km, na.rm = T),
            best_10k = max(MCC_10km, na.rm = T),
            best_pop = min(Pop_sizes, na.rm = T)) %>%
  ungroup() %>%
  mutate(weight = abs((mean_score-min(mean_score))/(max(mean_score)-min(mean_score))-1)) %>%
  arrange(mean_score) %>% 
  dplyr::select(type, Tsize, threshold, n_months, weight, mean_score, mean_5k, mean_pop)

write.csv(df1, file.path("results", "calibration_summary.csv"), row.names = F)
write.csv(df1 %>% filter(type == "RCorrected"), 
          file.path("results", "calibration_summary_RCorrected.csv"), row.names = F)

sample_df <- df1 %>% filter(type == "RCorrected") %>% 
              sample_n(nrow(.), 
                       size = 500,
                       weight = weight, replace = T)

write.csv(sample_df, 
          file.path("results", "simulation_parameters_RCorrected_sampled.csv"), 
          row.names = F)

sample_df2 <- df1 %>% filter(type == "RIPM") %>% 
              sample_n(nrow(.), 
                       size = 500,
                       weight = weight, replace = T)

write.csv(sample_df2, 
          file.path("results", "simulation_parameters_RIPM_sampled.csv"), 
          row.names = F)

sample_df3 <- df1 %>% filter(type == "ROriginal") %>% 
              sample_n(nrow(.), 
                       size = 500,
                       weight = weight, replace = T)

write.csv(sample_df3, 
          file.path("results", "simulation_parameters_ROriginal_sampled.csv"), 
          row.names = F)


cat('------------------------------------------------\n')
cat('Top 10 overall with best MCC at 5km and RMSE population estimate:\n')
cat('------------------------------------------------\n\n\n')

df1 %>% arrange(mean_score) %>% head(10) %>% print()

cat('\n\n------------------------------------------------\n')

cat('\n\n\nTop 10 replicates with best MCC at 5km:\n')
df1 %>% arrange(desc(best_5k)) %>% head(10) %>% print()

cat('\n\n\nTop 10 over all with best MCC at 5km:\n')
df1 %>% arrange(desc(mean_5k)) %>% head(10) %>% print()

cat('\n\n\nTop 10 replicates with best MCC at 10km:\n')
df1 %>% arrange(desc(best_10k)) %>% head(10) %>% print()

cat('\n\n\nTop 10 over all with best MCC at 10km:\n')
df1 %>% arrange(desc(mean_10k)) %>% head(10) %>% print()

cat('\n\n\nTop 10 replicates with best population estimate:\n')
df1 %>% arrange(desc(best_pop)) %>% head(10) %>% print()

cat('\n\n\nTop 10 over all  with best population estimate:\n')
df1 %>% arrange(mean_pop) %>% head(10) %>% print()  



