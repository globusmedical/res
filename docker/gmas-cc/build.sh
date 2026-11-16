#!/bin/sh
# Rebuilds the GMAS cross compiler as native Win32 executables. See README.md.
#
#     sh docker/gmas-cc/build.sh <path-to-gmas-cc-linux-ppc_4.1.0-gm001>
#
# The argument is the root of the Cygwin package (the folder holding
# cpp-env.json and opt/); its PowerPC target files are reused unchanged.
# Requires Docker. Writes the package tree and tarball into out/ next to this
# script. Build state is kept in the gmas-cc-work volume, so a failed run
# resumes; remove the volume to start from scratch.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
ORIG=${1:?usage: build.sh <gmas-cc-linux-ppc_4.1.0-gm001 package root>}
ORIG=$(cd "$ORIG" && pwd)
OUT="$HERE/out"

mkdir -p "$OUT"
docker build -t gmas-cc "$HERE"
docker run --rm \
  -v "$ORIG:/orig:ro" \
  -v "$OUT:/out" \
  -v gmas-cc-work:/work \
  -e JOBS -e PKG_NAME \
  gmas-cc bash /src/build-in-container.sh
