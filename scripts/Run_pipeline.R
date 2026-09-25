# ----------------------------------------------------------------------------
# Lynx PVA pipeline
#
# Runs all steps in order on the HPC. Currently set for DRAGO (the CSIC HPC)
#    which uses SLURM. Using it on other HPC will require some changes, including
#    setting the correct partitions
#
# Run from the repository root:
#   Rscript scripts/Run_pipeline.R
#
# Every step waits until its SLURM job(s) are finished (sbatch --wait), so keep
# this session open (e.g. run it inside screen/tmux).
#
# All file locations and settings used by the pipeline scripts are set below.
# The scripts contain the same values as defaults, which they only use when a
# setting is not given (e.g. when a script is run on its own). How the settings
# reach each step:
#   - Data preparation is sourced, so it uses the objects defined here.
#   - The R scripts run by SLURM load the settings from pipeline_settings_file,
#     whose location is passed in the environment variable LYNX_PIPELINE_SETTINGS.
#   - The shell/Python scripts get their file locations as environment variables.
# Only the #SBATCH lines (partition, memory, time) and the module loads have to
# be changed in the scripts in scripts/shell/ themselves.
# ----------------------------------------------------------------------------

#----------------------------------------
# Settings (update these)
#----------------------------------------

## Steps to run ----------------------------------------------------------------

run_data_preparation <- TRUE
run_calibration      <- TRUE
run_comparison       <- TRUE
run_simulations      <- TRUE

## Input data: original data ---------------------------------------------------

corine_path             <- "data/original_data/U2018_CLC2018_V2020_20u1.tif"
presence_dir            <- "data/original_data/20250825_data_German/Presencias"
pops_file               <- file.path(presence_dir, "2022_peninsula_iberica/2022_peninsula.shp")
annual_distribution_dir <- "data/original_data/Annual_distribution_Alejandro"
biopop_file             <- "data/GIS_maps/manual_populations_drawn.shp"

# Census: population sizes for the start populations (xlsx) and calibration (csv)
census_file  <- "data/original_data/2025.08.06_LynxConnectWebsiteCensusNumber.xlsx"
census_sheet <- "Sheet2"
census_csv   <- "data/original_data/2025.08.06_LynxConnectWebsiteCensusNumber.csv"

# Released individuals
release_file  <- "data/original_data/Alejandro_information/250623 Lynx age at the time of release.xlsx"
release_sheet <- "Age of released lynx"
release_skip  <- 5

# Rivers (GRWL, Allen & Pavelsky 2018), downloaded to grwl_dir if not there yet
grwl_dir      <- "data/original_data/grwl_data"
grwl_zip_url  <- "https://zenodo.org/records/1297434/files/GRWL_summaryStats_V01.01.zip?download=1"
grwl_zip_name <- "GRWL_summaryStats_V01.01.zip"

## Input data: rabbit model output ---------------------------------------------

# Folders per scenario are named NC_simulation_Complete_<scenario>, with one
# subfolder per rabbit line
rabbit_root            <- "data/Rabbit_output"
rabbit_calibration_dir <- file.path(rabbit_root, "NC_simulation_Complete_historic")
rabbit_lines           <- c("line12", "line13", "line14")   # lines used for the calibration

## Model -----------------------------------------------------------------------

model_executable <- "Program/Executables/Run_model_debug"

# Model settings files (see README), for the calibration and per simulation scenario.
# With inbreeding = "true", use the settings files with track_pedigree 1.
calibration_settings <- "data/model_input/past_calibration_settings_IPMcorrected.txt"
simulation_settings  <- c(historic = "data/model_input/past_calibration_settings_IPMcorrected.txt",
                          ssp245   = "data/model_input/future_simulation_settings_IPMcorrected.txt",
                          ssp585   = "data/model_input/future_simulation_settings_IPMcorrected.txt")

## Parameters: data preparation ------------------------------------------------

# Template grid
peninsula_extent <- c(2574200, 3801100, 1515200, 2497800)  # xmin, xmax, ymin, ymax (EPSG:3035)
cell_size        <- 500   # m
max_land_class   <- 40    # CORINE classes below this are land (40+ = water)

# Populations
pop_buffer_m    <- 3000   # buffer around the observed populations (m)
biopop_buffer_m <- 1000   # buffer around the biological populations (m)

# Observed presence per year (calibration)
annual_distribution_years <- 2002:2018
presence_years <- c(2015, 2017, 2020:2022, 2002:2014, 2021)  # year of each shapefile in presence_dir, in list.files() order

# Start populations
start_census_year <- 2022
start_2005_rows   <- c(1, 4)     # rows of the 2022 start populations present in 2005 (Andujar-Cardena, Donana)
start_2005_sizes  <- c(56, 28)   # their population sizes in 2005

# Rivers
width_threshold_m <- 5              # keep rivers wider than this (m)
filter_stat       <- "width_mean"   # GRWL width statistic to filter on
raster_stat       <- "width_mean"   # GRWL width statistic for the river buffer

## Parameters: calibration -----------------------------------------------------

calibration_prefix <- "RCorrected"   # name of this calibration; the simulations use its summary

# Calibration grid: every combination is run n_reps times for every rabbit line
tsize_values     <- seq(from = 14, to = 48, by = 6)   # territory size (cells)
threshold_values <- c(1, 3, 6, 9)                     # rabbit density threshold
n_months_values  <- c(6, 9, 12)                       # months at or above the threshold
n_reps           <- 2

lynx_year_start_month <- 6   # a lynx year runs from June to May (breeding maps)

