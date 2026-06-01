library(dplyr)
library(terra)
library(ggplot2)
library(tidyterra)

obsAlejandro <- list.files("data/original_data/Annual_distribution_Alejandro/", pattern = ".shp", full.names = T)
names(obsAlejandro) <- c(2002:2018)
obsAlejandro <- lapply(obsAlejandro, vect)

obsConnect <- list.files("data/original_data/20250825_data_German/Presencias/", pattern = ".shp$", recursive = T, full.names = T)
names(obsConnect) <- c(2015,2017,2020:2022, 2002:2014, 2021)
obsConnect <- lapply(obsConnect, vect)


for(i in intersect(names(obsAlejandro), names(obsConnect))){
print(ggplot() +
  geom_spatvector(data = obsAlejandro[[i]], colour = "red", fill = "red") +
  geom_spatvector(data = obsConnect[[i]], colour = "blue", fill = "blue", alpha = 0.5) +
  ggtitle(i)
  )
}


merged_obs <- lapply(intersect(names(obsAlejandro), names(obsConnect)), function(x) {
  rbind(obsAlejandro[[x]], obsConnect[[x]])
})
names(merged_obs) <- intersect(names(obsAlejandro), names(obsConnect))

merged_obs <- c(merged_obs, obsAlejandro[setdiff(names(obsAlejandro), names(obsConnect))], obsConnect[setdiff(names(obsConnect), names(obsAlejandro))])
merged_obs <- merged_obs[sort(names(merged_obs))]


dir.create("data/GIS_maps/presence_vectors/", showWarnings = FALSE)

for (i in seq_along(merged_obs)) {
  writeVector(
    merged_obs[[i]],
    filename = file.path("data/GIS_maps/presence_vectors/", paste0(names(merged_obs)[i], ".shp")),
    overwrite = TRUE
  )
}
