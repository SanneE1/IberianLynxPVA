library(tidyverse)
library(terra)
library(tidyterra)


COR <- rast("data/GIS_maps/Lynx_HabitatMap_500_Peninsula_Revilla_2015_1.asc")

disp <- rast("data/original_data/Lynx_movement_resistance_maps_Pablo_Cisneros/capas/res_lince_w_2025.tif")
disp <- project(disp, crs(COR))
disp <- resample(disp, COR, method = "bilinear") 

df <- data.frame(
  dis_res = values(disp),
  corine = as.factor(values(COR))
) %>% 
  rename(disp_res = res_lince_w_2025) %>%
  na.omit()

# FORD <- rast("data/GIS_maps/Lynx_BreedingHabitat_500_Peninsula_Fordham_2013.asc")
# hab <- rast("data/original_data/Lynx_movement_resistance_maps_Pablo_Cisneros/capas/habitat_lince_PI_2025.tif")
# hab <- project(hab, crs(COR))
# hab <- resample(hab, COR, method = "bilinear") 
# df1 <- data.frame(
#   hab_res = values(hab),
#   corine = as.factor(values(COR))
# ) %>% 
#   rename(hab_res = habitat_lince_PI_2025) %>%
#   na.omit()


#--------------------------------
# Trial-and-error but fast
#--------------------------------

library(rpart)
library(rpart.plot)

tree <- rpart(corine ~ disp_res, data = df,
              method = "class",
              control = rpart.control(cp = 0.001))
rpart.plot(tree, type = 2, extra = 104)

# Extract the actual threshold values
tree$splits 

## Splits if we only use dispersal resistance
# disp >= 37       -> 0
# 37 > disp >= 3.5 -> 1
# dips < 3.5       -> 2

disp_class <- ifel(disp >= 37, 0, ifel(disp >= 3.5, 1, 2)) 
plot(disp_class)


# ----------------------------------------------------------------------------
# Transform projected dispersal resistance to categories for model
# ----------------------------------------------------------------------------

disp_for <- rast(file.path("data", "GIS_maps", "resistance_LUCAS_scaling", "projected_stack.tiff"))

ggplot() +
  geom_spatraster(data = disp_for$`2016`) + 
  scale_fill_viridis_c(transform = "sqrt",
                       limits   = c(0, 100),
                       oob      = scales::squish)


for (n in names(disp_for)[c(17:85)]) {
  p <- ifel(disp_for[[n]] >= 37, 0, ifel(disp_for[[n]] >= 3.5, 1, 2))
  writeRaster(p, file.path("data", "GIS_maps", "dispersal_projected", paste("Lynx_HabitatMap_", n, ".asc")),
              overwrite = T)

}











# Statistical
# 
# library(partykit)
# 
# treeB <- ctree(
#   corine ~ disp_res,
#   data = df,
#   control = ctree_control(mincriterion = 0.95)  # adjust if needed
# )
# 
# get_thresholds <- function(tree) {
#   splits <- nodeapply(tree, ids = nodeids(tree), function(node) {
#     if (is.terminal(node)) {
#       node$split$breaks
#     }
#   })
#   
#   # Clean result
#   thresholds <- sort(unique(unlist(splits)))
#   return(thresholds)
# }
# 
# thresholds <- get_thresholds(treeB)
# thresholds
