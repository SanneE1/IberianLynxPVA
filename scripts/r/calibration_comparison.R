library(dplyr)
library(ggplot2)
library(tidyterra)
library(sf)
library(rnaturalearth)

source(file.path("scripts", "r", "Rasterize_output_maps.R"))

#----------------------------------------
# Settings
#----------------------------------------
# Only used if the object does not exist yet.

# Settings saved by scripts/Run_pipeline.R (path in the environment variable
# LYNX_PIPELINE_SETTINGS) are loaded first and replace the defaults below.
pipeline_settings <- Sys.getenv("LYNX_PIPELINE_SETTINGS")
if (nzchar(pipeline_settings) && file.exists(pipeline_settings)) {
  list2env(readRDS(pipeline_settings), envir = environment())
}

if (!exists("calibration_results_dir")) calibration_results_dir <- "results/calibration"
# Calibration run type to pass on to the simulations: the text before the first "_"
# of the result file names
if (!exists("calibration_prefix"))       calibration_prefix       <- "RCorrected"
if (!exists("summary_all_file"))         summary_all_file         <- file.path("results", "calibration_summary.csv")
if (!exists("calibration_summary_file")) calibration_summary_file <- file.path("results", paste0("calibration_summary_", calibration_prefix, ".csv"))
# Score = rmse_importance * population size fit + (1 - rmse_importance) * MCC (5 km)
if (!exists("rmse_importance"))    rmse_importance    <- 0.95
# Weight = softmax(mean score / weight_temperature); lower = more weight on the best sets
if (!exists("weight_temperature")) weight_temperature <- 0.1


files <- list.files(calibration_results_dir, 
                     recursive = T, full.names = T)

df <- lapply(files, function(x) {
  tryCatch(
  read.csv(x) %>% 
    mutate(type = stringr::str_split_i(basename(x), "_", 1)),
    error = function(e) NULL)
}) %>% bind_rows()


max_RMSE <- max(df$RMSE_sizes, na.rm = T)


df1 <- df %>%
  mutate(RMSEpop_norm = 1-(RMSE_sizes /max_RMSE), #scale(RMSE_sizes)[,1],
         MCC_5km_norm = (MCC_5km + 1) / 2,       #scale(-MCC_5km)[,1],                # Matthews Correlation Coefficient at 5km resolution
         score = RMSEpop_norm * rmse_importance + MCC_5km_norm * (1- rmse_importance)) %>%
  group_by(type, Tsize, threshold, n_months) %>%
  summarise(mean_score = mean(score, na.rm = T),
            best_score = min(score, na.rm = T),
            mean_RMSEnorm = mean(RMSEpop_norm, na.rm = T),
            mean_MCCnorm = mean(MCC_5km_norm, na.rm = T),
#            mean_500 = mean(MCC_500m, na.rm = T),
            mean_5k = mean(MCC_5km, na.rm = T),
#            mean_10k = mean(MCC_10km, na.rm = T),
#            mean_pophit_500 = mean(PopHit_500m, na.rm = T),
            mean_pophit_5k = mean(PopHit_5km, na.rm = T),
#            mean_pophit_10k = mean(PopHit_10km, na.rm = T),
            mean_pop = mean(RMSE_sizes, na.rm = T),
#            best_500 = max(MCC_500m, na.rm = T),
            best_5k = max(MCC_5km, na.rm = T),
#            best_10k = max(MCC_10km, na.rm = T),
#            best_pophit_500 = max(PopHit_500m, na.rm = T),
            best_pophit_5k = max(PopHit_5km, na.rm = T),
#            best_pophit_10k = max(PopHit_10km, na.rm = T),
            best_pop = min(RMSE_sizes, na.rm = T)) %>%
  ungroup() %>%
  mutate(weight = (exp(mean_score/weight_temperature) / sum(exp(mean_score/weight_temperature)))) %>%  #abs((mean_score-min(mean_score))/(max(mean_score)-min(mean_score))-1)) %>%
  arrange(desc(mean_score)) %>% 
  dplyr::select(type, Tsize, threshold, n_months, weight, mean_score, mean_5k, mean_pophit_5k, mean_pop)

write.csv(df1, summary_all_file, row.names = F)
write.csv(df1 %>% filter(type == calibration_prefix),
          calibration_summary_file, row.names = F)


cat('------------------------------------------------\n')
cat('Top 10 overall with best MCC at 5km and RMSE population estimate:\n')
cat('------------------------------------------------\n\n\n')

df1 %>% arrange(desc(mean_score)) %>% head(10) %>% print()

cat('\n\n------------------------------------------------\n')

cat('\n\n\nTop 10 over all with best MCC at 5km:\n')
df1 %>% arrange(desc(mean_5k)) %>% head(10) %>% print()

cat('\n\n\nTop 10 over all  with best population estimate:\n')
df1 %>% arrange(mean_pop) %>% head(10) %>% print()



