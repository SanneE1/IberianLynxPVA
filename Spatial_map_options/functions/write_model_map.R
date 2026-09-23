# ----------------------------------------------------------------------------
# Save a map as .asc and as the .txt model input format
# (.txt = the .asc with its 6-line header replaced by "ncols nrows")
# ----------------------------------------------------------------------------

transform_asc_file <- function(input_path, output_path) {
  lines <- readLines(input_path)
  ncols <- strsplit(trimws(lines[1]), "\\s+")[[1]][2]
  nrows <- strsplit(trimws(lines[2]), "\\s+")[[1]][2]
  writeLines(c(paste(ncols, nrows), lines[-(1:6)]), output_path)
  output_path
}

# ... is passed on to writeRaster (e.g. NAflag = -9999)
write_model_map <- function(r, name, out_dir, ...) {
  asc_file <- file.path(out_dir, paste0(name, ".asc"))
  writeRaster(r, asc_file, datatype = "INT2S", overwrite = TRUE, ...)
  transform_asc_file(asc_file, file.path(out_dir, paste0(name, ".txt")))
}
