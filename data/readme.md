# Process dataset (except LiDAR)

``` shell
python waymo_processor/waymo_converter.py \
    --root_dir  ../data/waymo/raw/training/ \
    --save_dir  ../data/waymo/training_set_processed/ \
    --process_list pose calib image track dynamic
```

``` shell
python waymo_processor/waymo_converter.py \
    --root_dir  ../data/waymo/raw/validation/ \
    --save_dir  ../data/waymo/validation_set_processed/ \
    --process_list pose calib image track dynamic
```

# Process dataset (LiDAR)

``` shell
python waymo_processor/waymo_get_lidar_pcd.py     --root_dir  ../data/waymo/raw/validation/      --save_dir  ../data/waymo/validation_set_processed/
```

``` shell
python waymo_processor/waymo_get_lidar_pcd.py     --root_dir  ../data/waymo/raw/training/      --save_dir  ../data/waymo/training_set_processed/
```

# Render LiDAR 

``` shell
conda activate streetcrafter 
python waymo_processor/waymo_render_lidar_pcd.py \
    --data_dir ../data/waymo/training_set_processed/ \
    --save_dir color_render \
    --delta_frames 10 \
    --cams 0 1 2 3 4 \
    --shifts 0 2 3
```

``` shell
python waymo_processor/waymo_render_lidar_pcd.py \
    --data_dir ../data/waymo/validation_set_processed/ \
    --save_dir color_render \
    --delta_frames 10 \
    --cams 0 1 2 3 4 \
    --shifts 0 2 3
```
# Prepare meta data

``` shell
python waymo_processor/waymo_prepare_meta.py \
    --root_dir ../data/waymo/ \
    --split train
```

``` shell
python waymo_processor/waymo_prepare_meta.py \
    --root_dir ../data/waymo/ \
    --split val
```