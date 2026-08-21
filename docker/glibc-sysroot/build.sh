#!/bin/sh
# Rebuilds gm/armv7l-linux-gnueabihf-sysroot/armv7l-linux-gnueabihf-sysroot.tgz.
#
# Run this when the sysroot needs regenerating. The committed tarball is the
# artifact consumers download; this script is how it was produced.
#
#     sh docker/glibc-sysroot/build.sh
#
# Requires Docker. Writes the tarball and its checksum into the gm/ tree.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT="$ROOT/gm/armv7l-linux-gnueabihf-sysroot"

mkdir -p "$OUT"
docker build -t pmas-glibc-sysroot "$HERE"

docker run --rm -v "$OUT:/out" pmas-glibc-sysroot bash -c '
set -e
SR=/usr/arm-linux-gnueabihf
GCCDIR=$(dirname $(arm-linux-gnueabihf-gcc -print-libgcc-file-name))
DEST=/tmp/p/armv7l-linux-gnueabihf-sysroot
rm -rf /tmp/p
mkdir -p $DEST/lib $DEST/include

# Dereference every symlink. Windows cannot create symlinks without elevated
# privileges, and tar aborts the whole extraction when it tries.
cp -aL $SR/lib/. $DEST/lib/ 2>/dev/null || true
cp -aL $SR/include/. $DEST/include/ 2>/dev/null || true
cp -aL $GCCDIR/libgcc.a $GCCDIR/libgcc_eh.a $GCCDIR/crtbegin*.o $GCCDIR/crtend*.o $DEST/lib/

# -lgcc_s searches for libgcc_s.so. Debian ships only the versioned file in the
# sysroot and reaches the unversioned name through a symlink from the gcc
# directory, which the dereferencing above does not reproduce.
cp -aL $GCCDIR/libgcc_s.so.1 $DEST/lib/libgcc_s.so

# Debian writes these as ld scripts holding absolute paths, which do not survive
# relocation to ext/toolchains. Rewrite them to bare names, resolved from the
# library search path.
for f in libc.so libpthread.so libm.so; do
  [ -f "$DEST/lib/$f" ] || continue
  sed -i "s|/usr/arm-linux-gnueabihf/lib/||g; s|/lib/arm-linux-gnueabihf/||g; s|/usr/lib/arm-linux-gnueabihf/||g" "$DEST/lib/$f"
done

test "$(find $DEST -type l | wc -l)" -eq 0 || { echo "symlinks remain"; exit 1; }
for f in Scrt1.o crt1.o crti.o crtn.o crtbeginS.o crtendS.o libc.so libc.so.6 libgcc.a libgcc_s.so; do
  test -e "$DEST/lib/$f" || { echo "missing $f"; exit 1; }
done

cd /tmp/p && tar czf /out/armv7l-linux-gnueabihf-sysroot.tgz armv7l-linux-gnueabihf-sysroot
'

sha256sum "$OUT/armv7l-linux-gnueabihf-sysroot.tgz" \
  | awk '{print toupper($1)}' > "$OUT/armv7l-linux-gnueabihf-sysroot.tgz.sha256"

echo "Wrote $OUT/armv7l-linux-gnueabihf-sysroot.tgz"
echo "SHA256: $(cat "$OUT/armv7l-linux-gnueabihf-sysroot.tgz.sha256")"
echo "Update LINUX_SYSROOT_SHA256 and WIN_SYSROOT_SHA256 in makefile/Makefile-pmas-glibc.toml."