# Scoring
census_years    <- 2021:2024                                   # years compared with the census (weights 1, 1, 2, 4)
mcc_aggregation <- c(km5 = 10, km10 = 20)                      # aggregation (cells) for the 5 and 10 km MCC
pop_hit_buffers <- c(m500 = 500, km5 = 5000, km10 = 10000)     # distances (m) for the population hit rate

# Weights of the parameter sets
rmse_importance    <- 0.95   # score = 0.95 * population size fit + 0.05 * MCC (5 km)
weight_temperature <- 0.1    # weight = softmax(score / temperature)

## Parameters: simulations -----------------------------------------------------

scenarios  <- c("historic", "ssp245")
samples    <- 150      # parameter sets sampled per scenario
workers    <- 15       # model runs in parallel per scenario
seed       <- 42
inbreeding <- "false"
overwrite  <- "false"

## Output locations ------------------------------------------------------------

# GIS maps and model input
gis_dir              <- "data/GIS_maps"
model_input_dir      <- "data/model_input"
model_maps_dir       <- file.path(model_input_dir, "maps")   # also where the breeding maps are written
template_file        <- file.path(gis_dir, "Peninsula_500_template.tif")
presence_vectors_dir <- file.path(gis_dir, "presence_vectors")   # observed presence per year (calibration)
pop_lookup_file      <- "data/pop_id_lookup.csv"
start_pops_file      <- file.path(model_input_dir, "Lynx_start_pops_2022.txt")
start_pops_2005_file <- file.path(model_input_dir, "Lynx_start_pops_2005.txt")
reintro_output       <- file.path(model_input_dir, "Lynx_reintroductions.txt")
rivers_map_name      <- "Lynx_BreedingHabitat_rivers"

# Results
calibration_results_dir  <- "results/calibration"
summary_all_file         <- "results/calibration_summary.csv"
calibration_summary_file <- file.path("results", paste0("calibration_summary_", calibration_prefix, ".csv"))
runs_root                <- "results/simulation_runs"

# Copy of these settings, read by the scripts that run as SLURM jobs
pipeline_settings_file <- "results/pipeline_settings.rds"

#----------------------------------------
# Pass the settings on
#----------------------------------------

dir.create("job_reports", showWarnings = FALSE)   # log folder of the SLURM jobs (#SBATCH --output)
dir.create(dirname(pipeline_settings_file), showWarnings = FALSE, recursive = TRUE)

settings_names <- setdiff(ls(), c("settings_names"))
saveRDS(mget(settings_names), pipeline_settings_file)

# Environment variables for an sbatch call, e.g. "A='x' B='y'"
env_vars <- function(...) {
  v <- c(...)
  paste(paste0(names(v), "=", shQuote(v)), collapse = " ")
}

#----------------------------------------
# 1. Data preparation
#----------------------------------------
# Creates the template, habitat (Revilla), breeding (Fordham), rivers and
# population maps, the start population and reintroduction files, and converts
# the maps to model input (.txt) in data/model_input/maps/.
# Only needs to be rerun when the input data changes. Sourced (in its own
# environment), so settings defined above are used.

if (run_data_preparation) {
  source("scripts/r/Data_preparation.R", local = new.env())
}

#----------------------------------------
# 2. Calibration
#----------------------------------------
# For each rabbit line: runs the model for all threshold x n_months x Tsize
# combinations and scores them against observed presence and population sizes.
# Results are written to calibration_results_dir. The rabbit lines run in parallel,
# each as a SLURM array with one task per threshold x n_months combination.

if (run_calibration) {
  n_combinations <- length(threshold_values) * length(n_months_values)

  parallel::mclapply(rabbit_lines, function(line) {
    system(paste(env_vars(LYNX_PIPELINE_SETTINGS = pipeline_settings_file,
                          MODEL_EXE = model_executable,
                          OBS_DIR = presence_vectors_dir),
                 "sbatch --wait", paste0("--array=1-", n_combinations),
                 "scripts/shell/calibration_submission.sh",
                 file.path(rabbit_calibration_dir, line, ""),
                 calibration_settings,
                 paste0(calibration_prefix, "_RL", sub("line", "", line))))
  }, mc.cores = length(rabbit_lines))
}

#----------------------------------------
# 3. Calibration comparison
#----------------------------------------
# Combines the calibration results and calculates a weight per parameter set.
# Writes calibration_summary_file, used by the simulations.

if (run_comparison) {
  system(paste(env_vars(LYNX_PIPELINE_SETTINGS = pipeline_settings_file),
               "sbatch --wait scripts/shell/calibration_comparison_submission.sh"))
}

#----------------------------------------
# 4. Simulations
#----------------------------------------
# Samples parameter sets by their calibration weight, creates any missing
# breeding maps, runs the model and summarises the output in
# runs_root/<scenario>/. The scenarios run in parallel.

if (run_simulations) {
  parallel::mclapply(scenarios, function(scenario) {
    system(paste(env_vars(LYNX_PIPELINE_SETTINGS = pipeline_settings_file,
                          SIM_SETTINGS_FILE = simulation_settings[[scenario]],
                          CALIBRATION_CSV = calibration_summary_file,
                          RABBIT_ROOT = rabbit_root,
                          MAPS_ROOT = model_maps_dir,
                          RUNS_ROOT = runs_root,
                          MODEL_EXE = model_executable,
                          TEMPLATE = template_file),
                 "sbatch --wait scripts/shell/run_weighted_simulation_batch_submission.sh",
                 scenario, samples, workers, seed, inbreeding, overwrite))
  }, mc.cores = length(scenarios))
}

#----------------------------------------
# 5. Report
#----------------------------------------
# Plots and results report. Run locally once the simulation results are copied over:
#   quarto render Manuscript/PVA-result-report.qmd
