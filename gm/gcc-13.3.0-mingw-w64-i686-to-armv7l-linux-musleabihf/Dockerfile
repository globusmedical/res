FROM ubuntu:20.04

# Host: mingw-w64-i686 (Windows 64-bit)
# Target: arm-none-linux-gnueabihf
ARG gcc_version_3="11.2.0"
ARG gcc_version_2="11.2"
ARG toolchain_version="${gcc_version_2}-2022.02"
ARG host="mingw-w64-i686"
ARG target="arm-none-linux-gnueabihf"
ARG toolchain_id="gcc-arm-${toolchain_version}-${host}-${target}"
ARG musl_output="/opt/musl-toolchain"
ARG musl_target="arm-unknown-linux-musleabihf"
ARG musl_toolchain_id="gcc-arm-${toolchain_version}-${host}-${musl_target}"

ENV toolchain_url="https://developer.arm.com/-/media/Files/downloads/gnu/${toolchain_version}/binrel/${toolchain_id}.zip"

ENV TZ="UTC" \
    DEBIAN_FRONTEND="noninteractive"

    # Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        file \
        git \
        python3 \
        wget && \
    rm -rf /var/lib/apt/lists/*

# Fetch musl-cross-make
WORKDIR /tmp
RUN git clone --depth 1 https://github.com/richfelker/musl-cross-make.git
WORKDIR /tmp/musl-cross-make

# Configure musl-cross-make
RUN sed -i "s/GCC_VER = .*/GCC_VER = ${gcc_version_3}/" Makefile && \
    echo "TARGET=${musl_target}" > config.mak && \
    echo "OUTPUT=${musl_output}" >> config.mak && \
    echo "STRIP_OPTS=--strip-all" >> config.mak && \
    make -j$(nproc) && \
    make install

# install unzip
RUN apt-get update && apt-get install -y unzip && rm -rf /var/lib/apt/lists/*

# Download w64-mingw32 glibc based cross compiler
WORKDIR /opt
RUN curl -L -o ${toolchain_id}.zip ${toolchain_url} && \
    unzip ${toolchain_id}.zip && \
    rm ${toolchain_id}.zip

# Convert to musl-based toolchain
ENV musl_toolchain_id="${toolchain_id/-gnueabihf/-musleabihf}"

USER root

RUN cp -r /opt/${toolchain_id} /opt/${musl_toolchain_id} && \
    rm -rf /opt/${musl_toolchain_id}/libc && \
    cp -r /opt/musl-toolchain /opt/${musl_toolchain_id}/libc && \
    find /opt/${musl_toolchain_id} -type f -name '*.specs' -exec sed -i \
        "s|${target}|arm-none-linux-musleabihf|g" {} \; && \
    for bin in /opt/${musl_toolchain_id}/bin/${target}-*; do \
        mv "$bin" "$(echo $bin | sed 's/gnueabihf/musleabihf/')"; \
    done

# Package the musl-based toolchain
RUN cd /opt && \
    tar cvzf ${musl_toolchain_id}.tar.gz ${musl_toolchain_id}

# Provide a default command to export the package during runtime
CMD ["sh", "-c", "mv /tmp/ ${musl_toolchain_id}.tar.gz /output/ && echo 'Package exported to /output'"]

