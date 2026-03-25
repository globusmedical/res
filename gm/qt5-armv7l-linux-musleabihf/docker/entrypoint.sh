#!/bin/bash
set -euo pipefail

QT_VERSION="${QT_VERSION:-5.15.2}"
QT_MAJOR_MINOR=$(echo "${QT_VERSION}" | cut -d. -f1-2)
# musl.cc tuple (no "unknown" vendor)
MUSL_CC_TUPLE="armv7l-linux-musleabihf"
# Our grab artifact tuple (with "unknown" vendor, matching the GCC 15.2 Canadian cross)
ARTIFACT_TUPLE="armv7l-unknown-linux-musleabihf"
SYSROOT="/opt/${MUSL_CC_TUPLE}-cross/${MUSL_CC_TUPLE}/sysroot"
INSTALL_PREFIX="/opt/qt5-arm"

# ── Step 1: Verify cross-compiler ───────────────────────────────────────
echo "=== Step 1/5: Verifying cross-compiler ==="
${MUSL_CC_TUPLE}-gcc --version | head -1
${MUSL_CC_TUPLE}-g++ --version | head -1

# ── Step 2: Download Qt5 source ─────────────────────────────────────────
echo "=== Step 2/5: Downloading Qt5 ${QT_VERSION} source ==="
cd /tmp
wget -q "https://download.qt.io/archive/qt/${QT_MAJOR_MINOR}/${QT_VERSION}/submodules/qtbase-everywhere-src-${QT_VERSION}.tar.xz"
tar xf "qtbase-everywhere-src-${QT_VERSION}.tar.xz"
QT_SRC="/tmp/qtbase-everywhere-src-${QT_VERSION}"

# Patch Qt 5.15.2 for GCC 11+ compatibility (missing <limits>)
# See QTBUG-90395 — std::numeric_limits needs <limits> header.
# Patch qglobal.h (included by everything) so all files inherit the fix.
sed -i '/#.*include <type_traits>/a #  include <limits>' \
    "${QT_SRC}/src/corelib/global/qglobal.h"

# Install custom mkspec for our cross-compiler
cp -r /mkspecs/linux-arm-musleabihf-g++ "${QT_SRC}/mkspecs/linux-arm-musleabihf-g++"

# ── Step 3: Configure and build Qt5 for ARM musl ────────────────────────
echo "=== Step 3/5: Configuring Qt5 for ARM musl cross-compilation ==="
mkdir -p /tmp/qt5-build
cd /tmp/qt5-build
"${QT_SRC}/configure" \
    -prefix "${INSTALL_PREFIX}" \
    -extprefix "${INSTALL_PREFIX}" \
    -hostprefix "${INSTALL_PREFIX}" \
    -opensource -confirm-license \
    -release \
    -static \
    -xplatform linux-arm-musleabihf-g++ \
    -sysroot "${SYSROOT}" \
    -no-gui \
    -no-widgets \
    -no-dbus \
    -no-opengl \
    -no-openssl \
    -no-icu \
    -no-glib \
    -no-cups \
    -no-fontconfig \
    -no-freetype \
    -no-harfbuzz \
    -no-xcb \
    -no-linuxfb \
    -no-directfb \
    -no-eglfs \
    -no-gbm \
    -no-kms \
    -no-evdev \
    -no-libinput \
    -no-tslib \
    -no-feature-testlib \
    -qt-pcre \
    -qt-zlib \
    -nomake examples \
    -nomake tests \
    -nomake tools \
    -make libs \
    -v

echo "=== Step 4/5: Building Qt5 ==="
make -j"$(nproc)"
make install

# ── Step 5: Fetch Windows moc.exe and package ───────────────────────────
echo "=== Step 5/5: Fetching Windows moc.exe and packaging ==="
aqt install-qt windows desktop "${QT_VERSION}" win64_mingw81 \
    --archives qtbase \
    --outputdir /tmp/qt5-win

# Also install the MinGW 8.1 runtime (provides libgcc, libstdc++, libwinpthread DLLs)
aqt install-tool windows desktop tools_mingw qt.tools.win64_mingw810 \
    --outputdir /tmp/qt5-win

WIN_QT_BIN="/tmp/qt5-win/${QT_VERSION}/mingw81_64/bin"
WIN_MINGW_BIN="/tmp/qt5-win/Tools/mingw810_64/bin"

# Replace Linux host tools with Windows host tools
rm -f "${INSTALL_PREFIX}/bin/moc" "${INSTALL_PREFIX}/bin/rcc" \
      "${INSTALL_PREFIX}/bin/qlalr" "${INSTALL_PREFIX}/bin/qmake" \
      "${INSTALL_PREFIX}/bin/tracegen"

# Copy moc.exe, rcc.exe, qmake.exe and their runtime dependencies
cp "${WIN_QT_BIN}/moc.exe" "${INSTALL_PREFIX}/bin/"
cp "${WIN_QT_BIN}/rcc.exe" "${INSTALL_PREFIX}/bin/"
cp "${WIN_QT_BIN}/qmake.exe" "${INSTALL_PREFIX}/bin/"
# Qt5Core.dll from Qt bin
cp "${WIN_QT_BIN}/Qt5Core.dll" "${INSTALL_PREFIX}/bin/"
# MinGW runtime DLLs from the MinGW toolchain
for dll in libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll; do
    if [ -f "${WIN_MINGW_BIN}/${dll}" ]; then
        cp "${WIN_MINGW_BIN}/${dll}" "${INSTALL_PREFIX}/bin/"
    fi
done

# Patch CMake config to reference .exe host tools
for tool in moc rcc qmake qlalr tracegen; do
    sed -i "s|/bin/${tool}\"|/bin/${tool}.exe\"|g" \
        "${INSTALL_PREFIX}/lib/cmake/Qt5Core/Qt5CoreConfigExtras.cmake" 2>/dev/null || true
done

# Package
ARTIFACT_NAME="qt5-${ARTIFACT_TUPLE}"
cd /opt
mv qt5-arm "${ARTIFACT_NAME}"

# Remove unnecessary files (keep mkspecs — Qt5CoreConfig.cmake checks for it)
rm -rf "${ARTIFACT_NAME}/lib/pkgconfig"
find "${ARTIFACT_NAME}/lib" -name '*.la' -o -name '*.prl' | xargs rm -f 2>/dev/null || true

tar czf "/output/${ARTIFACT_NAME}.tar.gz" "${ARTIFACT_NAME}"
cd /output
sha256sum "${ARTIFACT_NAME}.tar.gz" > "${ARTIFACT_NAME}.tar.gz.sha256"

echo "=== Done! ==="
echo "Artifact:  /output/${ARTIFACT_NAME}.tar.gz"
echo "Checksum:  /output/${ARTIFACT_NAME}.tar.gz.sha256"
ls -lh /output/
