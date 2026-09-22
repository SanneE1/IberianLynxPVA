#!/bin/bash
#SBATCH --job-name=LynxWeightedSim
#SBATCH -p memory
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=160G
#SBATCH --time=24:00:00
#SBATCH --output=job_reports/Lynx_WeightedSim_output_%j.log
#SBATCH --error=job_reports/Lynx_WeightedSim_error_%j.log

# Usage:
# sbatch scripts/shell/run_weighted_simulation_batch_submission.sh <scenario> <samples> [workers] [seed] [inbreeding] [overwrite]
# Example:
# sbatch scripts/shell/run_weighted_simulation_batch_submission.sh historic 10 4 42 true false

module load rama0.4
module load GCC/13.3.0
module load OpenMPI/5.0.3
module load UDUNITS/2.2.28
module load GDAL/3.10.0
module load PROJ/9.4.1
module load GEOS/3.12.2
module load R/4.4.2

SCENARIO="$1"
SAMPLES="$2"
WORKERS="${3:-4}"
SEED="${4:-42}"
IC="${5:-false}"
OVERWRITE="${6:-false}"

if [ -z "$SCENARIO" ] || [ -z "$SAMPLES" ]; then
  echo "Usage: sbatch $0 <scenario> <samples> [workers] [seed] [inbreeding] [overwrite]"
  exit 1
fi

OVERWRITE_FLAG=""
if [ "$OVERWRITE" = "true" ] || [ "$OVERWRITE" = "1" ]; then
  OVERWRITE_FLAG="--overwrite"
fi

python3 scripts/python/run_weighted_simulation_batch.py \
  "$SCENARIO" \
  "$SAMPLES" \
  --workers "$WORKERS" \
  --seed "$SEED" \
  --calibration-csv "results/calibration_summary_RCorrected.csv" \
  --inbreeding "$IC" \
  $OVERWRITE_FLAG
