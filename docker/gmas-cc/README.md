# GMAS cross compiler without Cygwin

`gmas-cc-linux-ppc_4.1.0-gm002` is the ELMO GMAS cross compiler (gcc 4.1.0,
binutils 2.16.1, glibc 2.3.6, target `powerpc-603e-linux-gnu`) built as
native, statically linked Win32 programs. It needs no Cygwin and no
`cygwin1.dll`, and it is a drop-in replacement for `gm001`.

## What changes and what does not

Only the host programs are rebuilt: the drivers, `cc1`, `cc1plus`, `collect2`,
and binutils. Every PowerPC file is copied unchanged from `gm001`, so glibc,
`crt*.o`, libgcc, libstdc++ and all headers stay bit-identical to what the
controller and the ELMO libraries were built against. Nothing on the GMAS
changes.

The compiler sources are the ones `gm001` was built from (crosstool-0.43), with
the same configure options and the same install prefix. The binaries it
produces are identical to `gm001` output; see [Verification](#verification).

## Building

```sh
sh docker/gmas-cc/build.sh <path-to-gmas-cc-linux-ppc_4.1.0-gm001>
```

The argument is the root of the `gm001` package, the folder holding
`cpp-env.json` and `opt/`. The build takes about 20 minutes and writes the
package tree, `gmas-cc-linux-ppc_4.1.0-gm002.tar.gz`, and its SHA-256 into
`out/`.

Stage results are kept in the `gmas-cc-work` Docker volume, so a failed build
resumes where it stopped. To rebuild a stage, delete its `/work/.done-<stage>`
stamp; to start from scratch, remove the volume. `JOBS` and `PKG_NAME` override
the parallelism and the package name.

The image is Debian 8 with mingw-w64. gcc 4.1 and binutils 2.16 do not compile
with gcc 5 or newer, and every source tarball is pinned by SHA-256 in the
`Dockerfile`.

## Using it

Point CMake at the prefixed drivers in `bin/`, as `cpp-env.json` does:

```text
opt/crosstool/gcc-4.1.0-glibc-2.3.6/powerpc-603e-linux-gnu/bin/powerpc-603e-linux-gnu-g++.exe
```

The unprefixed drivers in `powerpc-603e-linux-gnu/bin/` are not shipped. gcc
4.1 only finds `cc1` and its libraries relative to `$prefix/bin`, so those
copies cannot work from another location.

No `CYGWIN` environment variable, `/cygdrive` path handling, or retry around
hung compiler processes is needed.

## Patches

`patches/<package>/*.patch` are applied in name order with `patch -p1`.

| Patch | Purpose |
| --- | --- |
| `binutils-2.16.1/{bfd-hash-tweak,binutils-2.15-psignal,binutils-skip-comments,callahan,cross-gprof,stabs-tweak}` | crosstool-0.43 patches that `gm001` was built with |
| `gcc-4.1.0/gcc-4.1-fix-fixincl` | crosstool-0.43 patch that `gm001` was built with |
| `*/…-expandargv` | `@file` response files in the gcc driver, `as`, `ld` and `ar`. CMake uses them to link GMAS executables. Backported from libiberty |
| `gcc-4.1.0/gcc-4.1-mingw-dir-eacces` | Windows reports `EACCES` when opening a directory. Without this, `#include <string>` fails in any include path holding a `String` directory. Backported from gcc 4.3 |
| `*/…-host-qsort` | Uses newlib's `qsort` from Cygwin 1.7.1 instead of msvcrt's |

### Why the compiler needs Cygwin's `qsort`

gcc 4.1 sorts with comparators that return 0 for distinct elements, for
example stack slots of equal size. The order of such ties is whatever the host
`qsort` produces, and it decides stack layout and register allocation. With
msvcrt's `qsort`, 57 of 76 GPS objects compiled differently from `gm001`. With
the `qsort` that `gm001`'s `cygwin1.dll` carries, the code is identical.

## Verification

The `GMAS-R` and `GMAS-RD` presets of INR_DEV were built with `gm001` and with
this package from the same `compile_commands.json`:

- `CPP_GPS_Application` is byte-identical in `GMAS-R`, and identical after
  `objcopy --strip-debug` in `GMAS-RD`.
- All other objects are identical, except two in `GMAS-R` and one in `GMAS-RD`
  (`Logger.cpp`) where the `DW.ref.*` exception-personality sections are
  emitted in a different order.
- Debug information is identical apart from embedded paths: the toolchain
  location, the build directory, and `DW_AT_comp_dir`, which is a Windows path
  such as `C:\build\GMAS-RD` instead of `/cygdrive/c/build/GMAS-RD`.
- Static libraries differ only in their `ar` member timestamps.
- Repeated builds, including from other directories, produce identical output.

The `DW.ref` order comes from gcc sorting those symbols by heap address, so it
depends on the host `malloc`. The sections are hidden, weak, 4-byte pointers
that the linker merges, which is why the linked executables do not change.

A parallel `ninja -j32` build of `GMAS-RD` takes 5 seconds and was repeated
without failure. With `gm001`, a parallel build fails intermittently with
`execvp: No such file or directory` or hangs in `g++`.

## Limitations

- `gdb` is not included.
- `collect2` does not accept response files, so a link line is still limited
  to Windows' 32 KB command line once the driver expands it.
- `ar` from binutils 2.16 has no deterministic mode.
