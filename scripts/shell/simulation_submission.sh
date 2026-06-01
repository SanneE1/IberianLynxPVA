#!/bin/bash
#SBATCH --job-name=LynxCal
#SBATCH -p generic
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=20G
#SBATCH --time=2-00
#SBATCH --array=1-10
#SBATCH --output=job_reports/Lynx_Simulation_output_%A_%a.log
#SBATCH --error=job_reports/Lynx_Simulation_error_%A_%a.log

TSIZE=$2
RABDIR=$1
SETTINGS=$3
MODEL_OUT=$4

ARRAY_OUT="${MODEL_OUT}_${SLURM_ARRAY_TASK_ID}"
echo "$ARRAY_OUT"

./Program/Executables/Run_model_debug "$SETTINGS" "$ARRAY_OUT" "$TSIZE" "$RABDIR"