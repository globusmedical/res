import os
from collections import defaultdict

# Directory to scan for files
base_dir = "."

# Dictionary to track case-insensitive filenames within each folder
folder_map = defaultdict(lambda: defaultdict(list))

# Walk through the directory to gather files
for root, _, files in os.walk(base_dir):
    for file in files:
        normalized_name = file.lower()  # Normalize to lowercase for case-insensitive matching
        folder_map[root][normalized_name].append(os.path.join(root, file))

# Check for case-insensitive collisions within each folder
collisions = {}
for folder, files in folder_map.items():
    collision_in_folder = {k: v for k, v in files.items() if len(v) > 1}
    if collision_in_folder:
        collisions[folder] = collision_in_folder

# If there are collisions, rename all but the first file in each collision group
for folder, files in collisions.items():
    for _, paths in files.items():
        for path in paths[1:]:
            base, ext = os.path.splitext(path)
            new_path = base + "_" + ext
            os.rename(path, new_path)
