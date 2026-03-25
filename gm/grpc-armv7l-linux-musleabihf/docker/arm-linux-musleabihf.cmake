# CMake toolchain file for cross-compiling to ARM Linux musl hard-float
# using the musl.cc armv7l-linux-musleabihf GCC toolchain.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR armv7l)

set(CROSS_PREFIX "armv7l-linux-musleabihf")
set(CROSS_ROOT "/opt/${CROSS_PREFIX}-cross")

set(CMAKE_SYSROOT "${CROSS_ROOT}/${CROSS_PREFIX}/sysroot")

# Install prefix for cross-compiled libraries (passed via -DCMAKE_INSTALL_PREFIX)
# Must be in CMAKE_FIND_ROOT_PATH so find_package() works under ONLY mode.
set(CMAKE_FIND_ROOT_PATH "${CMAKE_SYSROOT}" "/opt/grpc-arm")

set(CMAKE_C_COMPILER   "${CROSS_ROOT}/bin/${CROSS_PREFIX}-gcc")
set(CMAKE_CXX_COMPILER "${CROSS_ROOT}/bin/${CROSS_PREFIX}-g++")
set(CMAKE_AR           "${CROSS_ROOT}/bin/${CROSS_PREFIX}-ar"    CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB       "${CROSS_ROOT}/bin/${CROSS_PREFIX}-ranlib" CACHE FILEPATH "Ranlib")
set(CMAKE_STRIP        "${CROSS_ROOT}/bin/${CROSS_PREFIX}-strip"  CACHE FILEPATH "Strip")

# Match ct-ng config: cortex-a15, neon-vfpv4, hard float
set(CMAKE_C_FLAGS_INIT   "-mcpu=cortex-a15 -mfpu=neon-vfpv4 -mfloat-abi=hard")
set(CMAKE_CXX_FLAGS_INIT "-mcpu=cortex-a15 -mfpu=neon-vfpv4 -mfloat-abi=hard")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
