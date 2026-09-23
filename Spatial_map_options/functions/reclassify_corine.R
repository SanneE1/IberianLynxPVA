# ----------------------------------------------------------------------------
# Habitat (Revilla 2015) and breeding habitat (Fordham 2013) maps, made by
# reclassifying CORINE land cover classes and resampling to 500 m (majority).
# ----------------------------------------------------------------------------

# Revilla 2015 habitat categories: 0 = barrier, 1 = matrix, 2 = dispersal habitat
# option 1 and 2 differ only in the class of CORINE code 22 (agro-forestry)
reclassify_revilla <- function(corine, grid, option = 1) {
  if (option == 1) {
    new <- c(rep(0,9), rep(1,13),2,2,2,1,2,2,2,rep(1,4),0,0,1, rep(0,9))
  } else {
    new <- c(rep(0,9), rep(1,12),2,2,2,2,1,2,2,2,rep(1,4),0,0,1, rep(0,9))
  }
  reclass <- as.matrix(data.frame(old = c(1:44, 48), new = new))

  resample(classify(corine, reclass), grid, method = "mode")
}

# Fordham 2013 breeding habitat: 1 = breeding habitat (CORINE 28 and 29), 0 = other
reclassify_fordham <- function(corine, grid) {
  reclass <- as.matrix(data.frame(
    old = c(1:44, 48),
    new = c(rep(0,27), 1, 1, rep(0,16))
  ))

  resample(classify(corine, reclass), grid, method = "mode")
}
