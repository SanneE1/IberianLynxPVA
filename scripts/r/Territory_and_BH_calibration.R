library(dplyr)

#----------------------------------------
# Settings
#----------------------------------------
# Run-specific arguments come from the command line (scripts/shell/calibration_submission.sh):
#   Rscript scripts/r/Territory_and_BH_calibration.R <rabbit_folder> <settings_file>
#           <model_output> <model_executable> <obs_dir> <parameter_row>
# Without arguments (e.g. when testing interactively), existing objects with
# these names are used, otherwise the defaults below. The same applies to all
# other settings.

# Settings saved by scripts/Run_pipeline.R (path in the environment variable
# LYNX_PIPELINE_SETTINGS) are loaded first and replace the defaults below.
pipeline_settings <- Sys.getenv("LYNX_PIPELINE_SETTINGS")
if (nzchar(pipeline_settings) && file.exists(pipeline_settings)) {
  list2env(readRDS(pipeline_settings), envir = environment())
}

args <- commandArgs(trailingOnly = TRUE)
if (length(args) >= 6) {
  r_folder       <- args[1]
  settings_file  <- args[2]
  model_output   <- args[3]
  model_location <- args[4]
  obs_dir        <- args[5]
  param_row      <- as.integer(args[6])
}

if (!exists("r_folder"))       r_folder       <- "data/Rabbit_output/NC_simulation_Complete_historic/line12/"
if (!exists("settings_file"))  settings_file  <- "data/model_input/past_calibration_settings_IPMcorrected.txt"
if (!exists("model_output"))   model_output   <- "cal_test"
if (!exists("model_location")) model_location <- "Program/Executables/Run_model_debug"
if (!exists("obs_dir"))        obs_dir        <- "data/GIS_maps/presence_vectors/"
if (!exists("param_row"))      param_row      <- 1   # row of the threshold x n_months grid (= SLURM array task)

# Calibration grid. The number of threshold x n_months combinations (now 12)
# must match #SBATCH --array in scripts/shell/calibration_submission.sh
if (!exists("tsize_values"))     tsize_values     <- seq(from = 14, to = 48, by = 6)   # territory size (cells)
if (!exists("threshold_values")) threshold_values <- c(1, 3, 6, 9)                     # rabbit density threshold
if (!exists("n_months_values"))  n_months_values  <- c(6, 9, 12)                       # months at or above the threshold
if (!exists("n_reps"))           n_reps           <- 2                                 # model runs per combination

# Scoring and output
if (!exists("template_file"))           template_file           <- "data/GIS_maps/Peninsula_500_template.tif"
if (!exists("census_csv"))              census_csv              <- "data/original_data/2025.08.06_LynxConnectWebsiteCensusNumber.csv"
if (!exists("calibration_results_dir")) calibration_results_dir <- "results/calibration"

source(file.path("scripts", "r", "Create_breeding_maps.R"))
source(file.path("scripts", "r", "Presence_maps_accuracy.R"))
source(file.path("scripts", "r", "pop_sizes_accuracy.R"))

cat("Arguments received: \n",
    "Rabbit folder: ", r_folder, "\n",
    "Settings file: ", settings_file, "\n",
    "Model output folder: ", model_output, "\n",
    "Model executable location: ", model_location, "\n",
    "Observations directory: ", obs_dir, "\n",
    "Calibration parameter row: ", param_row, "\n")


if(!dir.exists(model_output)){
  dir.create(model_output, recursive = T)
}

#----------------------------------------
# Set calibration parameter combinations
#----------------------------------------

cal_df <- expand.grid("threshold" = threshold_values, "n_months" = n_months_values)

result_df <- data.frame("Tsize" = c(),
                        "threshold" = c(),
                        "n_months" = c(),
                        "rabbit_folder" = c(),
                        "rep" = c(),
                        "MMC_500m" = c(),
                        "MMC_5km" = c(),
                        "MMC_10km" = c())

#----------------------------------------
# Run calibration
#----------------------------------------

t = cal_df$threshold[param_row]
n = cal_df$n_months[param_row]

asc_dir = paste(basename(r_folder), t, n, sep = "_")

cat("Running calibration with parameters: \n",
    "Threshold: ", t, "\n",
    "N_months: ", n, "\n",
    "Rabbit folder: ", r_folder, "\n",
    "Temporary ASC folder: ", asc_dir, "\n",
    "Processing Folder now\n")

b_folder <- Create_breeding_maps(rabbit_folder = r_folder, density_threshold = t, n_months = n, asc_dir = asc_dir)

for(s in tsize_values) {
  cat("Tsize: ", s, "\n")

  for(rep in seq_len(n_reps)) {  
    cat("Rep: ", rep, "\n")

    cmd = paste(model_location, settings_file, model_output, s, b_folder)
    
    exit_code = system(cmd, intern = FALSE, ignore.stdout = FALSE)

    if (exit_code != 0) {
      message("Command failed on iteration ", s, "in rep ", rep, " with exit code ", exit_code)
    } else { 
    
    mcc <- mean_MCC(obs_dir = obs_dir, sim_data = model_output, hab_rast = template_file)

    pophit <- mean_pop_hit(obs_dir = obs_dir, sim_data = model_output,
                           hab_rast = template_file)
    
    popsizes <- compare_pop_sizes(size_file = census_csv, 
                                  sim_data = model_output)
    
    result <- data.frame("Tsize" = s,
                         "threshold" = t,
                         "n_months" = n,
                         "rabbit_folder" = r_folder,
                         "rep" = rep,
                         "MCC_500m" = mcc$mcc_500m,
                         "MCC_5km" = mcc$mcc_5km,
                         "MCC_10km" = mcc$mcc_10km,
                         "RMSE_sizes" = popsizes,
                         "PopHit_500m" = pophit$PopHit_500m,
                         "PopHit_5km" = pophit$PopHit_5km,
                         "PopHit_10km" = pophit$PopHit_10km,
                         "PopHit_meanDistKm" = pophit$PopHit_meanDistKm,
                         "PopHit_medianDistKm" = pophit$PopHit_medianDistKm)
    
    result_df <- rbind(result_df, result)
    }
    
    unlink(model_output, recursive = T)

  }
}

file_output = file.path(calibration_results_dir, paste0(paste(model_output, t,n, sep = "_"), ".csv"))

if(!dir.exists(dirname(file_output))){
  dir.create(dirname(file_output), recursive = T)
}

write.csv(result_df, file = file_output, row.names = F)

unlink(b_folder)
