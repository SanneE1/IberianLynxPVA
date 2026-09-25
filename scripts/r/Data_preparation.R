library(raster)
library(ncdf4)
library(terra)
library(dplyr)
library(here)

source("scripts/r/transform_asc_to_input_maps.R")

#----------------------------------------
# Settings
#----------------------------------------
# Each setting is only used if the object does not exist yet, so it can be set
# beforehand (e.g. in scripts/Run_pipeline.R). The same settings are used by
# scripts/r/Format_breeding_habitat.R.

# Folders
if (!exists("gis_dir"))         gis_dir         <- "data/GIS_maps"
if (!exists("model_input_dir")) model_input_dir <- "data/model_input"
if (!exists("model_maps_dir"))  model_maps_dir  <- file.path(model_input_dir, "maps")

# Template grid (created from CORINE)
if (!exists("corine_path"))      corine_path      <- "data/original_data/U2018_CLC2018_V2020_20u1.tif"
if (!exists("peninsula_extent")) peninsula_extent <- c(2574200, 3801100, 1515200, 2497800)  # xmin, xmax, ymin, ymax (EPSG:3035)
if (!exists("cell_size"))        cell_size        <- 500   # m
if (!exists("max_land_class"))   max_land_class   <- 40    # CORINE classes below this are land (40+ = water)
if (!exists("template_file"))    template_file    <- file.path(gis_dir, "Peninsula_500_template.tif")

# Populations
if (!exists("presence_dir"))    presence_dir    <- "data/original_data/20250825_data_German/Presencias"
if (!exists("pops_file"))       pops_file       <- file.path(presence_dir, "2022_peninsula_iberica/2022_peninsula.shp")
if (!exists("pop_buffer_m"))    pop_buffer_m    <- 3000   # buffer around the observed populations
if (!exists("pop_lookup_file")) pop_lookup_file <- "data/pop_id_lookup.csv"
if (!exists("biopop_file"))     biopop_file     <- file.path(gis_dir, "manual_populations_drawn.shp")
if (!exists("biopop_buffer_m")) biopop_buffer_m <- 1000   # buffer around the biological populations

# Observed presence per year (calibration)
if (!exists("annual_distribution_dir"))   annual_distribution_dir   <- "data/original_data/Annual_distribution_Alejandro"
if (!exists("annual_distribution_years")) annual_distribution_years <- 2002:2018
# Year of each shapefile in presence_dir, in the order list.files() returns them
if (!exists("presence_years"))            presence_years            <- c(2015, 2017, 2020:2022, 2002:2014, 2021)
if (!exists("presence_vectors_dir"))      presence_vectors_dir      <- file.path(gis_dir, "presence_vectors")

# Start populations
if (!exists("census_file"))       census_file       <- "data/original_data/2025.08.06_LynxConnectWebsiteCensusNumber.xlsx"
if (!exists("census_sheet"))      census_sheet      <- "Sheet2"
if (!exists("start_census_year")) start_census_year <- 2022
if (!exists("start_2005_rows"))   start_2005_rows   <- c(1, 4)     # rows of the 2022 file present in 2005 (Andujar-Cardena, Donana)
if (!exists("start_2005_sizes"))  start_2005_sizes  <- c(56, 28)   # their population sizes in 2005
if (!exists("start_pops_file"))      start_pops_file      <- file.path(model_input_dir, "Lynx_start_pops_2022.txt")
if (!exists("start_pops_2005_file")) start_pops_2005_file <- file.path(model_input_dir, "Lynx_start_pops_2005.txt")

# Reintroductions
if (!exists("release_file"))   release_file   <- "data/original_data/Alejandro_information/250623 Lynx age at the time of release.xlsx"
if (!exists("release_sheet"))  release_sheet  <- "Age of released lynx"
if (!exists("release_skip"))   release_skip   <- 5
if (!exists("reintro_output")) reintro_output <- file.path(model_input_dir, "Lynx_reintroductions.txt")

# The lookup tables that match population names between data sets (pop_key,
# reint_key) and the coordinates of release sites outside the populations are
# further down in this script.

#----------------------------------------
# Template grid
#----------------------------------------

corine_raster <- rast(corine_path)

# Define the boundaries and crop the CORINE to size
peninsula <- crop(corine_raster, ext(peninsula_extent))

# Create template rasters with 500m resolution
peninsula_template <- rast(
  xmin = xmin(peninsula),
  xmax = xmax(peninsula),
  ymin = ymin(peninsula),
  ymax = ymax(peninsula),
  resolution = c(cell_size, cell_size),
  crs = crs(peninsula)
)

template <- resample(peninsula, peninsula_template)
template <- ifel(template < max_land_class, 1, NA)

