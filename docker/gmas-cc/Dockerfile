# Builds the GMAS cross compiler (gcc 4.1.0, binutils 2.16.1, target
# powerpc-603e-linux-gnu) as native Win32 executables, with no Cygwin.
#
# Debian 8 carries gcc 4.9 and mingw-w64 4.9, which still compile gcc 4.1 and
# binutils 2.16 without patching their sources: gcc 5 switched the default C
# dialect to gnu11, which changes the meaning of the `extern inline` these
# sources rely on.
FROM debian/eol:jessie

# The base image already carries jessie-security package versions, so both
# archives are needed to keep apt's dependency resolution consistent.
RUN printf '%s\n' \
      'deb http://archive.debian.org/debian jessie main' \
      'deb http://archive.debian.org/debian-security jessie/updates main' \
      > /etc/apt/sources.list \
 && apt-get -o Acquire::Check-Valid-Until=false update -qq \
 && apt-get install -y --no-install-recommends \
      build-essential bison flex m4 patch bzip2 xz-utils file python3 \
      ca-certificates curl \
      gcc-mingw-w64-i686 g++-mingw-w64-i686 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
# Jessie's CA bundle no longer validates ftp.gnu.org, so the checksums below
# are what authenticates the downloads.
RUN curl -sSfLk -O https://ftp.gnu.org/gnu/gcc/gcc-4.1.0/gcc-4.1.0.tar.bz2 \
 && curl -sSfLk -O https://ftp.gnu.org/gnu/binutils/binutils-2.16.1.tar.bz2 \
 && printf '%s\n' \
      '1159457a0e4c054b709547ae21ff624aebab2033e0d9e5bf46c9cf88b1970606  gcc-4.1.0.tar.bz2' \
      'd78a6ff982ab2f73721706e7bfd3285ac647804664e7ea4786e66d01f91c56c5  binutils-2.16.1.tar.bz2' \
    | sha256sum -c -

COPY patches /src/patches
COPY materialize.py build-in-container.sh longpath.c /src/

WORKDIR /work
