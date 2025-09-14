#!/usr/bin/env python3
"""
Script to download Waymo training dataset.
Downloads tfrecord files from 1.4.1 dataset and parsed data from 2.0.0 dataset for training.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from typing import List


def run_command(cmd, description):
    """Run a command and handle errors."""
    print(f"Running: {description}")
    print(f"Command: {cmd}")
    try:
        result = subprocess.run(cmd, shell=True, check=True, capture_output=True, text=True)
        print(f"✓ {description} completed successfully")
        return result
    except subprocess.CalledProcessError as e:
        print(f"✗ Error in {description}:")
        print(f"Return code: {e.returncode}")
        print(f"Error output: {e.stderr}")
        raise Exception(f"Command failed: {e.stderr}")


def download_tfrecord_file(filename, target_dir, scene_id):
    """Download a single tfrecord file from 1.4.1 dataset."""
    # Path to gsutil
    GSUTIL_PATH = "/home/charles/.local/google-cloud-sdk/bin/gsutil"
    
    # Construct tfrecord URL for 1.4.1 dataset
    tfrecord_url = f"gs://waymo_open_dataset_v_1_4_1/individual_files/training/{filename}.tfrecord"
    
    run_command(
        f'{GSUTIL_PATH} -m cp "{tfrecord_url}" {target_dir}/',
        f"Downloading tfrecord file: {filename}.tfrecord"
    )


def download_parsed_data(scene_id, target_dir):
    """Download parsed data from 2.0.0 dataset for a given scene."""
    # Path to gsutil
    GSUTIL_PATH = "/home/charles/.local/google-cloud-sdk/bin/gsutil"
    
    # Data types to download (same as validation script)
    data_types = [
        ("lidar", "lidar"),
        ("lidar_box", "lidar_box"),  # Note: "lidarbox" as folder name
        ("lidar_calibration", "lidar_calibration"),
        ("lidar_camera_projection", "lidar_camera_projection"),
        ("lidar_camera_synced_box", "lidar_camera_synced_box"),
        ("lidar_pose", "lidar_pose"),
        ("vehicle_pose", "vehicle_pose")
    ]
    
    for data_type, folder_name in data_types:
        # Create subdirectory for this data type
        data_dir = target_dir / folder_name
        data_dir.mkdir(parents=True, exist_ok=True)
        
        # Download the parquet file
        parquet_file = f"{scene_id}.parquet"
        parquet_url = f"gs://waymo_open_dataset_v_2_0_0/training/{data_type}/{parquet_file}"
        
        run_command(
            f'{GSUTIL_PATH} -m cp "{parquet_url}" {data_dir}/',
            f"Downloading {data_type} data to {folder_name}/"
        )


def download_scene_data(scene_id, target_dir, filename):
    """Download both tfrecord and parsed data for a single scene."""
    print(f"\n=== Processing scene {scene_id} ===")
    
    # Download tfrecord file
    download_tfrecord_file(filename, target_dir, scene_id)
    
    # Extract segment ID from tfrecord filename for parquet files
    # Filename format: segment-<segment_id>_with_camera_labels (without .tfrecord extension)
    if filename.startswith("segment-") and filename.endswith("_with_camera_labels"):
        segment_id = filename.replace("segment-", "").replace("_with_camera_labels", "")
    else:
        print(f"Warning: Unexpected filename format: {filename}")
        segment_id = str(scene_id)  # Fallback to scene_id
    
    # Download parsed data using segment ID
    download_parsed_data(segment_id, target_dir)
    
    print(f"✓ Scene {scene_id} completed successfully!")


def download_training_data(
    scene_ids: List[int],
    target_dir: str,
    waymo_train_list_path: str = "./waymo_train_list.txt"
) -> None:
    """
    Downloads training data for specified scene IDs.
    
    Args:
        scene_ids (List[int]): List of scene IDs to download
        target_dir (str): Target directory to save downloaded files
        waymo_train_list_path (str): Path to waymo_train_list.txt file
    """
    # Create target directory
    target_path = Path(target_dir)
    target_path.mkdir(parents=True, exist_ok=True)
    
    # Read waymo train list
    if not os.path.exists(waymo_train_list_path):
        print(f"Error: waymo_train_list.txt not found at {waymo_train_list_path}")
        sys.exit(1)
    
    with open(waymo_train_list_path, "r") as f:
        total_list = f.readlines()
    
    # Get filenames for the specified scene IDs
    file_names = [total_list[i].strip() for i in scene_ids]
    
    print(f"Downloading training data for {len(scene_ids)} scenes...")
    print(f"Target directory: {target_path}")
    
    # Use ThreadPoolExecutor for concurrent downloads
    with ThreadPoolExecutor(max_workers=5) as executor:  # Reduced workers for stability
        futures = [
            executor.submit(download_scene_data, scene_id, target_path, filename)
            for scene_id, filename in zip(scene_ids, file_names)
        ]
        
        for counter, future in enumerate(futures, start=1):
            try:
                future.result()
                print(f"[{counter}/{len(scene_ids)}] Scene completed successfully!")
            except Exception as e:
                print(f"[{counter}/{len(scene_ids)}] Scene failed. Error: {e}")
    
    print("\n✓ All training data download completed!")
    print(f"Training data location: {target_path}")
    
    # List downloaded files
    print("\nDownloaded files:")
    for root, dirs, files in os.walk(target_path):
        level = root.replace(str(target_path), '').count(os.sep)
        indent = ' ' * 2 * level
        print(f"{indent}{os.path.basename(root)}/")
        subindent = ' ' * 2 * (level + 1)
        for file in files:
            print(f"{subindent}{file}")


def main():
    parser = argparse.ArgumentParser(description="Download Waymo training dataset")
    parser.add_argument(
        "--target_dir",
        type=str,
        default="data/waymo/raw/training",
        help="Path to the target directory"
    )
    parser.add_argument(
        "--scene_ids", 
        type=int, 
        nargs="+", 
        required=True,
        help="Scene IDs to download"
    )
    parser.add_argument(
        "--split_file", 
        type=str, 
        default=None, 
        help="Split file in data/waymo_splits"
    )
    parser.add_argument(
        "--waymo_train_list",
        type=str,
        default="./waymo_train_list.txt",
        help="Path to waymo_train_list.txt file"
    )
    
    args = parser.parse_args()
    
    print("Note: `gcloud auth login` is required before running this script")
    print("Downloading Waymo training dataset from Google Cloud Storage...")
    
    # Handle split file if provided
    if args.split_file is not None:
        if not os.path.exists(args.split_file):
            print(f"Error: Split file not found at {args.split_file}")
            sys.exit(1)
        
        with open(args.split_file, "r") as f:
            split_lines = f.readlines()[1:]  # Skip header
        
        scene_ids = [int(line.strip().split(",")[0]) for line in split_lines]
    else:
        scene_ids = args.scene_ids
    
    download_training_data(scene_ids, args.target_dir, args.waymo_train_list)


if __name__ == "__main__":
    main()
