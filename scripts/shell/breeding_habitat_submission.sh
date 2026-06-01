#!/bin/bash
#SBATCH --job-name=LynxCal
#SBATCH -p generic
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=20G
#SBATCH --time=1:00:00
#SBATCH --output=job_reports/create_BH_output_%A.log
#SBATCH --error=job_reports/create_BH_error_%A.log

RABDIR=$1
THRESHOLD=$2
NMONTHS=$3

# Load modules
module load rama0.4  
module load GCC/13.3.0
module load OpenMPI/5.0.3
module load UDUNITS/2.2.28
module load GDAL/3.10.0
module load PROJ/9.4.1
module load GEOS/3.12.2
module load R/4.4.2


Rscript scripts/r/Create_breeding_maps.R "$RABDIR" "$THRESHOLD" "$NMONTHS" 