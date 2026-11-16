#!/bin/bash
# Runs inside the gmas-cc image. See README.md.
#
#   /orig  read-only: the Cygwin gmas-cc-linux-ppc 4.1.0-gm001 package root
#   /out   receives the package tree and tarball
#   /work  scratch; a stage whose stamp exists is skipped, so a failed build
#          resumes where it stopped when /work is a persistent volume
set -euo pipefail

TARGET=powerpc-603e-linux-gnu
HOST=i686-w64-mingw32
BUILD=x86_64-pc-linux-gnu
# Kept identical to the original so that gcc's relocation logic and every path
# the Cygwin build embedded resolve the same way.
PREFIX=/opt/crosstool/gcc-4.1.0-glibc-2.3.6/$TARGET
SYSROOT=$PREFIX/$TARGET
ORIG=/orig/opt/crosstool/gcc-4.1.0-glibc-2.3.6/$TARGET
PKG_NAME=${PKG_NAME:-gmas-cc-linux-ppc_4.1.0-gm003}
JOBS=${JOBS:-$(nproc)}
W=/work
STAGE2=$W/stage2-root

export PATH=$PREFIX/bin:$PATH
# gcc 4.1's configure only accepts makeinfo 4.2-4.x; without one it skips the
# manuals, which the package does not ship anyway.
export MAKEINFO=missing

stage() { [ -f "$W/.done-$1" ]; }
done_() { touch "$W/.done-$1"; echo "=== stage $1 done"; }

# Stage 1 installs into $PREFIX; keep it in /work so a resumed run finds it.
mkdir -p $W/opt-crosstool /opt
ln -sfn $W/opt-crosstool /opt/crosstool

# Target files are PowerPC objects and identical whatever the host, so they are
# taken from the Cygwin package unchanged rather than rebuilt. That keeps glibc,
# libgcc and libstdc++ bit-identical to what the controller and the ELMO
# libraries were built against.
if ! stage sysroot; then
    test -d "$ORIG/$TARGET/lib" || { echo "/orig is not a gmas-cc-linux-ppc package root"; exit 1; }
    rm -rf $W/orig
    python3 /src/materialize.py "$ORIG" $W/orig
    rm -rf $PREFIX && mkdir -p $SYSROOT
    cp -a $W/orig/$TARGET/include $W/orig/$TARGET/lib $SYSROOT/
    done_ sysroot
fi

