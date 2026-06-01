#!/bin/bash
#SBATCH --job-name=RabPostProc
#SBATCH -p generic
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem=60G
#SBATCH --time=03:00:00
#SBATCH --output=job_reports/Postprocess_output_%j.log
#SBATCH --error=job_reports/Postprocess_error_%j.log

SIM_DIR=$1
OUTPUT_DIR="results/simulations/${SIM_DIR}"
mkdir -p "$OUTPUT_DIR"

module load rama0.4
module load GCC/11.3.0
module load GCCcore/11.3.0
module load Python/3.10.4
module load OpenMPI/4.1.4
module load Bottleneck/1.3.7

python scripts/python/get_summary_maps_from_simulations.py "$SIM_DIR" "$OUTPUT_DIR" 

#rm -r "$SIM_DIR"
