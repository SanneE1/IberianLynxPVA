#!/bin/bash
#SBATCH --job-name=LynxBHBatch
#SBATCH -p generic
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=24G
#SBATCH --time=2-00:00:00
#SBATCH --output=job_reports/Lynx_BreedingMaps_output_%j.log
#SBATCH --error=job_reports/Lynx_BreedingMaps_error_%j.log

# Load required modules
module load rama0.4
module load GCC/13.3.0
module load OpenMPI/5.0.3
module load UDUNITS/2.2.28
module load GDAL/3.10.0
module load PROJ/9.4.1
module load GEOS/3.12.2
module load R/4.4.2

# Run the batch breeding map creation script for all scenarios and replicates.
# The driver scans data/Rabbit_output/ and writes outputs to data/model_input/maps/.

Rscript scripts/r/batch_create_breeding_maps.R --rabbit-root=data/Rabbit_output --output-root=data/model_input/maps
