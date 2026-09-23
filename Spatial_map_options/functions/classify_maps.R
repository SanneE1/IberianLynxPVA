# ----------------------------------------------------------------------------
# Turn continuous predictions into the categories the IBM uses.
#
# The cut-off values are found once, on the historical (observed) Cisneros
# surface, with a classification tree (find_*_cutoffs). The same cut-offs are
# then applied to the historical prediction and to every future year
# (apply_*_cutoffs), so the categories are comparable over time.
# apply_* functions work on single rasters and on multi-year stacks.
# ----------------------------------------------------------------------------

#----------------------------------------
# Dispersal habitat: 0 = barrier, 1 = matrix, 2 = dispersal habitat
#----------------------------------------

# Resistance values that best separate the reference categories (the Revilla map).
# Returns two cut-offs, lowest first.
find_dispersal_cutoffs <- function(observed, reference_classes) {
  df <- data.frame(value = values(observed)[, 1],
                   class = factor(values(reference_classes)[, 1], ordered = TRUE))

  tree <- rpart::rpart(class ~ value, data = df, method = "class",
                       control = rpart::rpart.control(maxdepth = 2, cp = 0, minbucket = 5))
  cutoffs <- sort(unique(tree$splits[, "index"]))[1:2]
  cat("  Dispersal cut-off values:", cutoffs, "\n")
  cutoffs
}

# Low resistance = better habitat
apply_dispersal_cutoffs <- function(predicted, cutoffs) {
  ifel(predicted < cutoffs[1], 2, ifel(predicted < cutoffs[2], 1, 0))
}

#----------------------------------------
# Breeding habitat: 1 = breeding habitat, 0 = other
#----------------------------------------

# Value that best separates cells with and without observed lynx presence.
# Only observed values below max_value are used to find it.
find_breeding_cutoff <- function(observed, presence, max_value = Inf) {
  df <- data.frame(value = values(observed)[, 1],
                   obs = factor(values(presence)[, 1]))
  df <- df[!is.na(df$value) & df$value < max_value, ]

  tree <- rpart::rpart(obs ~ value, data = df, method = "class",
                       control = rpart::rpart.control(maxdepth = 1, cp = -1, minsplit = 2, minbucket = 1))
  cutoff <- tree$splits[1, "index"]
  cat("  Breeding cut-off value:", cutoff, "\n")
  cutoff
}

# low_is_suitable = TRUE for resistance surfaces, FALSE for suitability/selection surfaces
apply_breeding_cutoff <- function(predicted, cutoff, low_is_suitable = TRUE) {
  if (low_is_suitable) ifel(predicted < cutoff, 1, 0) else ifel(predicted >= cutoff, 1, 0)
}
