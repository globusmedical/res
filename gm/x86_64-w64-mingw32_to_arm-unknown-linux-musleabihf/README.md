# Cross-compiler toolchain for PMAS

Canadian-cross toolchain for compiling C and C++ code on Windows
x64 for Linux ARMv7 using GCC 15.2 with the musl C library.

| Property | Value |
|---|---|
| Compiler | GCC 15.2 (C and C++ with full C++23 and partial C++26 support) |
| Host | x86_64-w64-mingw32 |
| Target | armv7l-unknown-linux-musleabihf |
| crosstool-NG | 1.28.0 |

## grab

The built toolchain is published to the `s3://globus-soup-archives`
registry as `x86_64-w64-mingw32_to_armv7l-unknown-linux-musleabihf`.

Fetch with:

```sh
grab fetch x86_64-w64-mingw32_to_armv7l-unknown-linux-musleabihf@15.2.0
```

## Building

Rebuild the toolchain with Docker:

```sh
cd docker
docker compose up --build
```

Output lands in `docker/output/`.
