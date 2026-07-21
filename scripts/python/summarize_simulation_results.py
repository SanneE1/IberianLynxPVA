#!/usr/bin/env python3
"""
Standalone summary script for simulation run folders.

Given a parent folder containing one or more run folders, this script:
1. Reads each run folder's maps/*.csv files and writes summary files
   (occupancy probabilities or mean/CI maps for traveled maps).
2. Combines CSV files found directly in each run folder into summary files.

Usage:
    python3 scripts/python/summarize_simulation_results.py /path/to/main_folder
    python3 scripts/python/summarize_simulation_results.py /path/to/main_folder /path/to/output_folder
"""

import argparse
import csv
import math
import statistics
import sys
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple


def normal_inverse_cdf(probability: float) -> float:
    # Approximation of the inverse CDF for the standard normal distribution.
    # This is sufficient for summary-map confidence intervals and avoids
    # requiring scipy or newer Python versions.
    if probability <= 0:
        return float("-inf")
    if probability >= 1:
        return float("inf")

    # Coefficients from the Abramowitz-Stegun approximation
    a = [-3.969683028665376e01, 2.209460984245205e02, -2.759285104469687e02, 1.383577518672690e02, -3.066479806614716e01, 2.506628277459239e00]
    b = [-5.447609879822406e01, 1.615858368580409e02, -1.556989798598866e02, 6.680131188771972e01, -1.328068155288572e01]
    c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e00, -2.549732539343734e00, 4.374664141464968e00, 2.938163982698783e00]
    d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e00, 3.754408661907416e00]

    plow = 0.02425
    phigh = 1.0 - plow

    if probability < plow:
        q = math.sqrt(-2.0 * math.log(probability))
        return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0)

    if probability > phigh:
        q = math.sqrt(-2.0 * math.log(1.0 - probability))
        return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0)

    q = probability - 0.5
    r = q * q
    return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q / ((((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1.0))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize map matrices and combine CSV outputs from run folders"
    )
    parser.add_argument("parent_dir", type=Path, help="Folder that contains the run folders")
    parser.add_argument(
        "output_dir",
        type=Path,
        nargs="?",
        default=None,
        help="Where summary files should be written (default: <parent_dir>/summary)",
    )
    parser.add_argument(
        "--confidence-level",
        type=float,
        default=0.95,
        help="Confidence level for traveled-map CI summaries (default: 0.95)",
    )
    return parser.parse_args()


def discover_run_folders(parent_dir: Path, output_dir: Optional[Path] = None) -> List[Path]:
    if not parent_dir.exists():
        raise FileNotFoundError(f"Parent folder not found: {parent_dir}")
    if not parent_dir.is_dir():
        raise NotADirectoryError(f"Parent path is not a directory: {parent_dir}")

    resolved_output = output_dir.resolve() if output_dir is not None else None
    run_folders = [
        path
        for path in sorted(parent_dir.iterdir())
        if path.is_dir() and (resolved_output is None or path.resolve() != resolved_output)
    ]
    if not run_folders:
        raise ValueError(f"No subfolders found in {parent_dir}")
    return run_folders


def read_matrix(path: Path) -> List[List[float]]:
    with path.open("r", newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))

    if not rows:
        raise ValueError(f"Matrix file is empty: {path}")

    matrix: List[List[float]] = []
    for row in rows:
        if not row:
            continue
        matrix.append([float(value) for value in row])

    if not matrix:
        raise ValueError(f"Matrix file contains no data rows: {path}")
    return matrix


