#!/usr/bin/env python3
"""
Weighted simulation batch runner for Iberian Lynx PVA.

This script samples rows from results/calibration_summary_RCorrected.csv using the
weight column, randomly selects a Rabbit_output replicate for each sample, resolves
maps in data/model_input/maps, launches Program/Executables/Run_model_debug in
parallel, and performs summary aggregation.
"""

import argparse
import json
import logging
import random
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

import numpy as np
import pandas as pd


def setup_logging(log_file: Optional[Path] = None) -> logging.Logger:
    logger = logging.getLogger("run_weighted_simulation_batch")
    logger.setLevel(logging.DEBUG)

    formatter = logging.Formatter(
        "%(asctime)s %(levelname)s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)

    if log_file is not None:
        file_handler = logging.FileHandler(log_file, mode="a")
        file_handler.setLevel(logging.DEBUG)
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)

    return logger


#def get_settings_file(scenario: str, repo_root: Path) -> Path:
#    model_input = repo_root / "data" / "model_input"
#    if scenario == "historic":
#        return model_input / "past_calibration_settings_IPM.txt"
#    elif scenario in {"ssp245", "ssp585"}:
#        return model_input / "future_simulation_settings_IPM.txt"
#    raise ValueError(f"Unsupported scenario: {scenario}")

def get_settings_file(scenario: str, repo_root: Path) -> Path:
    model_input = repo_root / "data" / "model_input"
    if scenario == "historic":
        return model_input / "past_calibration_settings_IPMcorrected.txt"
    elif scenario in {"ssp245", "ssp585"}:
        return model_input / "future_simulation_settings_IPMcorrected.txt"
    raise ValueError(f"Unsupported scenario: {scenario}")


def get_settings_file_IC(scenario: str, repo_root: Path) -> Path:
    model_input = repo_root / "data" / "model_input"
    if scenario == "historic":
        return model_input / "past_calibration_settings_IPMcorrected_IC.txt"
    elif scenario in {"ssp245", "ssp585"}:
        return model_input / "future_simulation_settings_IPMcorrected_IC.txt"
    raise ValueError(f"Unsupported scenario: {scenario}")


def read_and_sample_calibration(
    calibration_csv: Path,
    sample_count: int,
    seed: int,
    logger: logging.Logger,
) -> pd.DataFrame:
    if not calibration_csv.exists():
        raise FileNotFoundError(f"Calibration CSV not found: {calibration_csv}")

    df = pd.read_csv(calibration_csv)
    logger.info(f"Loaded calibration CSV with {len(df)} rows")

    if "weight" not in df.columns:
        raise ValueError("Calibration CSV does not contain a 'weight' column")

    df_positive = df[df["weight"] > 0].copy()
    logger.info(f"Filtered to {len(df_positive)} rows with positive weight")

    if len(df_positive) == 0:
        raise ValueError("No rows with positive weights found in calibration CSV")

    weights = df_positive["weight"].values.astype(float)
    weights = weights / weights.sum()
    replace = sample_count > len(df_positive)

    rng = np.random.default_rng(seed)
    indices = rng.choice(len(df_positive), size=sample_count, replace=replace, p=weights)

    sampled = df_positive.iloc[indices].reset_index(drop=True)
    logger.info(
        f"Sampled {len(sampled)} rows from calibration CSV "
        f"(replace={replace})"
    )
    return sampled


def get_replicates_for_scenario(scenario: str, rabbit_root: Path, logger: logging.Logger) -> List[str]:
    scenario_dir = rabbit_root / f"NC_simulation_Complete_{scenario}"
    if not scenario_dir.exists():
        raise FileNotFoundError(f"Rabbit scenario root does not exist: {scenario_dir}")

    replicates = [p.name for p in scenario_dir.iterdir() if p.is_dir()]
    if not replicates:
        raise ValueError(f"No replicate folders found in {scenario_dir}")

    logger.info(f"Found {len(replicates)} replicates in {scenario_dir}")
    return sorted(replicates)


