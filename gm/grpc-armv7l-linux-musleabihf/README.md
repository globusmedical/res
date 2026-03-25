# gRPC Static Libraries for ARM Linux musl (armv7l-unknown-linux-musleabihf)

Pre-built gRPC + protobuf static libraries for cross-compiling C++ code
targeting the ELMO PMAS (ARM Cortex-A15, musl libc, hard float).

## What's Included

| Component | Description |
|---|---|
| `lib/libgrpc.a` | gRPC C core static library |
| `lib/libgrpc++.a` | gRPC C++ static library |
| `lib/libprotobuf.a` | Protocol Buffers runtime |
| `lib/libprotobuf-lite.a` | Protocol Buffers lite runtime |
| `lib/libabsl_*.a` | Abseil libraries (required by gRPC/protobuf) |
| `lib/libaddress_sorting.a` | gRPC address sorting |
| `lib/libupb*.a` | µpb (protobuf micro) |
| `lib/libre2.a` | RE2 regex (required by gRPC) |
| `lib/libcares.a` | c-ares DNS resolver |
| `lib/libssl.a`, `lib/libcrypto.a` | OpenSSL (static) |
| `lib/libz.a` | zlib (static) |
| `include/grpc/`, `include/grpcpp/` | gRPC headers |
| `include/google/protobuf/` | Protobuf headers |
| `include/absl/` | Abseil headers |
| `lib/cmake/` | CMake config files for `find_package()` |
| `bin/protoc` | Linux host protoc compiler |
| `bin/grpc_cpp_plugin` | Linux host gRPC C++ codegen plugin |

## Pinned Versions

Versions are chosen for mutual compatibility with gRPC 1.71.0:

| Package | Version |
|---|---|
| gRPC | 1.71.0 |
| Protobuf | 5.29.5 |
| Abseil | 20240722.0 |
| c-ares | 1.34.5 |
| RE2 | 2025-11-05 |
| OpenSSL | 3.5.0 |
| zlib | 1.3.1 |

## Building the Artifact

```bash
cd docker
docker compose build
docker compose up
```

The output appears in `docker/output/`:

- `grpc-armv7l-unknown-linux-musleabihf.tar.gz`
- `grpc-armv7l-unknown-linux-musleabihf.tar.gz.sha256`

## Publishing to grab

After building, upload the artifact to the S3 registry:

```bash
grab publish --collection grpc
```
