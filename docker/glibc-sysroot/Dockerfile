# Cross toolchain for armv7-unknown-linux-gnueabihf against a glibc sysroot the
# PMAS can run.
#
# Debian 9 carries glibc 2.24, inside the 2.17 to 2.25 window that Rust and the
# controller set between them. Debian 12 would give glibc 2.36, and 2.34 merged
# libpthread into libc, so a binary built there requires GLIBC_2.34 and cannot
# run on the controller.
FROM debian/eol:stretch

RUN sed -i 's|deb.debian.org|archive.debian.org|g; s|security.debian.org|archive.debian.org|g; /stretch-updates/d' /etc/apt/sources.list \
 && apt-get -o Acquire::Check-Valid-Until=false update -qq \
 && apt-get install -y --no-install-recommends \
      gcc-arm-linux-gnueabihf \
      libc6-dev-armhf-cross \
      ca-certificates curl xz-utils build-essential pkg-config \
 && rm -rf /var/lib/apt/lists/*

# Pinned to match rust-toolchain.toml in rs-gm_mctrl.
ARG RUST_VERSION=1.97.1
ENV RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo PATH=/opt/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --profile minimal --default-toolchain ${RUST_VERSION} \
        --target armv7-unknown-linux-gnueabihf

ENV CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc \
    CC_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc \
    AR_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-ar

WORKDIR /work
