#!/bin/bash
set -e

# Build the cross-compiler as the 'build' user (ct-ng refuses to run as root)
su - build -c 'ct-ng build'

# Package the cross-compiler into a ZIP file
cd /home/build/x-tools/HOST-x86_64-w64-mingw32
chmod -R a+rw .

# Fix duplicate files (case-insensitive collisions for Windows)
python3 /fix_filename_cases.py

# Create a ZIP file with the cross-compiler
zip -r /output/x86_64-w64-mingw32_to_armv7l-unknown-linux-musleabihf.zip armv7l-unknown-linux-musleabihf
