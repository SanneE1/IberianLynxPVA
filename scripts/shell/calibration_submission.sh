#!/bin/bash
#SBATCH --job-name=LynxCal
#SBATCH -p generic
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=20G
#SBATCH --time=12:00:00
#SBATCH --array=1-12
#SBATCH --output=job_reports/Lynx_Calibration_output_%A_%a.log
#SBATCH --error=job_reports/Lynx_Calibration_error_%A_%a.log

RABDIR=$1
SETTINGS=$2
MODEL_OUT=$3
MODEL_EXE="Program/Executables/Run_model_debug"
OBS_DIR="data/GIS_maps/presence_vectors/"

TASK_ID=${SLURM_ARRAY_TASK_ID}

MODEL_OUTPUT="${MODEL_OUT}_${TASK_ID}"

# Load modules
module load rama0.4  
module load GCC/13.3.0
module load OpenMPI/5.0.3
module load UDUNITS/2.2.28
module load GDAL/3.10.0
module load PROJ/9.4.1
module load GEOS/3.12.2
module load R/4.4.2


Rscript scripts/r/Territory_and_BH_calibration.R "$RABDIR" "$SETTINGS" "$MODEL_OUTPUT" "$MODEL_EXE" "$OBS_DIR" "$TASK_ID"

rm -rf "$MODEL_OUTPUT"