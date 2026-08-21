# glibc sysroot for the PMAS

`gm/armv7l-linux-gnueabihf-sysroot/armv7l-linux-gnueabihf-sysroot.tgz` lets you
build `armv7-unknown-linux-gnueabihf` for the ELMO PMAS. It is 6.7 MB, and it
contains no compiler.

## Why a sysroot and not a toolchain

Rust links this target through a C compiler driver by default, but `rust-lld`
ships with every Rust toolchain and can do the job directly. Given a sysroot, a
pure-Rust build needs no host C compiler at all, and the same sysroot works on
Windows and on Linux. That is why this is 6.7 MB rather than the several hundred
a cross toolchain costs.

Crates that build C sources still need a cross compiler. Set `GM_MCTRL_GLIBC_CC`
to one whose sysroot is glibc 2.25 or older; the Dockerfile here provides one.

## The version window

The sysroot must carry glibc **2.17 through 2.25**.

| Bound | Set by |
| --- | --- |
| 2.16 or newer | Rust 1.78 calls `libc::getauxval` in `stack_overflow.rs` |
| 2.17 or newer | Rust's minimum for `armv7-unknown-linux-gnueabihf` |
| 2.25 or older | The controller runs glibc 2.25, and a dynamic binary needs the target's glibc to be at least as new as the build sysroot |

Nothing in the Elmo SDK narrows the window. `libMMC_APP_LIB.so` requires at most
`GLIBC_2.4` and `libEIP.so` at most `GLIBC_2.7`, and a symbol version
requirement is a floor rather than a cap.

Debian 9 sits at glibc 2.24 and needs no configuration, which is what the
Dockerfile uses. Debian 12 does not work: glibc 2.34 merged `libpthread` into
`libc`, so a binary built there requires `GLIBC_2.34` and the controller cannot
run it. `gcc-linaro-arm-linux-gnu-4.7.3`, elsewhere in this repository, does not
work either: its sysroot is glibc 2.15, below the floor, and it ships no `cc1`.

## Rebuilding

```sh
sh docker/glibc-sysroot/build.sh
```

This regenerates the tarball and its checksum. Update `SYSROOT_SHA256` in
`makefile/Makefile-pmas-glibc.toml` afterwards.

The build dereferences every symlink, because Windows cannot create symlinks
without elevated privileges and `tar` aborts the whole extraction when it tries.
It also rewrites `libc.so`, `libpthread.so`, and `libm.so`, which Debian ships
as `ld` scripts holding absolute paths that do not survive relocation.

## Using it

```toml
extend = "makefile/Makefile.toml"   # fetched from Makefile-pmas-glibc.toml
```

```sh
cargo make pmas_glibc build --release
```

Verify what a result requires before deploying it:

```sh
readelf -V <binary> | grep -o 'GLIBC_[0-9.]*' | sort -uV
```

A correct build reports nothing above `GLIBC_2.18`.

## When to prefer this over the musl task set

Static musl with mimalloc remains the default, and both meet the 1 kHz deadline
with zero missed cycles. Reach for glibc when you need one of these:

- `LD_PRELOAD`, `perf`, or `gdbserver` against the Elmo SDK, none of which work
  against a statically linked musl binary.
- A lower worst-case cycle. Measured over 60,000 cycles, glibc's slowest was
  13,502 ns against mimalloc's 28,466 ns.
- A smaller resident set. glibc measured 7.6 MB of Pss against mimalloc's
  17.2 MB, and 1.5 MB against 13.2 MB without `mlockall`.

Stay on musl when you want a binary that does not depend on any individual
controller's glibc version, or when allocator throughput matters: mimalloc
completed about 43% more operations than `ptmalloc2` in the same runs.

Full numbers: globusmedical/rs-gm_mctrl#141.
