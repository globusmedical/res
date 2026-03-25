#!/bin/bash
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────
GRPC_VERSION="${GRPC_VERSION:-1.71.0}"
PROTOBUF_VERSION="${PROTOBUF_VERSION:-5.29.5}"
ABSEIL_VERSION="${ABSEIL_VERSION:-20240722.0}"
CARES_VERSION="${CARES_VERSION:-1.34.5}"
RE2_VERSION="${RE2_VERSION:-2025-11-05}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.0}"
ZLIB_VERSION="${ZLIB_VERSION:-1.3.1}"

CROSS_PREFIX="armv7l-linux-musleabihf"
ARTIFACT_TUPLE="armv7l-unknown-linux-musleabihf"
INSTALL_PREFIX="/opt/grpc-arm"
# Native (host) install for protoc and grpc_cpp_plugin
HOST_PREFIX="/opt/grpc-host"
TOOLCHAIN="/toolchain.cmake"
NPROC=$(nproc)

mkdir -p "${INSTALL_PREFIX}" "${HOST_PREFIX}" /tmp/src

# ── Step 1: Verify cross-compiler ──────────────────────────────────────
echo "=== Step 1/9: Verifying cross-compiler ==="
${CROSS_PREFIX}-gcc --version | head -1
${CROSS_PREFIX}-g++ --version | head -1

# ── Step 2: Build zlib (cross) ──────────────────────────────────────────
echo "=== Step 2/9: Building zlib ${ZLIB_VERSION} ==="
cd /tmp/src
wget -q "https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz"
tar xf "zlib-${ZLIB_VERSION}.tar.gz"
cmake -S "zlib-${ZLIB_VERSION}" -B build-zlib -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF
cmake --build build-zlib -j"${NPROC}"
cmake --install build-zlib

# ── Step 3: Build OpenSSL (cross) ──────────────────────────────────────
echo "=== Step 3/9: Building OpenSSL ${OPENSSL_VERSION} ==="
cd /tmp/src
wget -q "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
tar xf "openssl-${OPENSSL_VERSION}.tar.gz"
cd "openssl-${OPENSSL_VERSION}"
# OpenSSL uses its own Configure script, not CMake
./Configure linux-armv4 \
    --cross-compile-prefix="${CROSS_PREFIX}-" \
    --prefix="${INSTALL_PREFIX}" \
    --openssldir="${INSTALL_PREFIX}/ssl" \
    --with-zlib-include="${INSTALL_PREFIX}/include" \
    --with-zlib-lib="${INSTALL_PREFIX}/lib" \
    no-shared \
    no-async \
    no-engine \
    no-dso \
    no-tests \
    -mcpu=cortex-a15 -mfpu=neon-vfpv4 -mfloat-abi=hard
make -j"${NPROC}"
make install_sw

# ── Step 4: Build c-ares (cross) ───────────────────────────────────────
echo "=== Step 4/9: Building c-ares ${CARES_VERSION} ==="
cd /tmp/src
wget -q "https://github.com/c-ares/c-ares/releases/download/v${CARES_VERSION}/c-ares-${CARES_VERSION}.tar.gz"
tar xf "c-ares-${CARES_VERSION}.tar.gz"
cmake -S "c-ares-${CARES_VERSION}" -B build-cares -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCARES_STATIC=ON \
    -DCARES_SHARED=OFF \
    -DCARES_BUILD_TOOLS=OFF
cmake --build build-cares -j"${NPROC}"
cmake --install build-cares

# ── Step 5: Build Abseil (cross) ───────────────────────────────────────
echo "=== Step 5/9: Building Abseil ${ABSEIL_VERSION} ==="
cd /tmp/src
wget -q "https://github.com/abseil/abseil-cpp/releases/download/${ABSEIL_VERSION}/abseil-cpp-${ABSEIL_VERSION}.tar.gz"
tar xf "abseil-cpp-${ABSEIL_VERSION}.tar.gz"
cmake -S "abseil-cpp-${ABSEIL_VERSION}" -B build-abseil -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DABSL_BUILD_TESTING=OFF \
    -DABSL_PROPAGATE_CXX_STD=ON \
    -DBUILD_SHARED_LIBS=OFF
cmake --build build-abseil -j"${NPROC}"
cmake --install build-abseil

