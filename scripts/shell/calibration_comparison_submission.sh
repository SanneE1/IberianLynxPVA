#!/bin/bash
#SBATCH --job-name=LynxCalCompare
#SBATCH -p generic
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=0:10:00
#SBATCH --output=job_reports/calibration_comparison_output_%j.log
#SBATCH --error=job_reports/calibration_comparison_error_%j.log

# Load required modules
module load rama0.4
module load GCC/13.3.0
module load OpenMPI/5.0.3
module load UDUNITS/2.2.28
module load GDAL/3.10.0
module load PROJ/9.4.1
module load GEOS/3.12.2
module load R/4.4.2

Rscript scripts/r/calibration_comparison.R
