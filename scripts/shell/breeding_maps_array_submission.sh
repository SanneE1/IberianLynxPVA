#!/bin/bash
#SBATCH --job-name=LynxBHArray
#SBATCH -p generic
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=24G
#SBATCH --time=2:00:00
#SBATCH --array=1-108
#SBATCH --output=job_reports/Lynx_BreedingMaps_array_%A_%a.log
#SBATCH --error=job_reports/Lynx_BreedingMaps_array_%A_%a.log

# Load required modules
module load rama0.4
module load GCC/13.3.0
module load OpenMPI/5.0.3
module load UDUNITS/2.2.28
module load GDAL/3.10.0
module load PROJ/9.4.1
module load GEOS/3.12.2
module load R/4.4.2

# Set the root folders for Rabbit input and breeding map output.
rabbit_root="data/Rabbit_output"
output_root="data/model_input/maps"

task_id=${SLURM_ARRAY_TASK_ID}

Rscript scripts/r/batch_create_breeding_maps.R \
  --rabbit-root="${rabbit_root}" \
  --output-root="${output_root}" \
  --task-id="${task_id}"
