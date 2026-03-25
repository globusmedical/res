# Qt5 Static Libraries for ARM Linux musl (armv7l-unknown-linux-musleabihf)

Pre-built Qt5 Core + Network static libraries for cross-compiling C++ code
targeting the ELMO PMAS (ARM Cortex-A15, musl libc, hard float).

## What's Included

| Component | Description |
|---|---|
| `lib/libQt5Core.a` | Qt5 Core static library (ARM musl) |
| `lib/libQt5Network.a` | Qt5 Network static library (ARM musl) |
| `include/QtCore/` | Qt5 Core headers |
| `include/QtNetwork/` | Qt5 Network headers |
| `lib/cmake/Qt5*/` | CMake config files for `find_package(Qt5)` |
| `bin/moc.exe` | Windows host tool for AUTOMOC |
| `bin/rcc.exe` | Windows host tool for AUTORCC |
| `bin/*.dll` | MinGW runtime DLLs for moc.exe/rcc.exe |

## Build Configuration

- **Qt version**: 5.15.2 (last open-source LTS release)
- **Target**: `armv7l-unknown-linux-musleabihf` (cortex-a15, neon-vfpv4, hard float)
- **Link type**: Static (`-static`)
- **Build type**: Release (`-release`)
- **Disabled modules**: GUI, Widgets, DBus, OpenGL, OpenSSL, ICU, X11/XCB, Wayland

## Building the Artifact

```bash
cd docker
docker compose build
docker compose up
```

The output appears in `docker/output/`:
- `qt5-armv7l-unknown-linux-musleabihf.tar.gz`
- `qt5-armv7l-unknown-linux-musleabihf.tar.gz.sha256`

## Publishing to grab

After building, upload the artifact to the S3 registry:

```bash
grab publish --collection qt5
```

## Usage in gm-egps-mctrl

The `gm-egps-mctrl` repo fetches this artifact via grab and sets `CMAKE_PREFIX_PATH`
to include the Qt5 installation. See `gm-egps-mctrl/cpp/README.md`.