# ── Step 6: Build RE2 (cross) ──────────────────────────────────────────
echo "=== Step 6/9: Building RE2 ${RE2_VERSION} ==="
cd /tmp/src
wget -q "https://github.com/google/re2/releases/download/${RE2_VERSION}/re2-${RE2_VERSION}.tar.gz"
tar xf "re2-${RE2_VERSION}.tar.gz"
cmake -S "re2-${RE2_VERSION}" -B build-re2 -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DCMAKE_PREFIX_PATH="${INSTALL_PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=17 \
    -DRE2_BUILD_TESTING=OFF \
    -DBUILD_SHARED_LIBS=OFF
cmake --build build-re2 -j"${NPROC}"
cmake --install build-re2

# ── Step 7: Build Protobuf (cross + native host protoc) ────────────────
echo "=== Step 7/9: Building Protobuf ${PROTOBUF_VERSION} ==="
cd /tmp/src

# protobuf releases strip the major API version prefix (e.g., "5.29.5" → tag "v29.5")
PROTOBUF_RELEASE_VERSION="${PROTOBUF_VERSION#*.}"
PROTOBUF_TAG="v${PROTOBUF_RELEASE_VERSION}"
wget -q "https://github.com/protocolbuffers/protobuf/releases/download/${PROTOBUF_TAG}/protobuf-${PROTOBUF_RELEASE_VERSION}.tar.gz"
tar xf "protobuf-${PROTOBUF_RELEASE_VERSION}.tar.gz"
PROTOBUF_SRC="protobuf-${PROTOBUF_RELEASE_VERSION}"

# 7a: Build host abseil (native x86_64, needed for host protoc + grpc_cpp_plugin)
cmake -S "abseil-cpp-${ABSEIL_VERSION}" -B build-abseil-host -G Ninja \
    -DCMAKE_INSTALL_PREFIX="${HOST_PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DABSL_BUILD_TESTING=OFF \
    -DABSL_PROPAGATE_CXX_STD=ON \
    -DBUILD_SHARED_LIBS=OFF
cmake --build build-abseil-host -j"${NPROC}"
cmake --install build-abseil-host

# 7b: Build host RE2 (native x86_64, needed for host gRPC)
cmake -S "re2-${RE2_VERSION}" -B build-re2-host -G Ninja \
    -DCMAKE_INSTALL_PREFIX="${HOST_PREFIX}" \
    -DCMAKE_PREFIX_PATH="${HOST_PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=17 \
    -DRE2_BUILD_TESTING=OFF \
    -DBUILD_SHARED_LIBS=OFF
cmake --build build-re2-host -j"${NPROC}"
cmake --install build-re2-host

# 7c: Build host c-ares (native x86_64)
cmake -S "c-ares-${CARES_VERSION}" -B build-cares-host -G Ninja \
    -DCMAKE_INSTALL_PREFIX="${HOST_PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCARES_STATIC=ON \
    -DCARES_SHARED=OFF \
    -DCARES_BUILD_TOOLS=OFF
cmake --build build-cares-host -j"${NPROC}"
cmake --install build-cares-host

# 7d: Build host protoc (native x86_64)
cmake -S "${PROTOBUF_SRC}" -B build-protobuf-host -G Ninja \
    -DCMAKE_INSTALL_PREFIX="${HOST_PREFIX}" \
    -DCMAKE_PREFIX_PATH="${HOST_PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=17 \
    -Dprotobuf_BUILD_TESTS=OFF \
    -Dprotobuf_BUILD_EXAMPLES=OFF \
    -Dprotobuf_BUILD_PROTOBUF_BINARIES=ON \
    -Dprotobuf_BUILD_PROTOC_BINARIES=ON \
    -Dprotobuf_BUILD_SHARED_LIBS=OFF \
    -Dprotobuf_ABSL_PROVIDER=package \
    -Dprotobuf_WITH_ZLIB=ON
cmake --build build-protobuf-host -j"${NPROC}"
cmake --install build-protobuf-host

# 7e: Cross-compile protobuf runtime (ARM)
cmake -S "${PROTOBUF_SRC}" -B build-protobuf-cross -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DCMAKE_PREFIX_PATH="${INSTALL_PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=17 \
    -Dprotobuf_BUILD_TESTS=OFF \
    -Dprotobuf_BUILD_EXAMPLES=OFF \
    -Dprotobuf_BUILD_PROTOBUF_BINARIES=ON \
    -Dprotobuf_BUILD_PROTOC_BINARIES=OFF \
    -Dprotobuf_BUILD_SHARED_LIBS=OFF \
    -Dprotobuf_ABSL_PROVIDER=package \
    -Dprotobuf_WITH_ZLIB=ON
