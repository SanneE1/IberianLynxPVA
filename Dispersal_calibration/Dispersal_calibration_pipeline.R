# ----------------------------------------------------------------------------
# Dispersal calibration
#
# Estimates the lynx dispersal parameters (alpha_steps, theta_d, delta_theta_long,
# delta_theta_f, L, N_d, beta, gamma) with ABC, by comparing one day of simulated
# dispersal with daily steps from GPS-collared lynx (Cisneros-Araujo).
#
# Uses the Pascal program Program/Executables/dispersal_calibration
# (source: Program/dispersal_calibration.lpr). Everything else is in this folder:
#   functions/  helper functions and the ABC script (Python, pyabc)
#   data/       model and ABC input files created by this pipeline
#   results/    ABC database, parameter estimates and plots
#
# Run from the repository root:
#   Rscript Dispersal_calibration/Dispersal_calibration_pipeline.R
#
# The estimated parameters are NOT copied into the model automatically. Update
# alpha_steps ... gamma in the demography file(s) in data/model_input/ by hand.
# ----------------------------------------------------------------------------

library(dplyr)
library(terra)

#----------------------------------------
# Settings (update these)
#----------------------------------------

# Which steps to run
run_prepare_data <- TRUE
run_abc          <- TRUE

# Input data
gps_file        <- "data/original_data/GPS_dispersal_data_Iberian_lynx_Cisneros-Araujo.csv"
habitat_asc     <- "data/GIS_maps/Lynx_HabitatMap_500_Peninsula_Revilla_2015_1.asc"   # to find barrier cells

# Model inputs (same maps as the population model)
demography_file <- "data/model_input/Lynx_demography_values.txt"
habitat_map     <- "data/model_input/maps/Lynx_HabitatMap_500_Peninsula_Revilla_2015_1.txt"
breeding_map    <- "data/model_input/maps/Lynx_BreedingHabitat_500_Peninsula_Fordham_2013.txt"

# Model executable (Windows build has .exe)
executable <- file.path("Program", "Executables",
                        paste0("dispersal_calibration", ifelse(.Platform$OS.type == "windows", ".exe", "")))

# Python with pyabc installed
python <- ifelse(.Platform$OS.type == "windows", "python", "python3")

# ABC settings
n_repeats           <- 10    # simulated individuals per observed step
population_size     <- 25
max_populations     <- 3
min_epsilon         <- 1
min_acceptance_rate <- 0.2

# Folders and files
data_dir    <- "Dispersal_calibration/data"
results_dir <- "Dispersal_calibration/results"

starting_file   <- file.path(data_dir, "calibration_dispersal_starting_locations.txt")
observed_file   <- file.path(data_dir, "calibration_dispersal_observed.csv")
full_table_file <- file.path(data_dir, "calibration_dispersal_full_table.csv")
settings_file   <- file.path(data_dir, "dispersal_calibration_settings.txt")

#----------------------------------------
# Functions
#----------------------------------------

source("Dispersal_calibration/functions/prepare_gps_data.R")
source("Dispersal_calibration/functions/write_settings.R")

dir.create(data_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)

#----------------------------------------
# 1. Prepare the observed dispersal data
#----------------------------------------
# Daily steps (16:00 to next 16:00) from the GPS data, converted to model grid
# cells. Writes the start locations for the model, the observed start/end cells
# for the ABC, and a settings file for the dispersal program.

if (run_prepare_data) {
  gps_steps <- prepare_gps_dispersal(gps_file, habitat_asc)
  n_rows <- write_dispersal_inputs(gps_steps, starting_file, observed_file, full_table_file)

  write_dispersal_settings(settings_file, demography_file, habitat_map, breeding_map,
                           starting_file, n_rows, n_repeats)
}

#----------------------------------------
# 2. ABC calibration
#----------------------------------------
# Samples dispersal parameters, runs the dispersal program for each set and keeps
# the sets whose simulated end points are closest to the observed ones.
# Writes the parameter estimates and plots to the results folder.

if (run_abc) {
  system2(python, c("Dispersal_calibration/functions/dispersal_abc.py",
                    "--executable", executable,
                    "--settings", settings_file,
                    "--observed", observed_file,
                    "--output-dir", results_dir,
                    "--n-repeats", n_repeats,
                    "--population-size", population_size,
                    "--max-populations", max_populations,
                    "--min-epsilon", min_epsilon,
                    "--min-acceptance-rate", min_acceptance_rate))
}
