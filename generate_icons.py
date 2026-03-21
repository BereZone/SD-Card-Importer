
import subprocess
import os
import sys

# absolute paths
project_root = "/Users/berezone/Documents/Projects/SD Card File Importer"
source_image = os.path.join(project_root, "sd_card.png")
output_dir = os.path.join(project_root, "SD Card File Importer/Assets.xcassets/AppIcon.appiconset")

if not os.path.exists(source_image):
    print(f"Error: Source image not found at {source_image}")
    sys.exit(1)

if not os.path.exists(output_dir):
    print(f"Error: Output directory not found at {output_dir}")
    sys.exit(1)

# Define sizes
sizes = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
    "icon_1024x1024.png": 1024
}

for filename, size in sizes.items():
    output_path = os.path.join(output_dir, filename)
    print(f"Generating {filename} ({size}x{size}) to {output_path}...")
    try:
        subprocess.run(["sips", "-z", str(size), str(size), source_image, "--out", output_path], check=True)
    except subprocess.CalledProcessError as e:
        print(f"Failed to generate {filename}: {e}")

print("Icon generation complete.")