if ! stage src; then
    rm -rf $W/src && mkdir -p $W/src && cd $W/src
    tar xjf /src/gcc-4.1.0.tar.bz2
    tar xjf /src/binutils-2.16.1.tar.bz2
    for p in /src/patches/gcc-4.1.0/*.patch; do patch -d gcc-4.1.0 -p1 -s < "$p"; done
    for p in /src/patches/binutils-2.16.1/*.patch; do patch -d binutils-2.16.1 -p1 -s < "$p"; done
    done_ src
fi

BINUTILS_CONF="--target=$TARGET --prefix=$PREFIX --disable-nls --disable-werror --with-sysroot=$SYSROOT"
# Matches the "Configured with" line of the Cygwin compiler.
GCC_CONF="--target=$TARGET --prefix=$PREFIX --with-cpu=603e --enable-cxx-flags=-mcpu=603e \
  --with-headers=$SYSROOT/include --with-local-prefix=$SYSROOT --disable-nls \
  --enable-threads=posix --enable-symvers=gnu --enable-__cxa_atexit \
  --enable-languages=c,c++ --enable-shared --enable-c99 --enable-long-long"

# Stage 1: a Linux-hosted cross compiler. A Canadian cross needs one on the
# build machine to compile target code, and it doubles as a reference the
# Windows build can be compared against.
if ! stage binutils-linux; then
    rm -rf $W/b-binutils-linux && mkdir -p $W/b-binutils-linux && cd $W/b-binutils-linux
    $W/src/binutils-2.16.1/configure --build=$BUILD --host=$BUILD $BINUTILS_CONF
    make -j$JOBS all-binutils all-gas all-ld
    make install-binutils install-gas install-ld
    done_ binutils-linux
fi

if ! stage gcc-linux; then
    rm -rf $W/b-gcc-linux && mkdir -p $W/b-gcc-linux && cd $W/b-gcc-linux
    $W/src/gcc-4.1.0/configure --build=$BUILD --host=$BUILD $GCC_CONF
    make -j$JOBS all-gcc
    make install-gcc
    done_ gcc-linux
fi

# Stage 2: the same sources hosted on Win32. Statically linked so the package
# carries no MinGW runtime DLLs, and with longpath.o, which lifts msvcrt's
# MAX_PATH limit on file names (see longpath.c). The 2.13-era top-level
# configure scripts drop LDFLAGS, and passing it to make also reaches the
# build-machine programs, so a compiler wrapper adds both to host links only.
LONGPATH_O=$W/longpath.o
$HOST-gcc -O2 -Wall -Werror -c /src/longpath.c -o $LONGPATH_O
mkdir -p $W/bin
cat > $W/bin/$HOST-gcc-lp <<EOF
#!/bin/sh
for a; do case \$a in -c|-S|-E) exec $HOST-gcc "\$@" ;; esac; done
exec $HOST-gcc "\$@" -static $LONGPATH_O
EOF
chmod +x $W/bin/$HOST-gcc-lp
MINGW_ENV="CC=$W/bin/$HOST-gcc-lp CXX=$HOST-g++ AR=$HOST-ar RANLIB=$HOST-ranlib CC_FOR_BUILD=gcc"

if ! stage binutils-win; then
    rm -rf $W/b-binutils-win && mkdir -p $W/b-binutils-win && cd $W/b-binutils-win
    env $MINGW_ENV $W/src/binutils-2.16.1/configure --build=$BUILD --host=$HOST $BINUTILS_CONF
    make -j$JOBS all-binutils all-gas all-ld
    make DESTDIR=$STAGE2 install-binutils install-gas install-ld
    done_ binutils-win
fi

if ! stage gcc-win; then
    rm -rf $W/b-gcc-win && mkdir -p $W/b-gcc-win && cd $W/b-gcc-win
    env $MINGW_ENV $W/src/gcc-4.1.0/configure --build=$BUILD --host=$HOST $GCC_CONF
    make -j$JOBS all-build-libiberty || true
    make -j$JOBS all-gcc
    make DESTDIR=$STAGE2 install-gcc
    done_ gcc-win
fi

# Assemble: Win32 host programs from stage 2, target files from the original.
rm -rf /out/$PKG_NAME
DEST=/out/$PKG_NAME/opt/crosstool/gcc-4.1.0-glibc-2.3.6/$TARGET
mkdir -p $DEST
cp -a $STAGE2$PREFIX/. $DEST/
rm -rf $DEST/share $DEST/info $DEST/man $DEST/$TARGET/lib $DEST/$TARGET/include
# gcc 4.1 locates cc1 and its libraries relative to $prefix/bin only, so the
# driver copies in $TARGET/bin cannot relocate; ship the prefixed drivers.
rm -f $DEST/$TARGET/bin/gcc.exe $DEST/$TARGET/bin/g++.exe $DEST/$TARGET/bin/c++.exe \
      $DEST/bin/$TARGET-gcc-4.1.0 $DEST/bin/$TARGET-gccbug
rm -rf $DEST/libexec/gcc/$TARGET/4.1.0/install-tools
# PowerPC glibc utilities (gencat, iconv, ...) live in $TARGET/bin in the
# original; they cannot run on Windows, and the Cygwin package shipped them by
# accident of layout.
cp -a $W/orig/$TARGET/include $W/orig/$TARGET/lib $DEST/$TARGET/
GCCLIB=lib/gcc/$TARGET/4.1.0
rm -rf $DEST/$GCCLIB/include
for f in $W/orig/$GCCLIB/*; do
    case "$(basename "$f")" in install-tools) continue ;; esac
    rm -rf "$DEST/$GCCLIB/$(basename "$f")"
    cp -a "$f" $DEST/$GCCLIB/
done
rm -rf $DEST/include/c++
cp -a $W/orig/include/c++ $DEST/include/
# The libtool archives name the Cygwin prefix; nothing in this toolchain reads them.
find $DEST -name '*.la' -delete

# Fail rather than ship a package that still needs Cygwin.
if find $DEST -type f \( -name '*.exe' -o -name '*.dll' \) -exec file {} + | grep -v 'PE32 executable' | grep -q .; then
    echo "non-Win32 host binaries in the package"; exit 1
fi
if grep -rlI --include='*.exe' cygwin1.dll $DEST; then echo "cygwin1.dll referenced"; exit 1; fi
for f in $(find $DEST -name '*.exe'); do
    grep -q gmas-longpath "$f" || { echo "$f lacks longpath.o"; exit 1; }
done
test "$(find $DEST -type l | wc -l)" -eq 0 || { echo "symlinks remain"; exit 1; }

cat > /out/$PKG_NAME/cpp-env.json <<'EOF'
{
    "env": {
        "AR": [
            "./opt/crosstool/gcc-4.1.0-glibc-2.3.6/powerpc-603e-linux-gnu/powerpc-603e-linux-gnu/bin/ar.exe"
        ],
        "AR_VERSION": "2.16.1",
        "CC": [
            "./opt/crosstool/gcc-4.1.0-glibc-2.3.6/powerpc-603e-linux-gnu/bin/powerpc-603e-linux-gnu-gcc.exe"
        ],
        "CC_VERSION": "4.1.0",
        "CXX": [
            "./opt/crosstool/gcc-4.1.0-glibc-2.3.6/powerpc-603e-linux-gnu/bin/powerpc-603e-linux-gnu-g++.exe"
        ],
        "CXX_VERSION": "4.1.0",
        "GMAS_CC_ROOT": [
            "./opt/crosstool/gcc-4.1.0-glibc-2.3.6/powerpc-603e-linux-gnu"
        ],
        "OBJDUMP": [
            "./opt/crosstool/gcc-4.1.0-glibc-2.3.6/powerpc-603e-linux-gnu/bin/powerpc-603e-linux-gnu-objdump.exe"
        ],
        "OBJDUMP_VERSION": "2.16.1",
        "Path": [
            "./opt/crosstool/gcc-4.1.0-glibc-2.3.6/powerpc-603e-linux-gnu/powerpc-603e-linux-gnu/bin",
            "./opt/crosstool/gcc-4.1.0-glibc-2.3.6/powerpc-603e-linux-gnu/bin"
        ]
    },
    "name": "gmas-cc-linux-ppc",
    "version": "4.1.0"
}
EOF

cd /out && tar czf $PKG_NAME.tar.gz $PKG_NAME
sha256sum $PKG_NAME.tar.gz | awk '{print toupper($1)}' > $PKG_NAME.tar.gz.sha256
echo "Wrote /out/$PKG_NAME.tar.gz"
