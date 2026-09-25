---
bibliography: references.bib
---

# Iberian lynx PVA

Spatially explicit, individual-based population viability analysis (PVA) for the Iberian lynx (*Lynx pardinus*) on the Iberian Peninsula, with breeding habitat driven by simulated rabbit densities.

The model is written in Free Pascal. The data preparation, calibration and post-processing use R and Python, and the full workflow is designed to run on an HPC cluster with SLURM.

The final, full workflow will be hosted by LIFEWATCH ERIC where the full analysis can be re-run with new input data. The full reproducible workflow will also be available as an open source workflow.

## Contents

- [Repository layout](#repository-layout)
- [Requirements](#requirements)
- [Input data](#input-data)
- [Running the simulations](#running-the-simulations)
- [Model outputs](#model-outputs)
- [Additional workflows](#additional-workflows)
- [Troubleshooting](#troubleshooting)

## Repository layout {#repository-layout}

```         
scripts/
  Run_pipeline.R           Main pipeline: calibration and simulations, in order
  r/                       R scripts called by the pipeline
  python/                  Simulation batch runner and summary maps
  shell/                   SLURM submission scripts
Program/                   Pascal model source (Model_cmd.lpr, lynx/*.pas) and executables
Spatial_map_options/       Alternative habitat maps (Revilla, Fordham, PCA, land cover), historic and future
Dispersal_calibration/     ABC calibration of the dispersal parameters
data/                      Input data (not in git, see Input data)
results/                   Calibration and simulation output (not in git)
```

## Requirements {#requirements}

**Model** - [Lazarus / Free Pascal](https://www.lazarus-ide.org/) to build the model. Linux and Windows builds of `Run_model_debug` are in `Program/Executables/`. To rebuild: `lazbuild --build-mode=Debug Program/Model_cmd.lpi`

**R (4.4 or later)** - Main pipeline: `terra`, `sf`, `dplyr`, `lubridate`, `stringr`, `here`, `readxl`, `raster`, `ncdf4`, `ggplot2`, `tidyterra`, `rnaturalearth`. - `Spatial_map_options/` also needs `mgcv`, `rpart`, `geodata`, `osmextract` and `tibble`.

**Python (3.12)** - `numpy`, `pandas`, `scipy`, `rasterio` (`bottleneck` is optional and makes it faster). - `Dispersal_calibration/` also needs `pyabc` and `matplotlib`.

**Other** - SLURM, for the calibration and simulation jobs. The submission scripts in `scripts/shell/` are set up for DRAGO (CSIC). On another cluster, update the partitions (`#SBATCH -p`) and the `module load` lines. \## Input data

The `data/` folder is not included in the repository. All paths below are relative to the repository root, and all maps are on the same 500 m grid (ETRS89 / LAEA Europe, EPSG:3035; 2454 × 1965 cells).

### Rabbit density

Lynx breeding habitat is derived each year from simulated monthly rabbit densities (**Evers et al., in prep.**) and will be archived as the project matures. The rabbit model output goes in:

```         
data/Rabbit_output/NC_simulation_Complete_<scenario>/<line>/
```

- `<scenario>` is `historic`, `ssp245` or `ssp585`, and `<line>` is one folder per rabbit simulation (e.g. `line12`).
- **Files:** each folder holds monthly rabbit density grids as CSV files. Each file is a grid of 1965 rows × 2454 columns with no header, and its name contains the date as `YYYY_M`.
- **Lynx year:** a model year runs from June to May, and only years with all 12 months are used.
- **Breeding habitat:** a cell counts as breeding habitat when the density is at or above the threshold in at least *n* months. Both values are calibrated. `scripts/r/Create_breeding_maps.R` makes these maps and writes them to `data/model_input/maps/`; the pipeline runs it automatically.

### Model input (`data/model_input/`)

The model reads five kinds of input files. All are plain text, and all file paths are relative to the folder the model is run from (the repository root).

#### 1. Settings file

The settings file tells the model which period to simulate, which outputs to write and where all other input files are.

- **Format:** one setting per line, as `key value`, separated by a **single space**. There is no header.
- **Values:** no value can contain spaces, including file paths.
- **Order:** the order of the lines does not matter, and lines with an unknown key are ignored.

Example file:

```         
start_year 2006
end_year 2024
create_maps 1
create_maps_25yrs 0
all_year_maps 0
track_pedigree 0
lynx_demography data/model_input/Lynx_demography_values.txt
mapname_lynx data/model_input/maps/Lynx_HabitatMap_Revilla_2015_1.txt
breeding_file data/model_input/maps/Lynx_BreedingHabitat_Fordham_2013.txt
prey_file 0
map_lynx_pops data/model_input/maps/Lynx_populations_2022.txt
lynx_start_size data/model_input/Lynx_start_pops_2005.txt
lynx_reintro data/model_input/Lynx_reintroductions.txt
habitat_folder 0
breeding_folder 0
prey_folder data/model_input/maps/simulated_prey_suitability/
```

| Key | Value | Meaning |
|------------------------|------------------------|------------------------|
| `start_year`, `end_year` | year | First and last simulated year |
| `lynx_demography` | file | Demography and dispersal parameters (see 2) |
| `lynx_start_size` | file | Starting populations (see 3) |
| `lynx_reintro` | file | Reintroductions (see 4) |
| `mapname_lynx` | file | Fixed dispersal habitat map (see 5) |
| `breeding_file` | file | Fixed land-cover breeding habitat map |
| `prey_file` | file or `0` | Fixed prey (rabbit) breeding habitat map. Use `0` when the prey maps come from `prey_folder` or the command line |
| `map_lynx_pops` | file | Population ID map |
| `habitat_folder` | folder or `0` | Folder with a dispersal habitat map per year (`Lynx_HabitatMap_<year>.txt`). `0` = use `mapname_lynx` for every year |
| `breeding_folder` | folder or `0` | Folder with a breeding habitat map per year (`Lynx_BreedingMap_<year>.txt`). `0` = use `breeding_file` |
| `prey_folder` | folder or `0` | Folder with a prey map per year (`Lynx_PreyMap_<year>.txt`). `0` = use `prey_file` |
| `create_maps` | `1` | Write the migration files, the reproduction-outside-populations file and the maps of cells traveled (on by default) |
| `create_maps_25yrs` | `0` / `1` | Also write the territory maps every 25 years (2025, 2050, ...) |
| `all_year_maps` | `0` / `1` | Write the territory maps for every year. By default they are only written for the first year |
| `track_pedigree` | `0` / `1` | Track the pedigree and calculate inbreeding |

- **Required keys:** `habitat_folder`, `breeding_folder` and `prey_folder` must always be present, set to `0` when not used. A missing key is not treated as `0`, and the model will then fail to find the maps.
- **Prey maps on the command line:** the pipeline gives the prey folder as a command-line argument (see [Running a single simulation](#running-a-single-simulation)), which overrides `prey_folder`.
- **Switching off maps:** setting `create_maps 0` does not switch the output maps off, because the model only reads the value `1`.

#### 2. Demography file

The demography file uses the same `key value` format as the settings file.

- **Reproduction and territory:** `min_rep_age`, `max_rep_age`, `max_age`, `Tsize` (territory size in cells), `litter_size`, `litter_size_sd`, `rep_prob`, and optionally `male_T_multiplier` (male territory size relative to females).
- **Survival:**
  - There is one line per age from `surv_0` to `surv_21`, each with 6 annual survival probabilities, one per group of natal populations: other, Vale do Guadiana, Doñana, Matachel group, Sierra Morena/Andújar group, Montes de Toledo group.
  - The groups are hard-coded by population ID in `Program/lynx/lynx_vital_rates.pas`, so they must match the IDs in the population map.
  - In this workflow we tested 3 different estimates of survival.
    1.  Estimates based on life table analyses for each population (Rodriguez, pers. comm)
    2.  Estimates from a published integrated population model [@jiménez2025] in Extremadura.
    3.  Corrected rates for each population, based on the relative differences in the Extremadura population between 1. and 2.
- **Dispersal:** `surv_disp_rho`, `alpha_steps`, `theta_d`, `theta_delta`, `delta_theta_long`, `delta_theta_f`, `L`, `N_d`, `beta`, `gamma`, `n_cycles`.
- **Inbreeding** (only with `track_pedigree 1`): `IC_eff_surv`, `IC_eff_rep`, `IC_eff_kittens`.

`Tsize` is estimated during the calibration in this pipeline.

#### 3. Start populations

The start-population file has one population per line, space separated, with a header line starting with `N`:

```         
N X Y pop
56 1021 1417 Andújar-Cardeña
28 565 1542 Doñana-Aljarafe
```

- `N`: number of individuals. Each is given a random sex and an age of 3–5 years.
- `X` and `Y`: the column and row of the starting cell on the model grid (starting at 1).
- `pop`: a label only, not used by the model.

#### 4. Reintroductions

The reintroduction file has one released individual per line, space separated, with the header `Year X Y Sex Age`. `Sex` is `f` or `m`, and `X`/`Y` are the column and row of the release cell. Releases are only read for 2009–2024; this is set in `Program/population_dynamics.pas`.

#### 5. Maps

All maps are integer grids on the model grid (2454 × 1965 cells).

- **Format:** the first line is `ncols nrows`, followed by one line per row of space-separated values.
- **Source:** this is an ESRI ASCII grid (`.asc`) with its 6-line header replaced by `ncols nrows`. `transform_asc_file()` in `scripts/r/transform_asc_to_input_maps.R` does this conversion.
- **No data:** negative values (e.g. `-9999`) mean no data.

| Map | Values |
|------------------------------------|------------------------------------|
| Dispersal habitat (`mapname_lynx`, `Lynx_HabitatMap_<year>`) | `0` barrier (cannot be entered), `1` matrix, `2` dispersal/breeding habitat |
| Breeding habitat (`breeding_file`, `Lynx_BreedingMap_<year>`) | `1` suitable for territories based on land cover, `0` not |
| Prey (`prey_file`, `Lynx_PreyMap_<year>`) | `1` enough rabbits for breeding that year, `0` not |
| Populations (`map_lynx_pops`) | Population ID, `0` outside populations |

A cell can only be part of a breeding territory when breeding habitat = `1` and prey = `1`.

### Original data (`data/original_data/` and `data/GIS_maps/`)

| File(s) | Used for | Source |
|------------------------|------------------------|------------------------|
| `original_data/U2018_CLC2018_V2020_20u1.tif` | Template grid; Revilla and Fordham habitat maps | CORINE Land Cover 2018 (v2020_20u1), Copernicus Land Monitoring Service: <https://land.copernicus.eu/en/products/corine-land-cover/clc2018> |
| `original_data/20250825_data_German/Presencias/` | Observed lynx presence (calibration, population map, start locations) | $$TODO: source, e.g. LIFE LynxConnect census data, provided by ...$$ |
| `original_data/Annual_distribution_Alejandro/` | Observed annual distribution 2002–2018 (calibration) | $$TODO: source$$ |
| `original_data/2025.08.06_LynxConnectWebsiteCensusNumber.csv` / `.xlsx` | Observed population sizes (calibration, start populations) | LIFE LynxConnect census figures, downloaded 6 August 2025 $$TODO: URL$$ |
| `original_data/Alejandro_information/250623 Lynx age at the time of release.xlsx` | Reintroductions | $$TODO: source$$ |
| `original_data/Population_sizes_IUCN.csv` | Observed population sizes (report figures) | $$TODO: IUCN reference$$ |
| `original_data/grwl_data/` | Rivers wider than 5 m (breeding habitat option) | Allen, G. H. & Pavelsky, T. M. (2018) Global extent of rivers and streams. *Science* 361, 585–588. <https://doi.org/10.1126/science.aat0636>. Data: <https://doi.org/10.5281/zenodo.1297434> (downloaded automatically) |
| `GIS_maps/manual_populations_drawn.shp` | Biological populations (polygons drawn by hand) | created for this project |

## Running the simulations {#running-the-simulations}

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

1.  **Data preparation** (optional, `run_data_preparation`): runs step 1 above.
2.  **Calibration**: for each rabbit line, runs the model for every combination of rabbit density threshold, number of months above the threshold, and territory size (`Tsize`). Each run is scored against the observed presence (Matthews correlation coefficient) and population sizes (RMSE). Output goes to `results/calibration/`.
3.  **Calibration comparison**: combines the scores and gives each parameter combination a weight. Output: `results/calibration_summary_RCorrected.csv`.
4.  **Simulations**: for each scenario (`historic`, `ssp245`), draws `samples` parameter sets according to their weights and a random rabbit line for each. It creates any missing breeding maps, runs the model, and summarises the runs. Output goes to `results/simulation_runs/<scenario>/`:
    - `summary/`: all runs' CSV output combined
    - `summary_maps/`: occupancy probability and mean movement maps

To run only the simulations with an existing calibration, set `run_calibration` and `run_comparison` to `FALSE` and place the calibration summary in `results/calibration_summary_RCorrected.csv`.

### 3. Results report

Copy `results/simulation_runs/` to your local machine and render the report:

```         
quarto render Manuscript/PVA-result-report.qmd
```

### Running a single simulation {#running-a-single-simulation}

```         
Program/Executables/Run_model_debug <settings_file> <output_dir> [Tsize] [prey_folder] [breeding_folder]
```

- `prey_folder` is a folder of yearly breeding maps from rabbit density (`Lynx_PreyMap_<year>.txt`).
- The optional arguments override the values in the settings and demography files.

For example:

```         
Program/Executables/Run_model_debug data/model_input/past_calibration_settings_IPMcorrected.txt test_run 20 data/model_input/maps/historic/threshold_6_months_9/line12
```

## Model outputs {#model-outputs}

Each run writes the following to its output folder: - `lynx_pop_size.csv`: population size per population per year. - `lynx_biopop_size.csv`: population size per biological population per year. - `lynx_migration.csv` and `lynx_migration_settled.csv`: movements between populations. - `lynx_reproduction_outside_populations.csv`: reproduction events outside known populations. - `lynx_pop_IC.csv` and `lynx_biopop_IC.csv`: inbreeding (only when `track_pedigree 1`). - `maps/`: female and male territory maps per year and maps of cells traveled.

## Additional workflows {#additional-workflows}

- **`Spatial_map_options/`** creates the historical habitat and breeding habitat maps for each spatial method (Revilla 1 and 2, Fordham, PCA dispersal, PCA habitat, land cover prediction), for comparison. It also contains functions to project the model-based maps onto future land cover (SSP2-4.5, SSP5-8.5). Run it with `Rscript Spatial_map_options/Spatial_option_pipeline.R`.
- **`Dispersal_calibration/`** estimates the dispersal parameters with ABC, by comparing one simulated day of dispersal with GPS data. It uses `Program/Executables/dispersal_calibration`. Run it with `Rscript Dispersal_calibration/Dispersal_calibration_pipeline.R`. The estimated parameters must be copied into the demography file by hand.

## Troubleshooting {#troubleshooting}

- **`[project] cannot get output boundaries for the target crs` / `PROJ: proj_create: no database context specified`:** another program (e.g. PostgreSQL/PostGIS) has set `PROJ_LIB` or `GDAL_DATA` system-wide, and terra is using the wrong PROJ database. Remove these variables for R, e.g. with `Sys.unsetenv(c("PROJ_LIB", "GDAL_DATA"))` before loading terra, or by setting them to empty in `~/.Renviron`.
- **SLURM jobs fail immediately:** the job logs go to `job_reports/`. The pipeline creates this folder itself, but it must be run from the repository root.