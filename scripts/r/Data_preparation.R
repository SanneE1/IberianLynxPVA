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
template <- ifel(template < 40, 1, NA)

writeRaster(template, "data/GIS_maps/Peninsula_500_template.tif", 
            datatype = "INT2S", overwrite = TRUE, NAflag = -9999)


# --------------------------------------
# DISPERSAL HABITAT MAP
# --------------------------------------

# Use dispersal resistance surface from Cisneros-araujo to
# 1) projected the dispersal resistance into the future using landcover change
# 2) classify all dispersal resistance surfaces into the 3 habitat categories 
#    required for the IBM 
source("scripts/r/PCA_dispersal.R")

# --------------------------------------
# BREEDING HABITAT
# --------------------------------------


# Use habitat selection (while in territory) surface from Cisneros-araujo to
# 1) projected the habitat selection into the future using landcover change
# 2) classify all surfaces into the 3 habitat categories required for the IBM 
source("scripts/r/PCA_habitat.R")

# Format map(s) for additional breeding habitat requirements 
# 1) rivers
source("scripts/r/Format_breeding_habitat.R")

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
writeVector(result,  file.path(output_folder, "Lynx_populations_2022_buffered_vector.shp"), overwrite = TRUE)
writeRaster(pops_rast, file.path(output_folder, "Lynx_populations_2022_buffered.asc"), datatype = "INT2S", overwrite = TRUE)
writeRaster(pops_rast, file.path(output_folder, "Lynx_populations_2022_buffered.tif"), datatype = "INT2S", overwrite = TRUE)

# ----------------------------------------------------------------------------
# POPULATION MAPS
# ----------------------------------------------------------------------------

if(!exists("pops_lookup")){pops_lookup <- read.csv("data/pop_id_lookup.csv")}

if(!exists("result")){
  presence_buffered <- vect(file.path(output_folder, "Lynx_populations_2022_buffered_vector.shp"))
} else {
  presence_buffered <- result
}

obsAlejandro <- list.files("data/original_data/Annual_distribution_Alejandro/", pattern = ".shp", full.names = T)
obsAlejandro <- lapply(obsAlejandro, function(x) project(vect(x), crs(template)))
names(obsAlejandro) <- c(2002:2018)

obsConnect <- list.files("data/original_data/20250825_data_German/Presencias/", pattern = ".shp$", recursive = T, full.names = T)
obsConnect <- lapply(obsConnect, function(x) project(vect(x), crs(template)))
names(obsConnect) <- c(2015,2017,2020:2022, 2002:2014, 2021)


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
    warning("No overlap found for: ", f)
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
              filename = file.path("data/GIS_maps/presence_vectors/", paste0(names(merged_obs)[i], ".shp")),
              overwrite = T)
  
}

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



# ----------------------------------------------------------------------------
# Change ASC files to txt model input
# ----------------------------------------------------------------------------







