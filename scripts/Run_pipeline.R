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
# ----------------------------------------------------------------------------

#----------------------------------------
# Settings (update these)
#----------------------------------------

# Which steps to run
run_data_preparation <- TRUE
run_calibration      <- TRUE
run_comparison       <- TRUE
run_simulations      <- TRUE

# Calibration
calibration_settings <- "data/model_input/past_calibration_settings_IPMcorrected.txt"
calibration_prefix   <- "RCorrected"   # calibration_comparison.R filters on this name
rabbit_lines         <- c("line12", "line13", "line14")
rabbit_dir           <- "data/Rabbit_output/NC_simulation_Complete_historic"

# Simulations
scenarios  <- c("historic", "ssp245")
samples    <- 150
workers    <- 15
seed       <- 42
inbreeding <- "false"
overwrite  <- "false"

dir.create("job_reports", showWarnings = FALSE)  # log folder used by the submission scripts

#----------------------------------------
# 1. Data preparation
#----------------------------------------
# Creates the template, habitat (Revilla), breeding (Fordham), rivers and
# population maps, the start population and reintroduction files, and converts
# the maps to model input (.txt) in data/model_input/maps/.
# Only needs to be rerun when the input data changes.

if (run_data_preparation) {
  system("Rscript scripts/r/Data_preparation.R")
}

#----------------------------------------
# 2. Calibration
#----------------------------------------
# For each rabbit line: runs the model for all threshold x n_months x Tsize
# combinations and scores them against observed presence and population sizes.
# Results are written to results/calibration/. The rabbit lines run in parallel.

if (run_calibration) {
  parallel::mclapply(rabbit_lines, function(line) {
    system(paste("sbatch --wait scripts/shell/calibration_submission.sh",
                 file.path(rabbit_dir, line, ""),
                 calibration_settings,
                 paste0(calibration_prefix, "_RL", sub("line", "", line))))
  }, mc.cores = length(rabbit_lines))
}

#----------------------------------------
# 3. Calibration comparison
#----------------------------------------
# Combines the calibration results and calculates a weight per parameter set.
# Writes results/calibration_summary_RCorrected.csv, used by the simulations.

if (run_comparison) {
  system("sbatch --wait scripts/shell/calibration_comparison_submission.sh")
}

#----------------------------------------
# 4. Simulations
#----------------------------------------
# Samples parameter sets by their calibration weight, creates any missing
# breeding maps, runs the model and summarises the output in
# results/simulation_runs/<scenario>/. The scenarios run in parallel.

if (run_simulations) {
  parallel::mclapply(scenarios, function(scenario) {
    system(paste("sbatch --wait scripts/shell/run_weighted_simulation_batch_submission.sh",
                 scenario, samples, workers, seed, inbreeding, overwrite))
  }, mc.cores = length(scenarios))
}

#----------------------------------------
# 5. Report
#----------------------------------------
# Plots and results report. Run locally once the simulation results are copied over:
#   quarto render Manuscript/PVA-result-report.qmd