def resolve_map_folder(
    scenario: str,
    replicate: str,
    threshold: int,
    n_months: int,
    maps_root: Path,
    logger: logging.Logger,
) -> Path:
    candidates = []

    candidates.append(
        maps_root
        / scenario
        / f"threshold_{threshold}_months_{n_months}"
        / replicate
    )
    candidates.append(maps_root / f"{replicate}_{threshold}_{n_months}")
    candidates.append(maps_root / f"{replicate}_{threshold}_{n_months}_")

    for candidate in candidates:
        if candidate.exists() and candidate.is_dir():
            logger.debug(f"Resolved map folder via direct candidate: {candidate}")
            return candidate

    pattern = re.compile(
        rf"{re.escape(replicate)}.*{threshold}.*{n_months}|{threshold}.*{n_months}.*{re.escape(replicate)}",
        flags=re.IGNORECASE,
    )

    for path in maps_root.rglob("*"):
        if path.is_dir() and pattern.search(path.name):
            logger.debug(f"Resolved map folder via pattern: {path}")
            return path

    raise FileNotFoundError(
        f"Could not locate map folder for replicate={replicate}, "
        f"threshold={threshold}, n_months={n_months}"
    )


def ensure_breeding_maps(
    scenario: str,
    requirements: List[Tuple[str, int, int]],
    rabbit_root: Path,
    maps_root: Path,
    repo_root: Path,
    workers: int,
    logger: logging.Logger,
) -> None:
    """Create missing breeding maps for the sampled simulation requirements."""
    scenario_dir = rabbit_root / f"NC_simulation_Complete_{scenario}"
    missing = []
    for replicate, threshold, n_months in requirements:
        output_dir = (
            maps_root
            / scenario
            / f"threshold_{threshold}_months_{n_months}"
            / replicate
        )
        if output_dir.exists():
            if not output_dir.is_dir():
                raise NotADirectoryError(f"Map path is not a directory: {output_dir}")
            continue
        missing.append((replicate, threshold, n_months))

    if missing:
        rscript = shutil.which("Rscript")
        if rscript is None:
            raise RuntimeError(
                "Rscript is required to create missing breeding maps, but it was not found"
            )

        create_script = repo_root / "scripts" / "r" / "Create_breeding_maps.R"
        if not create_script.exists():
            raise FileNotFoundError(f"Breeding-map script not found: {create_script}")

        tasks = [
            {
                "rabbit_folder": str(scenario_dir / replicate),
                "threshold": threshold,
                "n_months": n_months,
                "output_dir": str(
                    maps_root
                    / scenario
                    / f"threshold_{threshold}_months_{n_months}"
                    / replicate
                ),
                "asc_dir": str(
                    Path("asc_temp_dir")
                    / scenario
                    / f"threshold_{threshold}_months_{n_months}"
                    / replicate
                )
            }
            for replicate, threshold, n_months in missing
        ]
        script_literal = json.dumps(str(create_script))
        logger.info("Generating %s missing breeding-map folders with %s worker(s)", len(missing), workers)

        def run_single_task(task: dict) -> str:
            r_code = (
                f"source({script_literal}); "
                "Create_breeding_maps("
                f"rabbit_folder={json.dumps(task['rabbit_folder'])}, "
                f"density_threshold={task['threshold']}, "
                f"n_months={task['n_months']}, "
                f"output_dir={json.dumps(task['output_dir'])}, "
                f"asc_dir={json.dumps(task['asc_dir'])})"
            )
            result = subprocess.run(
                [rscript, "-e", r_code],
                cwd=repo_root,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=True,
            )
            return result.stdout or ""

        try:
            with ThreadPoolExecutor(max_workers=max(1, workers)) as executor:
                futures = {executor.submit(run_single_task, task): task for task in tasks}
                for future in as_completed(futures):
                    task = futures[future]
                    try:
                        output = future.result()
                        if output:
                            logger.info(
                                "Breeding-map generation output for %s/%s:\n%s",
                                task["threshold"],
                                task["n_months"],
                                output.rstrip(),
                            )
                    except subprocess.CalledProcessError as exc:
                        logger.error(
                            "Breeding-map generation failed for %s/%s:\n%s",
                            task["threshold"],
                            task["n_months"],
                            exc.stdout or "no output",
                        )
                        raise RuntimeError(
                            "Breeding-map generation failed"
                        ) from exc
        except RuntimeError:
            raise
        except Exception as exc:
            logger.error("Breeding-map generation failed: %s", exc)
            raise RuntimeError("Breeding-map generation failed") from exc

    for replicate, threshold, n_months in requirements:
        output_dir = (
            maps_root
            / scenario
            / f"threshold_{threshold}_months_{n_months}"
            / replicate
        )
        if not output_dir.is_dir():
            raise FileNotFoundError(f"Breeding-map folder was not created: {output_dir}")
        if scenario in {"ssp245", "ssp585", "ssp245IC", "ssp585IC"}:
            year_2100 = output_dir / "Lynx_PreyMap_2100.txt"
            if not year_2100.exists():
                raise FileNotFoundError(
                    f"Future breeding maps must include 2100, but it is missing: {year_2100}"
                )


