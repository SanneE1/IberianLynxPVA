import argparse
import numpy as np
import pandas as pd
from pathlib import Path
from scipy import stats
import sys

# Use bottleneck if available for faster operations
try:
    import bottleneck as bn
    USE_BOTTLENECK = True
    print("Using Bottleneck for accelerated computations")
except ImportError:
    USE_BOTTLENECK = False
    print("Bottleneck not found, using NumPy (consider installing: pip install bottleneck)")

try:
    import rasterio
    HAS_RASTERIO = True
except ImportError:
    HAS_RASTERIO = False


def read_template_raster(template_path):
    if template_path is None:
        return None
    if not HAS_RASTERIO:
        raise ImportError(
            "rasterio is required to create GeoTIFF outputs. Install it with: pip install rasterio"
        )

    template_path = Path(template_path)
    if not template_path.exists():
        raise FileNotFoundError(f"Template raster not found: {template_path}")

    with rasterio.open(template_path) as src:
        profile = src.profile.copy()
        shape = (src.height, src.width)
        nodata = src.nodata

    profile.update(dtype=rasterio.float32, count=1)
    if nodata is not None:
        profile.update(nodata=np.float32(nodata))

    return {
        "profile": profile,
        "shape": shape,
        "nodata": nodata,
    }


def save_geotiff(array, out_path, template_info):
    if template_info is None:
        return

    array = np.asarray(array, dtype=np.float32)
    template_shape = template_info["shape"]
    if array.shape != template_shape:
        raise ValueError(
            f"Array shape {array.shape} does not match template raster shape {template_shape}"
        )

    profile = template_info["profile"].copy()
    if template_info["nodata"] is not None:
        array = np.where(np.isfinite(array), array, np.float32(template_info["nodata"]))
    else:
        profile["nodata"] = np.float32(np.nan)

    with rasterio.open(out_path, "w", **profile) as dst:
        dst.write(array, 1)


def save_csv(array, out_path):
    pd.DataFrame(array).to_csv(out_path, index=False, header=False)


def calculate_matrix_statistics(folder_paths, output_folder, confidence_level=0.95, template_info=None):
    """
    Calculate occupancy probability (value > 0) for each cell across multiple
    txt matrices. For files with "traveled" in the filename, instead compute
    the mean and 95% CI (lower/upper) maps.

    Parameters:
    -----------
    folder_paths : list of str
        List of folder paths containing the txt matrices
    output_folder : str
        Path where summary files will be saved
    confidence_level : float
        Confidence level for the interval (default: 0.95), only used for
        "traveled" files
    
    """
    
    # Create output folder if it doesn't exist
    output_path = Path(output_folder)
    output_path.mkdir(parents=True, exist_ok=True)
    
    # Get list of CSV files from the first folder (assuming all folders have same files)
    first_folder = Path(folder_paths[0], "maps")
    csv_files = sorted(first_folder.glob("*.csv"))
    
    if not csv_files:
        print(f"No CSV files found in {first_folder}")
        return
    
    print(f"Found {len(csv_files)} CSV files")
    print(f"Processing {len(folder_paths)} folders")
    
    # Process each CSV file
    for csv_file in csv_files:
        filename = csv_file.name
        print(f"\nProcessing {filename}...")
        
        # Collect all matrices for this file
        matrices = []
        
        for folder in folder_paths:
            file_path = Path(folder, "maps") / filename
            if file_path.exists():
                df = pd.read_csv(file_path, header=None)
                matrices.append(df.values)
            else:
                print(f"  Warning: {file_path} not found, skipping")
        
        if not matrices:
            print(f"  No valid matrices found for {filename}, skipping")
            continue
        
        # Stack matrices along a new axis (now shape is: n_folders x rows x cols)
        matrices_array = np.stack(matrices, axis=0)
        n_samples = matrices_array.shape[0]
        
        base_name = filename.replace('.csv', '')

        if "traveled" in filename:
            print(f"  Computing mean and {confidence_level*100:.0f}% CI across {n_samples} matrices...")

            mean_matrix = np.mean(matrices_array, axis=0)
            std_matrix = np.std(matrices_array, axis=0, ddof=1)
            se_matrix = std_matrix / np.sqrt(n_samples)

            t_value = stats.t.ppf((1 + confidence_level) / 2, n_samples - 1)
            margin_error = t_value * se_matrix

            lower_ci = mean_matrix - margin_error
            upper_ci = mean_matrix + margin_error

            save_csv(mean_matrix, output_path / f"{base_name}_mean.csv")
            save_csv(lower_ci, output_path / f"{base_name}_lower_ci.csv")
            save_csv(upper_ci, output_path / f"{base_name}_upper_ci.csv")

            save_geotiff(mean_matrix, output_path / f"{base_name}_mean.tif", template_info)
            save_geotiff(lower_ci, output_path / f"{base_name}_lower_ci.tif", template_info)
            save_geotiff(upper_ci, output_path / f"{base_name}_upper_ci.tif", template_info)

        else:
            print(f"  Computing occupancy probability across {n_samples} matrices...")

            occupied = matrices_array > 0
            occupancy_prob = np.mean(occupied, axis=0)

            save_csv(occupancy_prob, output_path / f"{base_name}_occupancy_prob.csv")
            save_geotiff(occupancy_prob, output_path / f"{base_name}_occupancy_prob.tif", template_info)
        


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Summarize simulation matrices as CSV and optional GeoTIFF rasters."
    )
    parser.add_argument("parent_directory", type=Path, help="Parent directory containing simulation folders")
    parser.add_argument("output_folder", type=Path, help="Folder where summaries will be saved")
    parser.add_argument(
        "--template",
        "-t",
        type=Path,
        default=None,
        help="Optional template GeoTIFF file to write raster outputs"
    )
    parser.add_argument(
        "--confidence",
        type=float,
        default=0.95,
        help="Confidence level for traveled mean/CI calculations"
    )
    args = parser.parse_args()

    folders = sorted([str(f) for f in args.parent_directory.iterdir() if f.is_dir()])
    if not folders:
        print(f"No subdirectories found in {args.parent_directory}")
        sys.exit(1)

    print(f"Found {len(folders)} folders to process:")
    for folder in folders:
        print(f"  - {folder}")

    template_info = None
    if args.template is not None:
        template_info = read_template_raster(args.template)

    calculate_matrix_statistics(
        folders,
        args.output_folder,
        confidence_level=args.confidence,
        template_info=template_info,
    )
