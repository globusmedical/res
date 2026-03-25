# Build gRPC + protobuf static libraries for ARM Linux musl (armv7l-unknown-linux-musleabihf).
#
# Uses the same prebuilt musl.cc cross-compiler as the Qt5 build.
# The resulting artifact is intended for Windows-hosted cross-compilation using the
# GCC Canadian cross-compiler from grab. It includes:
#   - ARM musl static libraries (libgrpc++.a, libprotobuf.a, etc.)
#   - Headers (grpcpp/, google/protobuf/, absl/, etc.)
#   - CMake config files for find_package()
#   - Linux-native protoc + grpc_cpp_plugin (for code generation at build time)

FROM debian:bookworm-slim

# Pinned versions matching the API repo (globusmedical/api) vcpkg overrides
ARG GRPC_VERSION=1.71.0
ARG PROTOBUF_VERSION=5.29.5
ARG ABSEIL_VERSION=20240722.0
ARG CARES_VERSION=1.34.5
ARG RE2_VERSION=2025-11-05
ARG OPENSSL_VERSION=3.5.0
ARG ZLIB_VERSION=1.3.1

ENV TZ="UTC" \
    DEBIAN_FRONTEND="noninteractive"

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    git \
    libssl-dev \
    ninja-build \
    pkg-config \
    python3 \
    wget \
    xz-utils \
    zlib1g-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Download prebuilt musl.cc cross-compiler (same as Qt5 build)
RUN cd /opt && \
    wget -q "https://musl.cc/armv7l-linux-musleabihf-cross.tgz" && \
    tar xf armv7l-linux-musleabihf-cross.tgz && \
    rm armv7l-linux-musleabihf-cross.tgz

ENV CROSS_PREFIX="armv7l-linux-musleabihf" \
    CROSS_ROOT="/opt/armv7l-linux-musleabihf-cross" \
    PATH="/opt/armv7l-linux-musleabihf-cross/bin:${PATH}"

ENV SYSROOT="${CROSS_ROOT}/${CROSS_PREFIX}/sysroot"

# Copy the cross-compilation toolchain file and entrypoint
COPY arm-linux-musleabihf.cmake /toolchain.cmake
COPY --chmod=755 entrypoint.sh /entrypoint.sh

CMD ["/entrypoint.sh"]
