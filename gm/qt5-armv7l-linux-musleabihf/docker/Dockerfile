# Build Qt5 Core+Network static libraries for ARM Linux musl (armv7l-unknown-linux-musleabihf).
#
# Uses a prebuilt musl.cc cross-compiler for simplicity and reproducibility.
# The resulting artifact is intended for Windows-hosted cross-compilation using the
# GCC 15.2.0 Canadian cross-compiler from grab.toml. It includes:
#   - ARM musl static libraries (libQt5Core.a, libQt5Network.a)
#   - Qt headers (QtCore/, QtNetwork/)
#   - CMake config files
#   - Windows host tools (moc.exe + dependencies) for AUTOMOC support

FROM debian:bookworm-slim

ARG qt_version=5.15.2

ENV TZ="UTC" \
    DEBIAN_FRONTEND="noninteractive" \
    QT_VERSION=${qt_version}

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    perl \
    python3 \
    python3-pip \
    wget \
    xz-utils \
    zip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install aqtinstall (downloads prebuilt Windows Qt for moc.exe)
RUN pip3 install --break-system-packages aqtinstall

# Download prebuilt musl.cc cross-compiler (GCC, armv7l, hard float, musl)
# ABI-compatible with the GCC 15.2 Canadian cross (same musl, float ABI, arch)
RUN cd /opt && \
    wget -q "https://musl.cc/armv7l-linux-musleabihf-cross.tgz" && \
    tar xf armv7l-linux-musleabihf-cross.tgz && \
    rm armv7l-linux-musleabihf-cross.tgz

ENV PATH="/opt/armv7l-linux-musleabihf-cross/bin:${PATH}"

# Copy custom mkspec and entrypoint
COPY mkspecs/ /mkspecs/
COPY --chmod=755 entrypoint.sh /entrypoint.sh

CMD ["/entrypoint.sh"]