cmake --build build-protobuf-cross -j"${NPROC}"
cmake --install build-protobuf-cross

# ── Step 8: Build gRPC (cross + native plugins) ────────────────────────
echo "=== Step 8/9: Building gRPC ${GRPC_VERSION} ==="
cd /tmp/src
GRPC_TAG="v${GRPC_VERSION}"
wget -q "https://github.com/grpc/grpc/archive/refs/tags/${GRPC_TAG}.tar.gz" -O "grpc-${GRPC_VERSION}.tar.gz"
tar xf "grpc-${GRPC_VERSION}.tar.gz"

# 8a: Build native gRPC plugins (grpc_cpp_plugin needed for code generation)
cmake -S "grpc-${GRPC_TAG#v}" -B build-grpc-host -G Ninja \
    -DCMAKE_INSTALL_PREFIX="${HOST_PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=17 \
    -DgRPC_INSTALL=ON \
    -DgRPC_BUILD_TESTS=OFF \
    -DgRPC_BUILD_CSHARP_EXT=OFF \
    -DgRPC_BUILD_GRPC_CSHARP_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_NODE_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_OBJECTIVE_C_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_PHP_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_PYTHON_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_RUBY_PLUGIN=OFF \
    -DgRPC_ABSL_PROVIDER=package \
    -DgRPC_CARES_PROVIDER=package \
    -DgRPC_PROTOBUF_PROVIDER=package \
    -DgRPC_RE2_PROVIDER=package \
    -DgRPC_SSL_PROVIDER=package \
    -DgRPC_ZLIB_PROVIDER=package \
    -DCMAKE_PREFIX_PATH="${HOST_PREFIX}" \
    -DBUILD_SHARED_LIBS=OFF
cmake --build build-grpc-host -j"${NPROC}"
cmake --install build-grpc-host

# 8b: Cross-compile gRPC runtime
cmake -S "grpc-${GRPC_TAG#v}" -B build-grpc-cross -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DCMAKE_PREFIX_PATH="${INSTALL_PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=17 \
    -DgRPC_INSTALL=ON \
    -DgRPC_BUILD_TESTS=OFF \
    -DgRPC_BUILD_CODEGEN=OFF \
    -DgRPC_BUILD_CSHARP_EXT=OFF \
    -DgRPC_BUILD_GRPC_CSHARP_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_CPP_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_NODE_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_OBJECTIVE_C_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_PHP_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_PYTHON_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_RUBY_PLUGIN=OFF \
    -DgRPC_ABSL_PROVIDER=package \
    -DgRPC_CARES_PROVIDER=package \
    -DgRPC_PROTOBUF_PROVIDER=package \
    -DgRPC_RE2_PROVIDER=package \
    -DgRPC_SSL_PROVIDER=package \
    -DgRPC_ZLIB_PROVIDER=package \
    -DProtobuf_PROTOC_EXECUTABLE="${HOST_PREFIX}/bin/protoc" \
    -DBUILD_SHARED_LIBS=OFF
cmake --build build-grpc-cross -j"${NPROC}"
cmake --install build-grpc-cross

# ── Step 9: Package ────────────────────────────────────────────────────
echo "=== Step 9/9: Packaging ==="
ARTIFACT_NAME="grpc-${ARTIFACT_TUPLE}"

# Copy native host tools into the artifact
mkdir -p "${INSTALL_PREFIX}/bin"
cp "${HOST_PREFIX}/bin/protoc"          "${INSTALL_PREFIX}/bin/"
cp "${HOST_PREFIX}/bin/grpc_cpp_plugin" "${INSTALL_PREFIX}/bin/"

cd /opt
mv grpc-arm "${ARTIFACT_NAME}"

# Remove unnecessary files
rm -rf "${ARTIFACT_NAME}/lib/pkgconfig"

tar czf "/output/${ARTIFACT_NAME}.tar.gz" "${ARTIFACT_NAME}"
cd /output
sha256sum "${ARTIFACT_NAME}.tar.gz" > "${ARTIFACT_NAME}.tar.gz.sha256"

echo "=== Done! ==="
echo "Artifact:  /output/${ARTIFACT_NAME}.tar.gz"
echo "Checksum:  /output/${ARTIFACT_NAME}.tar.gz.sha256"
ls -lh /output/
