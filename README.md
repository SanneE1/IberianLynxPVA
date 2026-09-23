# Iberian lynx PVA

Spatially explicit, individual-based population viability analysis (PVA) for the Iberian lynx (*Lynx pardinus*) on the Iberian Peninsula, with breeding habitat driven by simulated rabbit densities.

The model is written in Free Pascal. The data preparation, calibration and post-processing use R and Python, and the full workflow is designed to run on an HPC cluster with SLURM.

## Contents

- [Repository layout](#repository-layout)
- [Requirements](#requirements)
- [Input data](#input-data)
- [Running the simulations](#running-the-simulations)
- [Model settings and outputs](#model-settings-and-outputs)
- [Additional workflows](#additional-workflows)
- [Troubleshooting](#troubleshooting)

## Repository layout

```
scripts/
  Run_pipeline.R           Main pipeline: calibration and simulations, in order
  r/                       R scripts called by the pipeline
  python/                  Simulation batch runner and summary maps
  shell/                   SLURM submission scripts
Program/                   Pascal model source (Model_cmd.lpr, lynx/*.pas) and executables
Spatial_map_options/       Alternative habitat maps (Revilla, Fordham, PCA, land cover), historic and future
Dispersal_calibration/     ABC calibration of the dispersal parameters
Manuscript/                Results report (PVA-result-report.qmd)
data/                      Input data (not in git, see Input data)
results/                   Calibration and simulation output (not in git)
```

## Requirements

**Model**
- [Lazarus / Free Pascal](https://www.lazarus-ide.org/) to build the model. Linux and Windows builds of `Run_model_debug` are in `Program/Executables/`. To rebuild:
  ```
  lazbuild --build-mode=Debug Program/Model_cmd.lpi
  ```

**R (4.4 or later)**
- Main pipeline: `terra`, `sf`, `dplyr`, `lubridate`, `stringr`, `here`, `readxl`, `raster`, `ncdf4`, `ggplot2`, `tidyterra`, `rnaturalearth`.
- `Spatial_map_options/` also needs `mgcv`, `rpart`, `geodata`, `osmextract` and `tibble`.

**Python (3.12)**
- `numpy`, `pandas`, `scipy`, `rasterio` (`bottleneck` is optional and makes it faster).
- `Dispersal_calibration/` also needs `pyabc` and `matplotlib`.

**Other**
- SLURM, for the calibration and simulation jobs. The submission scripts in `scripts/shell/` are set up for DRAGO (CSIC). On another cluster, update the partitions (`#SBATCH -p`) and the `module load` lines.
- [Quarto](https://quarto.org/), to render the results report.

## Input data

The `data/` folder is not included in the repository. All paths below are relative to the repository root, and all maps are on the same 500 m grid (ETRS89 / LAEA Europe, EPSG:3035; 2454 × 1965 cells).

### Rabbit density

Lynx breeding habitat is derived each year from simulated monthly rabbit densities (**Evers et al., in prep.**). The rabbit model output goes in:

```
data/Rabbit_output/NC_simulation_Complete_<scenario>/<line>/
```

- `<scenario>` is `historic`, `ssp245` or `ssp585`, and `<line>` is one folder per rabbit simulation (e.g. `line12`).
- **Files:** each folder holds monthly rabbit density grids as CSV files. Each file is a grid of 1965 rows × 2454 columns with no header, and its name contains the date as `YYYY_M`.
- **Lynx year:** a model year runs from June to May, and only years with all 12 months are used.
- **Breeding habitat:** a cell counts as breeding habitat when the density is at or above the threshold in at least *n* months. Both values are calibrated. `scripts/r/Create_breeding_maps.R` makes these maps and writes them to `data/model_input/maps/`; the pipeline runs it automatically.

### Model input (`data/model_input/`)

| File | Content | Created by |
|---|---|---|
| `past_calibration_settings_IPMcorrected.txt` | Settings for calibration and historic simulations (2006–2024) | written by hand |
| `future_simulation_settings_IPMcorrected.txt` | Settings for future simulations (2022–2050) | written by hand |
| `Lynx_demography_values_correctedIPM.txt` | Demographic and dispersal parameters | written by hand; survival and litter size from an IPM [TODO: reference], dispersal parameters from `Dispersal_calibration/` |
| `Lynx_start_pops_2005.txt`, `Lynx_start_pops_2022.txt` | Starting population sizes and locations | `scripts/r/Data_preparation.R` |
| `Lynx_reintroductions.txt` | Released individuals (year, location, sex, age) | `scripts/r/Data_preparation.R` |
| `maps/Lynx_HabitatMap_500_Peninsula_Revilla_2015_1.txt` | Dispersal habitat: 0 barrier, 1 matrix, 2 dispersal habitat | `scripts/r/Data_preparation.R` |
| `maps/Lynx_BreedingHabitat_500_Peninsula_Fordham_2013.txt` | Breeding habitat on land cover alone (0/1) | `scripts/r/Data_preparation.R` |
| `maps/Lynx_populations_2022_buffered.txt` | Population IDs, used to report sizes per population | `scripts/r/Data_preparation.R` |

### Original data (`data/original_data/` and `data/GIS_maps/`)

| File(s) | Used for | Source |
|---|---|---|
| `original_data/U2018_CLC2018_V2020_20u1.tif` | Template grid; Revilla and Fordham habitat maps | CORINE Land Cover 2018 (v2020_20u1), Copernicus Land Monitoring Service: https://land.copernicus.eu/en/products/corine-land-cover/clc2018 |
| — | Reclassification of CORINE into dispersal habitat | Revilla et al. (2015) [TODO: full reference] |
| — | Reclassification of CORINE into breeding habitat | Fordham, D. A. et al. (2013) Adapted conservation measures are required to save the Iberian lynx in a changing climate. *Nature Climate Change* 3, 899–903. https://doi.org/10.1038/nclimate1954 |
| `original_data/20250825_data_German/Presencias/` | Observed lynx presence (calibration, population map, start locations) | [TODO: source, e.g. LIFE LynxConnect census data, provided by ...] |
| `original_data/Annual_distribution_Alejandro/` | Observed annual distribution 2002–2018 (calibration) | [TODO: source] |
| `original_data/2025.08.06_LynxConnectWebsiteCensusNumber.csv` / `.xlsx` | Observed population sizes (calibration, start populations) | LIFE LynxConnect census figures, downloaded 6 August 2025 [TODO: URL] |
| `original_data/Alejandro_information/250623 Lynx age at the time of release.xlsx` | Reintroductions | [TODO: source] |
| `original_data/Population_sizes_IUCN.csv` | Observed population sizes (report figures) | [TODO: IUCN reference] |
| `original_data/grwl_data/` | Rivers wider than 5 m (breeding habitat option) | Allen, G. H. & Pavelsky, T. M. (2018) Global extent of rivers and streams. *Science* 361, 585–588. https://doi.org/10.1126/science.aat0636. Data: https://doi.org/10.5281/zenodo.1297434 (downloaded automatically) |
| `GIS_maps/manual_populations_drawn.shp` | Biological populations (polygons drawn by hand) | created for this project |

The following are used only by `Spatial_map_options/` and `Dispersal_calibration/`:

| File(s) | Used for | Source |
|---|---|---|
| `original_data/Lynx_movement_resistance_maps_Pablo_Cisneros/capas/` | Dispersal resistance and habitat selection surfaces | Cisneros-Araujo et al. [TODO: full reference] |
| `original_data/GPS_dispersal_data_Iberian_lynx_Cisneros-Araujo.csv` | Observed daily dispersal steps | Cisneros-Araujo et al. [TODO: full reference] |
| `original_data/LUC_historic_landcover/`, `original_data/LUC_future_landcover/` | Land cover 2015 and 2016–2100 (SSP2-4.5, SSP5-8.5) | LUCAS LUC v1.1: Hoffmann, P. et al. (2023) High-resolution land use and land cover dataset for regional climate modelling: historical and future changes in Europe. *Earth System Science Data* 15, 3819–3852. https://doi.org/10.5194/essd-15-3819-2023 |
| `original_data/Copernicus_GLO90_Europe_250m.tif` | Elevation | Copernicus DEM GLO-90, https://doi.org/10.5270/ESA-c5d3d65 |
| `original_data/OSM_road_density.tif` | Road density | © OpenStreetMap contributors (ODbL), downloaded automatically through Geofabrik with `osmextract` |
| — | Mainland Spain/Portugal mask | GADM (https://gadm.org), downloaded automatically with `geodata` |

## Running the simulations

All commands are run from the repository root.

### 1. Prepare the input data

```
Rscript scripts/r/Data_preparation.R
```

This creates the template grid, the habitat, breeding and population maps, the observed presence maps used for calibration (`data/GIS_maps/presence_vectors/`), the start populations and the reintroduction file. You only need to run it again when the original data change.

### 2. Run the pipeline

Open `scripts/Run_pipeline.R`, check the settings at the top, then run:

```
Rscript scripts/Run_pipeline.R
```

Each step waits for its SLURM jobs to finish, so keep the session open (e.g. in `screen` or `tmux`). The steps are:

1. **Data preparation** (optional, `run_data_preparation`): runs step 1 above.
2. **Calibration**: for each rabbit line, runs the model for every combination of rabbit density threshold, number of months above the threshold, and territory size (`Tsize`). Each run is scored against the observed presence (Matthews correlation coefficient) and population sizes (RMSE). Output goes to `results/calibration/`.
3. **Calibration comparison**: combines the scores and gives each parameter combination a weight. Output: `results/calibration_summary_RCorrected.csv`.
4. **Simulations**: for each scenario (`historic`, `ssp245`), draws `samples` parameter sets according to their weights and a random rabbit line for each. It creates any missing breeding maps, runs the model, and summarises the runs. Output goes to `results/simulation_runs/<scenario>/`:
   - `summary/`: all runs' CSV output combined
   - `summary_maps/`: occupancy probability and mean movement maps

To run only the simulations with an existing calibration, set `run_calibration` and `run_comparison` to `FALSE` and place the calibration summary in `results/calibration_summary_RCorrected.csv`.

### 3. Results report

Copy `results/simulation_runs/` to your local machine and render the report:

```
quarto render Manuscript/PVA-result-report.qmd
```

### Running a single simulation

```
Program/Executables/Run_model_debug <settings_file> <output_dir> [Tsize] [prey_folder] [breeding_folder]
```

- `prey_folder` is a folder of yearly breeding maps from rabbit density (`Lynx_PreyMap_<year>.txt`).
- The optional arguments override the values in the settings and demography files.

For example:

```
Program/Executables/Run_model_debug data/model_input/past_calibration_settings_IPMcorrected.txt test_run 20 data/model_input/maps/historic/threshold_6_months_9/line12
```

## Model settings and outputs

**Settings file keys**

| Key | Meaning |
|---|---|
| `start_year`, `end_year` | Simulated period |
| `create_maps`, `create_maps_25yrs`, `all_year_maps` | Which yearly maps to write (0/1) |
| `track_pedigree` | Track the pedigree and inbreeding (0/1) |
| `lynx_demography` | Demography and dispersal parameter file |
| `mapname_lynx` | Dispersal habitat map |
| `breeding_file` | Breeding habitat map |
| `prey_file` | Fixed prey (rabbit) breeding map; `0` when rabbit maps are given on the command line |
| `map_lynx_pops` | Population ID map |
| `lynx_start_size` | Starting populations |
| `lynx_reintro` | Reintroductions |
| `habitat_folder`, `breeding_folder`, `prey_folder` | Folders with yearly maps (`Lynx_HabitatMap_<year>.txt`, `Lynx_BreedingMap_<year>.txt`, `Lynx_PreyMap_<year>.txt`); `0` to use the fixed map instead |

**Output per run**
- `lynx_pop_size.csv`: population size per population per year.
- `lynx_biopop_size.csv`: population size per biological population per year.
- `lynx_migration.csv` and `lynx_migration_settled.csv`: movements between populations.
- `lynx_reproduction_outside_populations.csv`: reproduction events outside known populations.
- `lynx_pop_IC.csv` and `lynx_biopop_IC.csv`: inbreeding (only when `track_pedigree 1`).
- `maps/`: female and male territory maps per year and maps of cells traveled.

## Additional workflows

- **`Spatial_map_options/`** creates the historical habitat and breeding habitat maps for each spatial method (Revilla 1 and 2, Fordham, PCA dispersal, PCA habitat, land cover prediction), for comparison. It also contains functions to project the model-based maps onto future land cover (SSP2-4.5, SSP5-8.5). Run it with `Rscript Spatial_map_options/Spatial_option_pipeline.R`.
- **`Dispersal_calibration/`** estimates the dispersal parameters with ABC, by comparing one simulated day of dispersal with GPS data. It uses `Program/Executables/dispersal_calibration`. Run it with `Rscript Dispersal_calibration/Dispersal_calibration_pipeline.R`. The estimated parameters must be copied into the demography file by hand.

## Troubleshooting

- **`[project] cannot get output boundaries for the target crs` / `PROJ: proj_create: no database context specified`:** another program (e.g. PostgreSQL/PostGIS) has set `PROJ_LIB` or `GDAL_DATA` system-wide, and terra is using the wrong PROJ database. Remove these variables for R, e.g. with `Sys.unsetenv(c("PROJ_LIB", "GDAL_DATA"))` before loading terra, or by setting them to empty in `~/.Renviron`.
- **SLURM jobs fail immediately:** the job logs go to `job_reports/`. The pipeline creates this folder itself, but it must be run from the repository root.
