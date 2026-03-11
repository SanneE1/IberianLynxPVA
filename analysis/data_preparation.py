import os
from python.transform_asc_to_input_txt_map import process_folder
from python.get_matrix_cell_coordinates import extract_and_transform_coordinates

os.environ["R_HOME"] =  "C:\Program Files\R\R-4.5.1"  
import rpy2.robjects as robjects

# Set variables
output_dir = os.path.join("data", "GIS_maps")
txt_dir = os.path.join("data", "model_input", "maps")

robjects.r.assign("corine_raster_path", "data/original_data/U2018_CLC2018_V2020_20u1.tif")
robjects.r.assign("output_dir", output_dir)


# HABITAT CLASSIFICATION ---------------------------------------------------------------------------------------
robjects.r.source('R/Reclassify_Lynx_spatial_map.R')

# ASC TO TXT CONVERTER for maps --------------------------------------------------------------------------------
process_folder(output_dir, txt_dir)

# GET CELL CENTER COORDINATES ----------------------------------------------------------------------------------
rast_file_peninsula = os.path.join(output_dir, "Lynx_HabitatMap_500_Peninsula_Revilla_2015_1.asc")
output_peninsula = os.path.join(output_dir, "coordinates_peninsula_500_EPSG4326.txt")

extract_and_transform_coordinates(rast_file_peninsula, output_peninsula)


# GPS Dispersal data formatting --------------------------------------------------------------------------------

robjects.r.assign("hab_file", "data/GIS_maps/Lynx_HabitatMap_LUCAS_2015.asc")
robjects.r.assign("gps_file", "data/original_data/GPS_dispersal_data_Iberian_lynx_Cisneros-Araujo.csv")
robjects.r.assign("model_input_file", "data/model_input/calibration_dispersal_starting_locations.txt")
robjects.r.assign("result_dir", "results")

robjects.r.source('R/Calibration_data_dispersal.R')


# Presence/Absence maps data formatting --------------------------------------------------------------------------------
robjects.r.source('R/Format_presence_maps_for_calibration.R')




