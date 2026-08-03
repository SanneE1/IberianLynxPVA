library(raster)
library(ncdf4)
library(terra)
library(dplyr)

# paths
corine_raster_path <- "data/original_data/U2018_CLC2018_V2020_20u1.tif"  # Replace with the path to your CORINE raster
output_folder = "data/GIS_maps/"

corine_raster <- rast(corine_raster_path)

# Define the boundaries and crop the CORINE to size
peninsula <- crop(corine_raster, ext(2574200, 3801100, 1515200, 2497800))

# Create template rasters with 500m resolution
peninsula_template <- rast(
  xmin = xmin(peninsula), 
  xmax = xmax(peninsula),
  ymin = ymin(peninsula), 
  ymax = ymax(peninsula),
  resolution = c(500, 500),
  crs = crs(peninsula)
)

template <- resample(peninsula, peninsula_template)
template <- ifel(template < 45, 1, NA)

writeRaster(template, "data/GIS_maps/Peninsula_500_template.tif", 
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

print("Resizing to 500x500m resolution...")
# Create template rasters with 500m resolution
peninsula_template <- rast(
  xmin = xmin(reclas_peninsula1), 
  xmax = xmax(reclas_peninsula1),
  ymin = ymin(reclas_peninsula1), 
  ymax = ymax(reclas_peninsula1),
  resolution = c(500, 500),
  crs = crs(reclas_peninsula1)
)

# Resample instead of project
reproj_peninsula1 <- resample(reclas_peninsula1, peninsula_template, method = "mode")
reproj_peninsula2 <- resample(reclas_peninsula2, peninsula_template, method = "mode")

# Save raster maps as asc (easiest to change into format needed for pascal program)
writeRaster(reproj_peninsula1, file.path(output_dir, "Lynx_HabitatMap_500_Peninsula_Revilla_2015_1.asc"), datatype = "INT2S", overwrite = TRUE)
writeRaster(reproj_peninsula2, file.path(output_dir, "Lynx_HabitatMap_500_Peninsula_Revilla_2015_2.asc"), datatype = "INT2S", overwrite = TRUE)


# ----------------------------------------------------------------------------
# land cover LANDMATE 
# ----------------------------------------------------------------------------

## Historic land cover LANDMAtE ----------------------------------------------------------------------------------
print("Get the dominant category per raster cell in 2015")
LUCAS_rast <- rast("data/original_data/LUC_historic_landcover/LUCAS_LUC_v1.1_historical_Europe_0.1deg_2010_2015.nc")
LUCAS_rast <- LUCAS_rast[[c(81:96)]]

writeRaster(LUCAS_rast, "data/original_data/LUC_historic_landcover/LUCAS_LUC_2015.nc", 
            datatype = "INT2S", overwrite = TRUE, NAflag = -9999)

LUCAS_rast <- project(LUCAS_rast, crs(peninsula_template))

barrier <- sum(LUCAS_rast[[c(12, 15)]])
matrix <- sum(LUCAS_rast[[c(9:11, 13, 14, 16)]])
dispersal <- sum(LUCAS_rast[[c(1:8)]])

new_cat <- c(barrier, matrix, dispersal)
names(new_cat) <- c(0:2)
new_cat <- resample(new_cat, peninsula_template, method = "mode") 

new_cat <- which.max(new_cat)

writeRaster(new_cat, file.path(output_dir, "Lynx_HabitatMap_LUCAS_2015.asc"), 
            datatype = "INT2S", overwrite = TRUE, NAflag = -9999)


## Future land cover LANDMAtE ----------------------------------------------------------------------------------

landmade_raster_files = list.files("data/original_data/LUC_future_landcover/", full.names = T)

#go through all files
for (file in landmade_raster_files) {
  
  print(file)
  # get scenario
  model <- regmatches(file, regexpr("ssp[[:alnum:]]+", file))
  
  # Load nc file
  full_rast <- rast(file)
  full_rast <- project(full_rast, crs(peninsula_template))
  full_rast <-  resample(full_rast, peninsula_template, method = "mode")
  
  dates <- unique(time(full_rast))
  years <- format(dates, "%Y")
  
  for(i in c(1:length(dates))){
    
    yearly_rast <- subset(full_rast, time(full_rast) == dates[i])
    barrier <- sum(yearly_rast[[c(12, 15)]])
    matrix <- sum(yearly_rast[[c(9:11, 13, 14, 16)]])
    dispersal <- sum(yearly_rast[[c(1:8)]])
    
    yearly_rast <- c(barrier, matrix, dispersal)
    names(yearly_rast) <- c(0:2)
    
    yearly_rast <- which.max(yearly_rast)
    
    if(!dir.exists(file.path(output_folder, "landmate", model))){
      dir.create(file.path(output_folder, "landmate", model), recursive = T)
    }
    
    writeRaster(yearly_rast, file.path(output_folder, "landmate", model, paste0("Lynx_HabitatMap_", years[i], ".asc")), 
                datatype = "INT2S", overwrite = TRUE, NAflag = 0)
    
  }
}




# --------------------------------------
# BREEDING HABITAT
# --------------------------------------

# Reclassification table --- Based on Revilla 2015 (both options)
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
writeRaster(reproj_peninsulaF, file.path(output_dir, "Lynx_BreedingHabitat_500_Peninsula_Fordham_2013.asc"), datatype = "INT2S", overwrite = TRUE)


# --------------------------------------
# POPULATION MAPS
# --------------------------------------

pops_vect <- vect("data/original_data/20250825_data_German/Presencias/2022_peninsula_iberica/2022_peninsula.shp")
pops_vect <- project(pops_vect, crs(peninsula_template))
pops_vect$SUBPOBLAC <- gsub("RIO SOTILLOS", "RIO SOTILLO", pops_vect$SUBPOBLAC)
pops_vect$subpop_numeric <- as.integer(as.factor(pops_vect$SUBPOBLAC))

# Keep a lookup table
pops_lookup <- data.frame(
  id    = as.integer(as.factor(pops_vect$SUBPOBLAC)),
  label = pops_vect$SUBPOBLAC
) %>% unique() %>% arrange() %>% filter(!is.na(id))

write.csv(pops_lookup, "data/pop_id_lookup.csv", row.names = F)

dissolved <- aggregate(pops_vect, by = "subpop_numeric")
buffered <- buffer(dissolved, width = 3000)  # your buffer distance in map units
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
writeRaster(pops_rast, file.path(output_dir, "Lynx_populations_2022_buffered.asc"), datatype = "INT2S", overwrite = TRUE)


# ----------------------------------------------------------------------------
# Create population starting file
# ----------------------------------------------------------------------------

pop_centroids <- terra::centroids(result)
coords <- as.data.frame(crds(pop_centroids))
coords$subpop <- result$SUBPOBLAC

pop_sizes <- readxl::read_xlsx("data/original_data/2025.08.06_LynxConnectWebsiteCensusNumber.xlsx", "Sheet2") %>%
  filter(Year == 2022) %>%
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

write.table(start_df, file = "data/model_input/Lynx_start_pops_2022.txt", sep = " ", quote = F, row.names = F)

start_df2005 <- start_df[c(1, 4),]
start_df2005$N <- c(56, 28)

write.table(start_df2005, file = "data/model_input/Lynx_start_pops_2005.txt", sep = " ", quote = F, row.names = F)


# ----------------------------------------------------------------------------
# Create reintroduction file
# ----------------------------------------------------------------------------

reintro <- readxl::read_xlsx("data/original_data/Alejandro_information/250623 Lynx age at the time of release.xlsx",
                             sheet = "Age of released lynx", skip = 5) %>%
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

write.table(reint_df, file = "data/model_input/Lynx_reintroductions.txt", sep = " ", quote = F, row.names = F)


# View(as.data.frame(result) %>% select(subpop_numeric))