def create_output_folder(
    runs_root: Path,
    scenario: str,
    sample_index: int,
    replicate: str,
    threshold: int,
    n_months: int,
    tsize: int,
    overwrite: bool,
    logger: logging.Logger,
) -> Path:
    folder_name = (
        f"sample_{sample_index:03d}_{replicate}_t{threshold}_m{n_months}_T{tsize}"
    )
    output_folder = runs_root / scenario / folder_name
    if output_folder.exists():
        if overwrite:
            logger.warning(f"Overwriting existing output folder: {output_folder}")
        else:
            raise FileExistsError(f"Output folder already exists: {output_folder}")

    output_folder.mkdir(parents=True, exist_ok=True)
    return output_folder


@dataclass
class SimulationJob:
    index: int
    settings_file: Path
    output_folder: Path
    tsize: int
    map_folder: Path


def run_simulation(job: SimulationJob, executable: Path, logger: logging.Logger) -> Tuple[bool, str]:
    log_path = job.output_folder / "run.log"

    cmd = [
        str(executable),
        str(job.settings_file),
        str(job.output_folder),
        str(job.tsize),
        str(job.map_folder),
    ]

    logger.info(f"Launching: {job.output_folder.name}")
    logger.debug("Command: %s", " ".join(cmd))

    with log_path.open("w", encoding="utf-8") as log_file:
        try:
            subprocess.run(
                cmd,
                stdout=log_file,
                stderr=subprocess.STDOUT,
                check=True,
            )
            logger.info(f"Finished: {job.output_folder.name}")
            return True, job.output_folder.name
        except subprocess.CalledProcessError as exc:
            logger.error(
                "Simulation failed (%s): exit code %s",
                job.output_folder.name,
                exc.returncode,
            )
            return False, f"{job.output_folder.name} (exit {exc.returncode})"
        except subprocess.TimeoutExpired:
            logger.error("Simulation timed out: %s", job.output_folder.name)
            return False, f"{job.output_folder.name} (timeout)"
        except Exception as exc:
            logger.error("Simulation exception for %s: %s", job.output_folder.name, exc)
            return False, f"{job.output_folder.name} (error)"


def run_summary_script(
    summary_script: Path,
    run_root: Path,
    summary_root: Path,
    template: Path,
    logger: logging.Logger,
) -> bool:
    cmd = [
        sys.executable,
        str(summary_script),
        str(run_root),
        str(summary_root),
        "--template",
        str(template),
    ]
    logger.info("Running summary script: %s", " ".join(cmd))
    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=True,
        )
        summary_output = result.stdout or ""
        if summary_output:
            logger.info("Summary script output:\n%s", summary_output.rstrip())
            for line in summary_output.splitlines():
                if "Skipping incomplete CSV:" in line or "Skipping unreadable CSV:" in line:
                    logger.warning("Affected summary input: %s", line.strip())
        return True
    except subprocess.CalledProcessError as exc:
        logger.error("Summary script failed: %s", exc.stdout or "no output")
        return False
    except Exception as exc:
        logger.error("Summary script exception: %s", exc)
        return False


