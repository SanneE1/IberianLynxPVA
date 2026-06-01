library(dplyr)
library(terra)

csvToRaster <- function(fileName, habitat_raster, return_df = T, plot = F, 
                        save_tiff = F, tiff_name = NA) {
  
  mat_status <- as.matrix(read.csv(fileName, header = F))
  
  df <- terra::rasterize(mat_status, habitat_raster)
  values(df) <- mat_status
 
  if (return_df) {
    return(df)  
  } 
  
  if (plot) {
    plot(df)
  }
  
  if(save_tiff) {
    writeRaster(df, tiff_name, overwrite = T)
  }
  
}