writeRaster(template, template_file,
            datatype = "INT2S", overwrite = TRUE, NAflag = -9999)


# --------------------------------------
# HABITAT MAP
# --------------------------------------

# Reclassification table --- Based on Revilla 2015 (both options)
reclass_Rev1 <- as.matrix(data.frame(
  old = c(1:44, 48),
  new = c(rep(0,9), rep(1,13),2,2,2,1,2,2,2,rep(1,4),0,0,1, rep(0,9))
))

reclass_Rev2 <- as.matrix(data.frame(
  old = c(1:44, 48),
  new = c(rep(0,9), rep(1,12),2,2,2,2,1,2,2,2,rep(1,4),0,0,1, rep(0,9))
))

# Perform the reclassification
# Convert the reclass_table into a matrix for terra::classify
reclas_peninsula1 <- classify(peninsula, reclass_Rev1)
reclas_peninsula2 <- classify(peninsula, reclass_Rev2)

# Resample instead of project
reproj_peninsula1 <- resample(reclas_peninsula1, peninsula_template, method = "mode")
reproj_peninsula2 <- resample(reclas_peninsula2, peninsula_template, method = "mode")

# Save raster maps as asc (easiest to change into format needed for pascal program)
writeRaster(reproj_peninsula1, file.path(gis_dir, "Lynx_HabitatMap_500_Peninsula_Revilla_2015_1.asc"), datatype = "INT2S", overwrite = TRUE)
writeRaster(reproj_peninsula2, file.path(gis_dir, "Lynx_HabitatMap_500_Peninsula_Revilla_2015_2.asc"), datatype = "INT2S", overwrite = TRUE)

# --------------------------------------
# BREEDING HABITAT
# --------------------------------------

# Reclassification table --- Based on Fordham 2013
reclass_Ford <- as.matrix(data.frame(
  old = c(1:44, 48),
  new = c(rep(0,27), 1, 1, rep(0,16))
))

# Perform the reclassification
# Convert the reclass_table into a matrix for terra::classify
reclas_peninsulaF <- classify(peninsula, reclass_Ford)

# Resize to 500x500m raster size
reproj_peninsulaF <- resample(reclas_peninsulaF, peninsula_template, method = "mode")

# Save raster maps as asc (easiest to change into format needed for pascal program)
writeRaster(reproj_peninsulaF, file.path(gis_dir, "Lynx_BreedingHabitat_500_Peninsula_Fordham_2013.asc"), datatype = "INT2S", overwrite = TRUE)

# Format map(s) for additional breeding habitat requirements
# 1) rivers
source("scripts/r/Format_breeding_habitat.R", local = TRUE)

# --------------------------------------
# POPULATION MAPS
# --------------------------------------

pops_vect <- vect(pops_file)
pops_vect <- project(pops_vect, crs(peninsula_template))
pops_vect$SUBPOBLAC <- gsub("RIO SOTILLOS", "RIO SOTILLO", pops_vect$SUBPOBLAC)
pops_vect$subpop_numeric <- as.integer(as.factor(pops_vect$SUBPOBLAC))

# Keep a lookup table
pops_lookup <- data.frame(
  id    = as.integer(as.factor(pops_vect$SUBPOBLAC)),
  label = pops_vect$SUBPOBLAC
) %>% unique() %>% arrange() %>% filter(!is.na(id))

write.csv(pops_lookup, pop_lookup_file, row.names = F)

dissolved <- aggregate(pops_vect, by = "subpop_numeric")
buffered <- buffer(dissolved, width = pop_buffer_m)
contested <- intersect(buffered, buffered)
contested <- contested[contested$subpop_numeric != contested$subpop_numeric.1 ]  # keep only cross-class overlaps

classes <- unique(buffered$subpop_numeric)

result <- lapply(classes, function(cls) {
  this  <- buffered[buffered$subpop_numeric == cls, ]
  other <- buffered[buffered$subpop_numeric != cls, ]
  erase(this, other)  # remove any area that overlaps with another class
})

result <- do.call(rbind, result)

pops_rast <- terra::rasterize(result, peninsula_template, field = "subpop_numeric")
levels(pops_rast) <- pops_lookup

plot(pops_rast)
writeVector(result,  file.path(gis_dir, "Lynx_populations_2022_buffered_vector.shp"), overwrite = TRUE)
writeRaster(pops_rast, file.path(gis_dir, "Lynx_populations_2022_buffered.asc"), datatype = "INT2S", overwrite = TRUE)
writeRaster(pops_rast, file.path(gis_dir, "Lynx_populations_2022_buffered.tif"), datatype = "INT2S", overwrite = TRUE)

