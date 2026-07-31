library(dplyr)

source(file.path("scripts", "r", "Create_breeding_maps.R"))
source(file.path("scripts", "r", "Presence_maps_accuracy.R"))
source(file.path("scripts", "r", "pop_sizes_accuracy.R"))

# r_folder = "data/Rabbit_output/"
# settings_file = "data/model_input/past_calibration_settings.txt"
# model_location = "Program/Executables/Run_model_debug.exe"
# model_output = "cal_test"
# obs_dir = "data/GIS_maps/presence_vectors/"
# r = 1
# rep = 1

args = commandArgs(trailingOnly = T)

r_folder = args[1]
settings_file = args[2]
model_output = args[3]
model_location = args[4]
obs_dir = args[5]
r = as.integer(args[6])

cat("Arguments received: \n",
    "Rabbit folder: ", r_folder, "\n",
    "Settings file: ", settings_file, "\n",
    "Model output folder: ", model_output, "\n",
    "Model executable location: ", model_location, "\n",
    "Observations directory: ", obs_dir, "\n",
    "Calibration parameter row: ", r, "\n")


if(!dir.exists(model_output)){
  dir.create(model_output, recursive = T)
}

#----------------------------------------
# Set calibration parameter combinations
#----------------------------------------

Tsize <- seq(from = 10, to = 50, by = 5)
threshold <- seq(from = 1, to = 13, by = 3)
n_months <- c(6,9,12)

cal_df <- expand.grid("threshold" = threshold, "n_months" = n_months)

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

t = cal_df$threshold[r]
n = cal_df$n_months[r]

asc_dir = paste(basename(r_folder), t, n, sep = "_")

cat("Running calibration with parameters: \n",
    "Threshold: ", t, "\n",
    "N_months: ", n, "\n",
    "Rabbit folder: ", r_folder, "\n",
    "Temporary ASC folder: ", asc_dir, "\n",
    "Processing Folder now\n")

b_folder <- Create_breeding_maps(rabbit_folder = r_folder, density_threshold = t, n_months = n, asc_dir = asc_dir)

for(s in Tsize) {
  cat("Tsize: ", s, "\n")

  for(rep in c(1:10)) {  
    cat("Rep: ", rep, "\n")

    cmd = paste(model_location, settings_file, model_output, s, b_folder)
    
    exit_code = system(cmd, intern = FALSE, ignore.stdout = FALSE)

    if (exit_code != 0) {
      message("Command failed on iteration ", s, "in rep ", rep, " with exit code ", exit_code)
    } else { 
    
    mcc <- mean_MCC(obs_dir = obs_dir, sim_data = model_output, hab_rast = file.path("data", "GIS_maps", "Lynx_HabitatMap_LUCAS_2015.asc"))
    
    popsizes <- compare_pop_sizes(size_file = file.path("data", "original_data", "2025.08.06_LynxConnectWebsiteCensusNumber.csv"), 
                                  sim_data = model_output)
    
    result <- data.frame("Tsize" = s,
                         "threshold" = t,
                         "n_months" = n,
                         "rabbit_folder" = r_folder,
                         "rep" = rep,
                         "MCC_500m" = mcc$mcc_500m,
                         "MCC_5km" = mcc$mcc_5km,
                         "MCC_10km" = mcc$mcc_10km,
                         "Pop_sizes" = popsizes)
    
    result_df <- rbind(result_df, result)
    }
    
    unlink(model_output, recursive = T)

  }
}

file_output = file.path("results", "calibration", paste0(paste(model_output, t,n, sep = "_"), ".csv"))

if(!dir.exists(dirname(file_output))){
  dir.create(dirname(file_output), recursive = T)
}

write.csv(result_df, file = file_output, row.names = F)

unlink(b_folder)