def write_matrix(path: Path, matrix: Sequence[Sequence[float]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        for row in matrix:
            writer.writerow([format_value(value) for value in row])


def format_value(value: float) -> str:
    if isinstance(value, float):
        if abs(value) < 1e-12:
            return "0"
        return f"{value:.12g}"
    return str(value)


def read_csv_rows(path: Path) -> Tuple[List[str], List[List[str]], bool]:
    with path.open("r", newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))

    if not rows:
        return [], [], False

    first_row = rows[0]
    is_header = not all(is_number(cell) for cell in first_row)
    data_rows = rows[1:] if is_header else rows
    return first_row, data_rows, is_header


def is_number(value: str) -> bool:
    try:
        float(value)
    except ValueError:
        return False
    return True


def write_csv_rows(path: Path, header: Sequence[str], rows: Sequence[Sequence[str]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        if header:
            writer.writerow(list(header))
        for row in rows:
            writer.writerow(list(row))


def summarize_maps(
    run_folders: Sequence[Path],
    output_dir: Path,
    confidence_level: float = 0.95,
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    available_map_dirs = [folder / "maps" for folder in run_folders if (folder / "maps").exists() and (folder / "maps").is_dir()]

    if not available_map_dirs:
        raise ValueError("No 'maps' folders were found in the supplied run folders")

    csv_files = sorted(
        {csv_path.name for map_dir in available_map_dirs for csv_path in map_dir.glob("*.csv")}
    )
    if not csv_files:
        raise ValueError("No CSV files found in any maps folder")

    print(f"Found {len(csv_files)} map CSV files across {len(run_folders)} run folders")
    for filename in csv_files:
        print(f"Processing {filename}...")
        matrices: List[List[List[float]]] = []
        for folder in run_folders:
            file_path = folder / "maps" / filename
            if file_path.exists() and file_path.is_file():
                matrices.append(read_matrix(file_path))
            else:
                print(f"  Warning: {file_path} not found, skipping")

        if not matrices:
            print(f"  No valid matrices found for {filename}, skipping")
            continue

        n_samples = len(matrices)
        base_name = filename.replace(".csv", "")

        if "traveled" in filename.lower():
            rows = len(matrices[0])
            cols = len(matrices[0][0])
            mean_matrix = [[0.0 for _ in range(cols)] for _ in range(rows)]
            std_matrix = [[0.0 for _ in range(cols)] for _ in range(rows)]

            for i in range(rows):
                for j in range(cols):
                    values = [matrix[i][j] for matrix in matrices]
                    mean_value = statistics.mean(values)
                    mean_matrix[i][j] = mean_value
                    if n_samples > 1:
                        std_matrix[i][j] = statistics.stdev(values)

            z_value = normal_inverse_cdf((1 + confidence_level) / 2)
            lower_ci = [[0.0 for _ in range(cols)] for _ in range(rows)]
            upper_ci = [[0.0 for _ in range(cols)] for _ in range(rows)]

            for i in range(rows):
                for j in range(cols):
                    if n_samples > 1:
                        se = std_matrix[i][j] / math.sqrt(n_samples)
                        margin = z_value * se
                        lower_ci[i][j] = mean_matrix[i][j] - margin
                        upper_ci[i][j] = mean_matrix[i][j] + margin
                    else:
                        lower_ci[i][j] = mean_matrix[i][j]
                        upper_ci[i][j] = mean_matrix[i][j]

            write_matrix(output_dir / f"{base_name}_mean.csv", mean_matrix)
            write_matrix(output_dir / f"{base_name}_lower_ci.csv", lower_ci)
            write_matrix(output_dir / f"{base_name}_upper_ci.csv", upper_ci)
        else:
            rows = len(matrices[0])
            cols = len(matrices[0][0])
            occupancy = [[0.0 for _ in range(cols)] for _ in range(rows)]
            for i in range(rows):
                for j in range(cols):
                    occupied = sum(1 for matrix in matrices if matrix[i][j] > 0)
                    occupancy[i][j] = occupied / n_samples
            write_matrix(output_dir / f"{base_name}_occupancy_prob.csv", occupancy)


def combine_csv_files(run_folders: Sequence[Path], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    grouped_files: Dict[str, List[Tuple[str, Path]]] = {}
    for folder in run_folders:
        for csv_path in sorted(folder.glob("*.csv")):
            grouped_files.setdefault(csv_path.name, []).append((folder.name, csv_path))

    if not grouped_files:
        print("No CSV files found at the run-folder root for combination")
        return

    for filename, sources in sorted(grouped_files.items()):
        header: List[str] = []
        rows: List[List[str]] = []
        for source_run, csv_path in sources:
            file_header, file_rows, has_header = read_csv_rows(csv_path)
            if not header and has_header:
                header = ["source_run", *file_header]
            elif not header and not has_header:
                header = ["source_run"]

            for row in file_rows:
                rows.append([source_run, *row])

        out_path = output_dir / f"combined_{filename}"
        write_csv_rows(out_path, header, rows)
        print(f"Wrote combined CSV: {out_path}")


def main() -> int:
    args = parse_args()
    parent_dir = args.parent_dir.resolve()
    output_dir = args.output_dir.resolve() if args.output_dir is not None else parent_dir / "summary"

    try:
        run_folders = discover_run_folders(parent_dir, output_dir)
    except (FileNotFoundError, NotADirectoryError, ValueError) as exc:
        print(exc)
        return 1

    print(f"Processing folders under {parent_dir}")
    print(f"Writing summaries to {output_dir}")

    summarize_maps(run_folders, output_dir, confidence_level=args.confidence_level)
    combine_csv_files(run_folders, output_dir)

    print("Done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
