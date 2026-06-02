# Lynx PVA Repository

This repository contains code for the Individual Based Iberian lynx population viability analysis (PVA) including rabbit density dependence.

## Repository layout

- `data/`
  - `GIS_maps/` - GIS rasters and map inputs used by R scripts and the model.
  - `model_input/maps/` - simplified model input `.txt` maps consumed by the Pascal model.
  - `original_data/` - raw input data sources.
  - `Rabbit_output/` - rabbit model CSV output folder for HPC simulation runs.

- `scripts/r/` - R scripts and helpers.
  
- `scripts/python/` - Python helper scripts and summary tools.

- `scripts/shell/` - HPC submission wrappers and sbatch job helper files.

- `Program/` - Pascal model sources and executables. 

## Workflow overview
This repository supports a full Lynx PVA workflow from data preparation through forecast simulation and post-processing.

### 1. Data preparation
Prepare the base habitat and calibration inputs before any model runs.
- Reclassify raw GIS maps into lynx habitat maps
  - `scripts/r/Reclassify_Lynx_spatial_map.R`
- Convert `.asc` habitat maps to model input `.txt` maps
  - `scripts/r/transform_asc_to_input_maps.R`
  - `scripts/python/transform_asc_to_input_txt_map.py`
- Prepare dispersal calibration start locations from GPS data
  - `scripts/r/Calibration_data_dispersal.R`
- Prepare observed presence/absence maps for calibration
  - `scripts/r/Format_presence_maps_for_calibration.R`
- Optional helper driver
  - `scripts/python/data_preparation.py`

### 2. Create breeding habitat maps from rabbit density outputs
Generate breeding habitat `.asc` maps using rabbit density thresholds and a minimum number of months above threshold.
- Shell command:
  - `sbatch scripts/shell/breeding_habitat_submission.sh <rabbit_csv_dir> <density_threshold> <n_months>`
- Underlying script:
  - `scripts/r/Create_breeding_maps.R`
- Outputs:
  - breeding habitat `.asc` maps
  - converted model input maps under `data/model_input/maps/<...>`

### 3. Calibration search
Run the Pascal model across parameter combinations and evaluate fit to observed lynx distribution and population size.
- Shell command:
  - `sbatch scripts/shell/calibration_submission.sh <rabbit_csv_dir> <settings_file> <model_output_name>`
- Underlying script:
  - `scripts/r/Territory_and_BH_calibration.R`
- Evaluation helpers:
  - `scripts/r/Presence_maps_accuracy.R`
  - `scripts/r/pop_sizes_accuracy.R`
- Outputs:
  - CSV files in `results/calibration/`

### 4. Select best parameter combinations
Inspect calibration results and choose the best-performing values for:
- rabbit density threshold
- minimum months at threshold
- lynx territory size

- Shell command:
   - `scripts/shell/calibration_comparison_submission.sh`
- Underlying script:
   - `scripts/r/calibration_comparison.R`
- Outputs:
   

### 5. Forecast simulations
Run forward model simulations with the selected parameter sets.
- Shell command:
  - `sbatch scripts/shell/simulation_submission.sh <rabbit_dir> <tsize> <settings_file> <model_output_name>`
- Model executable:
  - `Program/Executables/Run_model_debug`
- Outputs:
  - simulation folders containing `lynx_pop_size.csv`, `FemalesMap_status_*`, and other model outputs

### 6. Post-process and analyze simulation outputs
Generate summary maps and visualization from completed simulation runs.
- Shell command:
  - `sbatch scripts/shell/submission_simulation_summary.sh <simulation_parent_dir>`
- Underlying script:
  - `scripts/python/get_summary_maps_from_simulations.py`
- Visualization:
  - `scripts/r/Plot_results.R`
- Outputs:
  - summary maps in `results/simulations/<SIM_DIR>`
  - plot images in `results/`

### Notes
- `scripts/r/Rasterize_output_maps.R` is a helper sourced by several analysis scripts.
- The workflow assumes rabbit CSV output files already exist in `data/Rabbit_output/`.
- `scripts/shell/calibration_submission.sh` currently calls `analysis/Territory_and_BH_calibration.R`, while the file is located at `scripts/r/Territory_and_BH_calibration.R`.

## Example run:
Example HPC submission commands for the Lynx PVA workflow.
Adjust the paths, settings files, and parameters for your cluster.

1) Create breeding habitat maps from rabbit CSV outputs  
This uses the same script as the breeding habitat submission job.

```
RABBIT_INPUT_DIR="data/Rabbit_output/TEST_FOLDER"
DENSITY_THRESHOLD=5
N_MONTHS=12
sbatch scripts/shell/breeding_habitat_submission.sh "$RABBIT_INPUT_DIR" \
$DENSITY_THRESHOLD" "$N_MONTHS" 
```
2) Run the calibration workflow
MODEL_OUTPUT_NAME is a prefix for the run-specific output folder under data/Rabbit_output.
SETTINGS_FILE should point to the correct model settings file.

```
SETTINGS_FILE="data/model_input/past_calibration_settings.txt"
MODEL_OUTPUT_NAME="calibration_run"
sbatch scripts/shell/calibration_submission.sh "$RABBIT_INPUT_DIR"\ "$SETTINGS_FILE" "$MODEL_OUTPUT_NAME"
```

3) Run a model simulation job
TSIZE is the territory size parameter.
MODEL_OUTPUT_NAME will be appended with the slurm array ID.

```
TSIZE=10
SIM_OUTPUT_NAME="sim_run"
sbatch scripts/shell/simulation_submission.sh "$RABBIT_INPUT_DIR" "$TSIZE" "$SETTINGS_FILE" "$SIM_OUTPUT_NAME"
```

4) Post-process a completed simulation directory
SIM_DIR should be the base directory name containing multiple model output subfolders.

```
SIM_DIR="your_simulation_parent_dir"
sbatch scripts/shell/submission_simulation_summary.sh "$SIM_DIR"
```