def concatenate_population_csvs(
    scenario: str,
    runs_root: Path,
    logger: logging.Logger,
) -> dict[str, Path]:
    scenario_root = runs_root / scenario
    summary_dir = scenario_root / "summary"
    summary_dir.mkdir(parents=True, exist_ok=True)

    csv_groups: dict[str, list[tuple[str, Path]]] = {}

    for sample_dir in sorted(scenario_root.iterdir()):
        if not sample_dir.is_dir() or not sample_dir.name.startswith("sample_"):
            continue

        for csv_path in sorted(sample_dir.glob("*.csv")):
            csv_groups.setdefault(csv_path.name, []).append((sample_dir.name, csv_path))

    combined_outputs: dict[str, Path] = {}

    for csv_name, source_files in sorted(csv_groups.items()):
        frames = []
        for source_run, path in source_files:
            df = pd.read_csv(path)
            if "source_run" not in df.columns:
                df["source_run"] = source_run
            frames.append(df)

        if not frames:
            continue

        combined = pd.concat(frames, ignore_index=True)
        output_path = summary_dir / f"all_{csv_name}"
        combined.to_csv(output_path, index=False)
        logger.info("Wrote combined %s: %s", csv_name, output_path)
        combined_outputs[csv_name] = output_path

    return combined_outputs


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Weighted simulation batch workflow for Iberian Lynx PVA"
    )

    parser.add_argument("scenario", choices=["historic", "ssp245", "ssp585"])
    parser.add_argument("samples", type=int)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument(
        "--inbreeding",
        type=lambda value: str(value).lower() in {"1", "true", "yes", "y", "on"},
        default=False,
        help="Use the inbreeding-aware settings files (supports --inbreeding true/false)",
    )

    parser.add_argument(
        "--calibration-csv",
        type=Path,
        default=None,
        help="Path to calibration summary CSV",
    )
    parser.add_argument(
        "--rabbit-root",
        type=Path,
        default=None,
        help="Path to Rabbit_output root",
    )
    parser.add_argument(
        "--maps-root",
        type=Path,
        default=None,
        help="Path to maps root",
    )
    parser.add_argument(
        "--runs-root",
        type=Path,
        default=None,
        help="Path to simulation runs root",
    )
    parser.add_argument(
        "--executable",
        type=Path,
        default=None,
        help="Path to Run_model_debug executable",
    )
    parser.add_argument(
        "--summary-script",
        type=Path,
        default=None,
        help="Path to the summary maps script",
    )

    parser.add_argument(
        "--template",
        type=Path,
        default=None,
        help="Path to template TIFF used by summary script",
    )

    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path.cwd()

    calibration_csv = (
        args.calibration_csv
        if args.calibration_csv is not None
        else repo_root / "results" / "calibration_summary_RCorrected.csv"
        #else repo_root / "results" / "calibration_summary.csv"
    )
    rabbit_root = (
        args.rabbit_root
        if args.rabbit_root is not None
        else repo_root / "data" / "Rabbit_output"
    )
    maps_root = (
        args.maps_root
        if args.maps_root is not None
        else repo_root / "data" / "model_input" / "maps"
    )
    runs_root = (
        args.runs_root
        if args.runs_root is not None
        else repo_root / "results" / "simulation_runs"
    )
    executable = (
        args.executable
        if args.executable is not None
        else repo_root / "Program" / "Executables" / "Run_model_debug"
    )
    summary_script = (
        args.summary_script
        if args.summary_script is not None
        else repo_root / "scripts" / "python" / "get_summary_maps_from_simulations.py"
    )
    scenario_label = f"{args.scenario}_IC" if args.inbreeding else args.scenario

    run_log = runs_root / scenario_label / "batch.log"
    run_log.parent.mkdir(parents=True, exist_ok=True)
    logger = setup_logging(run_log)

    logger.info("Starting weighted simulation batch")
    logger.info(
        "scenario=%s scenario_label=%s inbreeding=%s samples=%s workers=%s seed=%s overwrite=%s",
        args.scenario,
        scenario_label,
        args.inbreeding,
        args.samples,
        args.workers,
        args.seed,
        args.overwrite,
    )
    logger.info("calibration_csv=%s", calibration_csv)
    logger.info("rabbit_root=%s", rabbit_root)
    logger.info("maps_root=%s", maps_root)
    logger.info("runs_root=%s", runs_root)
    logger.info("executable=%s", executable)
    logger.info("summary_script=%s", summary_script)

    if not executable.exists():
        logger.error("Executable not found: %s", executable)
        return 1

    if not summary_script.exists():
        logger.error("Summary script not found: %s", summary_script)
        return 1

    settings_file = (
        get_settings_file_IC(args.scenario, repo_root)
        if args.inbreeding
        else get_settings_file(args.scenario, repo_root)
    )
    logger.info("settings_file=%s", settings_file)

    if not settings_file.exists():
        logger.error("Settings file not found: %s", settings_file)
        return 1

    sampled = read_and_sample_calibration(calibration_csv, args.samples, args.seed, logger)

    replicates = get_replicates_for_scenario(args.scenario, rabbit_root, logger)
    random.seed(args.seed)
    selected = [
        (random.choice(replicates), int(row["threshold"]), int(row["n_months"]))
        for _, row in sampled.iterrows()
    ]
    ensure_breeding_maps(
        args.scenario,
        sorted(set(selected)),
        rabbit_root,
        maps_root,
        repo_root,
        args.workers,
        logger,
    )

    jobs: List[SimulationJob] = []
    for idx, ((replicate, threshold, n_months), (_, row)) in enumerate(
        zip(selected, sampled.iterrows())
    ):
        tsize = int(row["Tsize"])

        map_folder = resolve_map_folder(
            args.scenario,
            replicate,
            threshold,
            n_months,
            maps_root,
            logger,
        )

        output_folder = create_output_folder(
            runs_root,
            scenario_label,
            idx,
            replicate,
            threshold,
            n_months,
            tsize,
            args.overwrite,
            logger,
        )

        jobs.append(
            SimulationJob(
                index=idx,
                settings_file=settings_file,
                output_folder=output_folder,
                tsize=tsize,
                map_folder=map_folder,
            )
        )

    logger.info("Prepared %s jobs", len(jobs))

    completed = []
    failed = []

    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        future_to_job = {
            executor.submit(run_simulation, job, executable, logger): job
            for job in jobs
        }
        for future in as_completed(future_to_job):
            job = future_to_job[future]
            try:
                success, message = future.result()
                if success:
                    completed.append(message)
                else:
                    failed.append(message)
            except Exception as exc:
                failed.append(f"{job.output_folder.name} (exception)")
                logger.exception("Job failed with exception: %s", exc)

    logger.info("Completed jobs: %s", len(completed))
    logger.info("Failed jobs: %s", len(failed))

    summary_maps_root = runs_root / scenario_label / "summary_maps"
    summary_maps_root.mkdir(parents=True, exist_ok=True)

    template = (
        args.template
        if args.template is not None
        else repo_root / "data" / "GIS_maps" / "Peninsula_500_template.tif"
    )
    logger.info("template=%s", template)
    if not template.exists():
        logger.warning("Template not found: %s", template)

    if run_summary_script(
        summary_script, runs_root / scenario_label, summary_maps_root, template, logger
    ):
        logger.info("Summary maps saved in %s", summary_maps_root)
    else:
        logger.warning("Summary map generation failed")

    combined_csvs = concatenate_population_csvs(scenario_label, runs_root, logger)
    if combined_csvs:
        for csv_name, output_path in sorted(combined_csvs.items()):
            logger.info("Combined %s CSV: %s", csv_name, output_path)
    else:
        logger.warning("No CSV files found to combine for scenario %s", scenario_label)

    logger.info("Weighted simulation batch finished")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