# Do the same for the larger, manually drawn polygons around the biological populations:
man_pop <- vect(biopop_file)
man_pop <- project(man_pop, crs(peninsula_template))
man_pop <- buffer(man_pop, width = biopop_buffer_m)
man_pop <- terra::rasterize(man_pop, peninsula_template, field = "population", background = 0)

# --------------------------------------
# CONVERT MAPS TO MODEL INPUT FORMAT
# --------------------------------------

for (m in c("Lynx_HabitatMap_500_Peninsula_Revilla_2015_1",
            "Lynx_HabitatMap_500_Peninsula_Revilla_2015_2",
            "Lynx_BreedingHabitat_500_Peninsula_Fordham_2013",
            "Lynx_populations_2022_buffered")) {
  transform_asc_file(input_path = file.path(gis_dir, paste0(m, ".asc")),
                     output_path = file.path(model_maps_dir, paste0(m, ".txt")))
}



# ----------------------------------------------------------------------------
# POPULATION MAPS
# ----------------------------------------------------------------------------

if(!exists("pops_lookup")){pops_lookup <- read.csv(pop_lookup_file)}

if(!exists("result")){
  presence_buffered <- vect(file.path(gis_dir, "Lynx_populations_2022_buffered_vector.shp"))
} else {
  presence_buffered <- result
}

obsAlejandro <- list.files(annual_distribution_dir, pattern = ".shp", full.names = T)
obsAlejandro <- lapply(obsAlejandro, function(x) project(vect(x), crs(template)))
names(obsAlejandro) <- annual_distribution_years

obsConnect <- list.files(presence_dir, pattern = ".shp$", recursive = T, full.names = T)
obsConnect <- lapply(obsConnect, function(x) project(vect(x), crs(template)))
names(obsConnect) <- presence_years


merged_obs <- lapply(intersect(names(obsAlejandro), names(obsConnect)), function(x) {
  rbind(obsAlejandro[[x]], obsConnect[[x]])
})

names(merged_obs) <- intersect(names(obsAlejandro), names(obsConnect))

merged_obs <- c(merged_obs, obsAlejandro[setdiff(names(obsAlejandro), names(obsConnect))], obsConnect[setdiff(names(obsConnect), names(obsAlejandro))])
merged_obs <- merged_obs[sort(names(merged_obs))]

for (i in seq_along(merged_obs)) {
  print(i)
  obs <- merged_obs[[i]]
  # make sure CRS matches before doing any overlay
  if (!same.crs(obs, template)) {
    warning('crs doesnt match template, skipping as you might have forgotten to match crs of either observation data sets')
    next
  }
  
  # give each feature in "obs" a unique ID to track it through the intersection
  obs$tmp_id <- seq_len(nrow(obs))
  
  obs <- makeValid(obs)
  
  # intersect obs polygons with the clean vector polygons
  inter <- intersect(obs, presence_buffered)
  
  # if there's no overlap at all, intersect() can return 0 rows -- guard for that
  if (nrow(inter) == 0) {
    warning("No overlap found for: ", names(merged_obs)[i])
    next
  }
  
  # compute area of each intersected fragment
  inter$overlap_area <- expanse(inter)
  
  # for each original polygon (tmp_id), keep the subpop_numeric with the largest overlap
  inter_df <- as.data.frame(inter)
  best_match <- inter_df[order(inter_df$tmp_id, -inter_df$overlap_area), ]
  best_match <- best_match[!duplicated(best_match$tmp_id), ]
  
  # merge the matched subpop_numeric back onto the original "obs" polygons
  subpop_col <- "subpop_num"
  
  match_lookup <- best_match[, c("tmp_id", subpop_col)]
  obs_df <- as.data.frame(obs)
  obs_df <- merge(obs_df, match_lookup, by = "tmp_id", all.x = TRUE)
  
  values(obs)[, subpop_col] <-
    obs_df[[subpop_col]][match(obs$tmp_id, obs_df$tmp_id)]
  obs <- aggregate(obs, by = subpop_col)
  
  writeVector(obs, 
              filename = file.path(presence_vectors_dir, paste0(names(merged_obs)[i], ".shp")),
              overwrite = T)
  
}

# ----------------------------------------------------------------------------
# Create population starting file
# ----------------------------------------------------------------------------

pop_centroids <- terra::centroids(result)
coords <- as.data.frame(crds(pop_centroids))
coords$subpop <- result$SUBPOBLAC

pop_sizes <- readxl::read_xlsx(census_file, census_sheet) %>%
  filter(Year == start_census_year) %>%
  rename(sizespop = Subpoblación)

