args <- commandArgs(trailingOnly = TRUE)

parse_arg <- function(name, default = NULL) {
  match <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(match) == 0) return(default)
  sub(paste0("^--", name, "="), "", match[1])
}

rabbit_root <- parse_arg("rabbit-root", "data/Rabbit_output")
output_root <- parse_arg("output-root", "data/model_input/maps")

thresholds <- c(3, 6, 9, 12)
n_months <- c(6, 9, 12)
task_id <- as.integer(parse_arg("task-id", NA))
dry_run <- any(grepl("^--dry-run$", args))

source(file.path("scripts", "r", "Create_breeding_maps.R"))

if (!dir.exists(rabbit_root)) {
  stop("Rabbit output root does not exist: ", rabbit_root)
}

scenario_dirs <- list.dirs(rabbit_root, recursive = FALSE, full.names = TRUE)
if (length(scenario_dirs) == 0) {
  stop("No scenario directories found under ", rabbit_root)
}

normalize_scenario <- function(path) {
  name <- basename(path)
  name <- sub("^NC_simulation_Complete_", "", name)
  name <- tolower(name)
  return(name)
}

build_task_list <- function() {
  tasks <- data.frame(
    scenario = character(),
    scenario_dir = character(),
    replicate_name = character(),
    replicate_dir = character(),
    threshold = integer(),
    n_months = integer(),
    stringsAsFactors = FALSE
  )

  for (scenario_dir in scenario_dirs) {
    scenario <- normalize_scenario(scenario_dir)
    replicate_dirs <- list.dirs(scenario_dir, recursive = FALSE, full.names = TRUE)

    if (length(replicate_dirs) == 0) {
      warning("Skipping scenario with no replicates: ", scenario_dir)
      next
    }

    for (rep_dir in replicate_dirs) {
      replicate_name <- basename(rep_dir)

      for (t in thresholds) {
        for (n in n_months) {
          tasks <- rbind(tasks, data.frame(
            scenario = scenario,
            scenario_dir = scenario_dir,
            replicate_name = replicate_name,
            replicate_dir = rep_dir,
            threshold = t,
            n_months = n,
            stringsAsFactors = FALSE
          ))
        }
      }
    }
  }

  return(tasks)
}

tasks <- build_task_list()
if (nrow(tasks) == 0) {
  stop("No breeding map tasks could be generated.")
}

if (!is.na(task_id)) {
  if (task_id < 1 || task_id > nrow(tasks)) {
    stop("Invalid task-id ", task_id, ", expected 1-", nrow(tasks))
  }
  tasks <- tasks[task_id, , drop = FALSE]
}

for (task_index in seq_len(nrow(tasks))) {
  task <- tasks[task_index, ]

  param_dir <- paste0("threshold_", task$threshold, "_months_", task$n_months)
  output_dir <- file.path(output_root, task$scenario, param_dir, task$replicate_name)

  if (dry_run) {
    cat("DRY RUN: task", ifelse(is.na(task_id), task_index, task_id), "/", nrow(tasks), ": ", task$scenario, task$replicate_name, "->", output_dir, "\n")
    next
  }

  if (!dir.exists(dirname(output_dir))) {
    dir.create(dirname(output_dir), recursive = TRUE)
  }

  if (dir.exists(output_dir)) {
    message("Skipping existing output folder: ", output_dir)
    next
  }

  message("Creating breeding maps for scenario=", task$scenario,
          ", replicate=", task$replicate_name,
          ", threshold=", task$threshold,
          ", n_months=", task$n_months)

  asc_dir <- tempfile(pattern = "breeding_asc_")
  safe_output_dir <- tryCatch({
    Create_breeding_maps(rabbit_folder = task$replicate_dir,
                         density_threshold = task$threshold,
                         n_months = task$n_months,
                         asc_dir = asc_dir,
                         output_dir = output_dir,
                         keep_asc = FALSE)
  }, error = function(e) {
    warning("Failed creating breeding maps for ", task$replicate_dir, ": ", e$message)
    return(NULL)
  })

  if (!is.null(safe_output_dir) && dir.exists(safe_output_dir)) {
    manifest_file <- file.path(safe_output_dir, "manifest.txt")
    cat(
      paste0("scenario: ", task$scenario), "\n",
      paste0("replicate: ", task$replicate_name), "\n",
      paste0("rabbit_folder: ", normalizePath(task$replicate_dir, winslash = "/", mustWork = FALSE)), "\n",
      paste0("threshold: ", task$threshold), "\n",
      paste0("n_months: ", task$n_months), "\n",
      paste0("output_dir: ", normalizePath(safe_output_dir, winslash = "/", mustWork = FALSE)), "\n",
      paste0("created_at: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
      file = manifest_file,
      sep = "\n"
    )
  }
}
