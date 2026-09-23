# ----------------------------------------------------------------------------
# Settings file read by Program/Executables/dispersal_calibration
# (paths are relative to the repository root)
# ----------------------------------------------------------------------------

write_dispersal_settings <- function(settings_file, demography_file, habitat_map,
                                     breeding_map, starting_file, n_rows, n_repeats) {
  writeLines(c(paste("lynx_demography", demography_file),
               paste("mapname_lynx", habitat_map),
               paste("breeding_file", breeding_map),
               paste("starting_coordinates", starting_file),
               paste("nrow_file", n_rows),
               paste("N_repeats", n_repeats)),
             settings_file)
}
