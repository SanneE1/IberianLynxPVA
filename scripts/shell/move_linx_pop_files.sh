#!/bin/bash

# Usage: ./move_files.sh <source_dir> <destination_dir>

SOURCE_DIR="$1"
DEST_DIR="$2"

# Check arguments are provided
if [ -z "$SOURCE_DIR" ] || [ -z "$DEST_DIR" ]; then
    echo "Usage: $0 <source_dir> <destination_dir>"
    exit 1
fi

# Check source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist."
    exit 1
fi

# Create destination folders
mkdir -p "$DEST_DIR/all_lynx_pop"
mkdir -p "$DEST_DIR/all_lynx_biopop"

# Move lynx_pop_sizes.csv files
while IFS= read -r f; do
    subfolder=$(basename "$(dirname "$f")")
    echo "Moving: $f -> $DEST_DIR/all_lynx_pop/${subfolder}_lynx_pop_size.csv"
    mv "$f" "$DEST_DIR/all_lynx_pop/${subfolder}_lynx_pop_size.csv"
done < <(find "$SOURCE_DIR" -name "lynx_pop_size.csv")

# Move lynx_biopop_sizes.csv files
while IFS= read -r f; do
    subfolder=$(basename "$(dirname "$f")")
    echo "Moving: $f -> $DEST_DIR/all_lynx_biopop/${subfolder}_lynx_biopop_size.csv"
    mv "$f" "$DEST_DIR/all_lynx_biopop/${subfolder}_lynx_biopop_size.csv"
done < <(find "$SOURCE_DIR" -name "lynx_biopop_size.csv")