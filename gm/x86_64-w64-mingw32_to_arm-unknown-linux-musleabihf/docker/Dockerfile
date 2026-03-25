# Use a base image with necessary build tools
FROM debian:bookworm-slim

ARG crosstool_ng_version=1.28.0

ENV TZ="UTC" \
    DEBIAN_FRONTEND="noninteractive"

# Install required dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    automake \
    bison \
    build-essential \
    ca-certificates \
    curl \
    file \
    flex \
    gawk \
    git \
    gperf \
    gzip \
    help2man \
    libncurses5-dev \
    libtool \
    libtool-bin \
    mingw-w64 \
    python3 \
    rsync \
    tar \
    texinfo \
    unzip \
    wget \
    xz-utils \
    zip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Define environment variables for directories
ENV PREFIX=/opt/cross
ENV TARGET=arm-none-linux-musleabihf
ENV PATH=$PREFIX/bin:$PATH

# Create necessary directories
WORKDIR /usr/src

# Download and compile crosstool-NG.
RUN wget http://crosstool-ng.org/download/crosstool-ng/crosstool-ng-${crosstool_ng_version}.tar.xz 2>&1 &&\
    tar xf crosstool-ng-*.tar* && \
    cd crosstool-ng-${crosstool_ng_version} &&\
    ./configure && make && make install &&\
    rm -rf ../crosstool-ng*

COPY fix_filename_cases.py /fix_filename_cases.py
COPY --chmod=755 entrypoint.sh /entrypoint.sh
RUN useradd -ms /bin/bash build
USER build
WORKDIR /home/build
COPY ct-ng-config.ini .config
RUN ct-ng upgradeconfig && yes "" | ct-ng oldconfig

# Run entrypoint as root so it can write to the volume mount
USER root

# Set the default shell
CMD ["/entrypoint.sh"]