pop_key <- data.frame(subpop = c("ANDUJAR_CARDENA_MONT", "Campo de Montiel", "Cornalvo", "DONANA", "GUADALMELLATO", "Guadalmez", 
                                 "GUARRIZAS", "GUAZUJEROS", "Ibores", "LAS MINAS", "Matachel", "Monfrague",
                                 "Montes de Toledo", "Ortigas", "PEGALAJAR_CONEX", "RIO SOTILLO", "SETEFILLA",
                                 "SIERRA ARANA", "Valdecañas", "Valdecigüeñas", "Vale do Guadiana"),
                      sizespop = c("Andújar-Cardeña", "Campo de Montiel", "Cornalvo", "Doñana-Aljarafe", "Guadalmellato", "Guadalmez", 
                                   "Guarrizas", "Guazurejos", "Ibores", "Las Minas", "Matachel", "Monfragüe", 
                                   "Montes de Toledo", "Ortiga", "Pegalajar", "Río Sotillo", "Setefilla",
                                   "Sierra Arana", "Valdecañas", "Valdecigüeñas", "Vale do Guadiana"))

df <- left_join(coords, pop_key)
df <- left_join(df, pop_sizes)


start_df <- data.frame(N = df$`Total ejemplares`,
                       X = colFromX(peninsula_template, x = df$x),
                       Y = rowFromY(peninsula_template, y = df$y),
                       pop = df$sizespop)

write.table(start_df, file = start_pops_file, sep = " ", quote = F, row.names = F)

start_df2005 <- start_df[start_2005_rows,]
start_df2005$N <- start_2005_sizes

write.table(start_df2005, file = start_pops_2005_file, sep = " ", quote = F, row.names = F)


# ----------------------------------------------------------------------------
# Create reintroduction file
# ----------------------------------------------------------------------------

reintro <- readxl::read_xlsx(release_file,
                             sheet = release_sheet, skip = release_skip) %>%
  mutate(Age = round(Age),
         Sex = ifelse(Sex == "Female", "f", "m")) %>%
  rename(sizespop = Cluster) %>%
  dplyr::select(sizespop, Year, Sex, Age, Population)

reint_key <- data.frame(subpop = c("ANDUJAR_CARDENA_MONT", "Campo de Montiel", "Cornalvo", "DONANA", "GUADALMELLATO", "Guadalmez", 
                                   "GUARRIZAS", "GUAZUJEROS", "Ibores", "LAS MINAS", "Matachel", "Monfrague",
                                   "Montes de Toledo", "Ortigas", "PEGALAJAR_CONEX", "RIO SOTILLO", "SETEFILLA",
                                   "SIERRA ARANA", "Valdecañas", "Valdecigüeñas", "Vale do Guadiana", "Montes de Toledo"),
                        sizespop = c("Andújar-Cardeña", "Campo de Montiel", "Cornalvo", "Doñana-Aljarafe", "Guadalmellato", "Guadalmez", 
                                     "Guarrizas", "Guazurejos", "Ibores", "Las Minas", "Matachel", "Monfragüe", 
                                     "Montes de Toledo", "Ortiga", "Pegalajar", "Río Sotillo", "Setefilla",
                                     "Sierra Arana", "Valdecañas", "Valdecigüeñas", "Vale do Guadiana", "Toledo Mountains"))

reintro <- left_join(reintro, reint_key)
reintro <- left_join(reintro, coords)

reintro[which(reintro$sizespop == "Guillena-Gerena"), c("x", "y")] <- data.frame(x = 2948657.108300277, y = 1538725.0227278136)
reintro[which(reintro$sizespop == "Vale de Perditos"), c("x", "y")] <- data.frame(x = 2900528.5508448305, y = 1764487.1617097498)
reintro[which(reintro$sizespop == "Cabañeros"), c("x", "y")] <- data.frame(x = 3074681.590008284, y = 1924957.9718479242)
reintro[which(reintro$sizespop == "La Jara"), c("x", "y")] <- data.frame(x = 3036276.113294731, y = 1981594.252867222)
reintro[which(reintro$sizespop == "Campos de Hellín"), c("x", "y")] <- data.frame(x = 3309543.4520794684, y = 1795963.4730151803)
reintro[which(reintro$sizespop == "Lorca"), c("x", "y")] <- data.frame(x = 3271312.3508618386, y = 1715273.559439425)
reintro[which(reintro$sizespop == "Sierra de San Pedro"), c("x", "y")] <- data.frame(x = 2851311.1530321133, y = 1988202.6903551097)



reint_df <- data.frame(Year = reintro$Year,
                       X = colFromX(peninsula_template, x = reintro$x),
                       Y = rowFromY(peninsula_template, y = reintro$y),
                       Sex = reintro$Sex,
                       Age = reintro$Age) %>%
  filter(complete.cases(.)) %>%
  arrange(Year)

write.table(reint_df, file = reintro_output, sep = " ", quote = F, row.names = F)


# View(as.data.frame(result) %>% select(subpop_numeric))







