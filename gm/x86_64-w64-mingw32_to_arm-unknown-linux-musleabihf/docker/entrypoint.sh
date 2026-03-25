#!/bin/bash

# Use ct-ng to build the cross-compiler
cd ~/build
ct-ng build

# Package the cross-compiler into a ZIP file
cd ~/x-tools/HOST-x86_64-w64-mingw32
chmod -R u+w .

# Fix duplicate files
python ~/fix-duplicate-files.py

# Create a ZIP file with the cross-compiler
# from directory "arm-unknown-linux-musleabihf", 
# named "x86_64-w64-mingw32_to_arm-unknown-linux-musleabihf.zip"
zip -r x86_64-w64-mingw32_to_arm-unknown-linux-musleabihf.zip arm-unknown-linux-musleabihf
