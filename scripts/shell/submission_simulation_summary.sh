#!/bin/bash
#SBATCH --job-name=RabPostProc
#SBATCH -p generic
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem=60G
#SBATCH --time=03:00:00
#SBATCH --output=job_reports/Postprocess_output_%j.log
#SBATCH --error=job_reports/Postprocess_error_%j.log

set -euo pipefail

SIM_DIR=$1
OUTPUT_DIR=$2
mkdir -p "$OUTPUT_DIR"

module purge
module load rama0.4
module load GCC/13.3.0
module load Python/3.12.3
module load SciPy-bundle/2024.05

python scripts/python/get_summary_maps_from_simulations.py "$SIM_DIR" "$OUTPUT_DIR" --template data/GIS_maps/Peninsula_500_template.tif

#rm -r "$SIM_DIR"
