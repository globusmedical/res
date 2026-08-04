#!/bin/bash
# Run a command inside the GEM Docker builder image.
set -euo pipefail

INTERACTIVE=""
if [[ "${1:-}" == "--interactive" ]]; then
    INTERACTIVE="-it"
    shift
fi

WORKSPACE="$1"
ENV_FILE="$2"
VOL_PREFIX="$3"
IMAGE="$4"
SIBLINGS="$5"
EXTRACT_ARTIFACTS="${6:-0}"
shift 6
INNER_CMD="$*"
if [[ "$SIBLINGS" == "-" ]]; then
    SIBLINGS=""
fi

# The env file may contain credentials (e.g. GITHUB_TOKEN); always remove it
# on exit, including when 'set -e' aborts the script on a failed command.
trap 'rm -f "$ENV_FILE"' EXIT

IMAGE="$(printf '%s' "$IMAGE" | tr -d '[:space:]')"
if [[ -z "$IMAGE" ]]; then
    echo "ERROR: GEM builder image is empty." >&2
    exit 1
fi

TOKEN=""
if [[ -f "$ENV_FILE" ]]; then
    TOKEN="$(sed -n 's/^GITHUB_TOKEN=//p' "$ENV_FILE" | head -1)"
fi

if [[ -n "$TOKEN" ]]; then
    printf '%s' "$TOKEN" | docker login ghcr.io -u github --password-stdin >/dev/null
fi

# The builder tag is mutable — the publishing workflow overwrites it whenever the
# image contents change. A cached tag must therefore never be trusted without a
# pull: a stale image silently links the kernel module against a different SHM
# ABI than the crates it is built with, and nothing downstream catches it until
# gemd rejects the package at deploy time.
if [[ "${GEM_DOCKER_NO_PULL:-}" == "1" ]]; then
    echo "WARNING: GEM_DOCKER_NO_PULL=1 — skipping pull; cached image may be stale." >&2
elif ! docker pull "$IMAGE"; then
    if docker image inspect "$IMAGE" >/dev/null 2>&1; then
        echo "" >&2
        echo "WARNING: could not pull $IMAGE; falling back to the local cache." >&2
        echo "         This tag is mutable, so the cached image may be STALE and may" >&2
        echo "         embed a different SHM ABI than the crates being built." >&2
        echo "" >&2
    else
        echo "" >&2
        echo "ERROR: failed to pull GEM builder image: $IMAGE" >&2
        echo "       Ensure you can access ghcr.io/globusmedical/gem-builder." >&2
        echo "       Run 'gh auth login' or set GITHUB_TOKEN, then retry." >&2
        exit 1
    fi
fi

# Pin the run to an immutable digest and record it: the tag alone does not
# identify which SHM ABI the produced artifact was built against.
IMAGE_DIGEST="$(docker image inspect --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' "$IMAGE" 2>/dev/null || true)"
if [[ -n "$IMAGE_DIGEST" ]]; then
    echo "GEM builder image digest: $IMAGE_DIGEST" >&2
    IMAGE="$IMAGE_DIGEST"
fi

if [[ "${GEM_DOCKER_PULL_ONLY:-}" == "1" ]]; then
    exit 0
fi

VOLUMES=(-v "$WORKSPACE:/workspace")
VOLUMES+=(-v "$VOL_PREFIX-cargo-target:/tmp/cargo-target")
VOLUMES+=(-v "$VOL_PREFIX-cargo-home:/root/.cargo")
VOLUMES+=(-v "$VOL_PREFIX-sccache:/tmp/sccache")

if [[ -n "$SIBLINGS" ]]; then
    IFS='@' read -ra MOUNTS <<< "$SIBLINGS"
    for mount in "${MOUNTS[@]}"; do
        [[ -n "$mount" ]] && VOLUMES+=(-v "$mount")
    done
fi

# shellcheck disable=SC2086
docker run --rm $INTERACTIVE \
    --env-file "$ENV_FILE" \
    "${VOLUMES[@]}" \
    -w /workspace \
    -e CARGO_TARGET_DIR=/tmp/cargo-target \
    -e RUSTC_WRAPPER=sccache \
    -e SCCACHE_DIR=/tmp/sccache \
    -e CARGO_NET_GIT_FETCH_WITH_CLI=true \
    --init "$IMAGE" \
    bash -c "$INNER_CMD"

if [[ "$EXTRACT_ARTIFACTS" == "1" ]]; then
    docker run --rm \
        -v "$WORKSPACE:/workspace" \
        -v "$VOL_PREFIX-cargo-target:/tmp/cargo-target" \
        --init "$IMAGE" \
        bash -c '
            set -euo pipefail
            out=/workspace/target/gem/cargo-artifacts
            rm -rf "$out"
            mkdir -p "$out"

            cmd=$1
            profile=debug
            if [[ " $cmd " == *" --release "* ]]; then
                profile=release
            fi

            read -r -a words <<< "$cmd"
            packages=()
            for ((i = 0; i < ${#words[@]}; i++)); do
                case "${words[$i]}" in
                    -p|--package)
                        if (( i + 1 < ${#words[@]} )); then
                            packages+=("${words[$((i + 1))]//-/_}")
                        fi
                        ;;
                    --package=*)
                        pkg=${words[$i]#--package=}
                        packages+=("${pkg//-/_}")
                        ;;
                esac
            done

            matches_package() {
                local base=$1
                if (( ${#packages[@]} == 0 )); then
                    return 0
                fi
                for pkg in "${packages[@]}"; do
                    if [[ "$base" == "$pkg" || "$base" == "lib$pkg."* ]]; then
                        return 0
                    fi
                done
                return 1
            }

            while IFS= read -r profile_dir; do
                find "$profile_dir" -maxdepth 2 \
                    \( -path "*/deps/*" -o -path "*/build/*" -o -path "*/incremental/*" -o -path "*/.fingerprint/*" \) -prune \
                    -o -type f \
                    \( -perm -111 -o -name "*.so" -o -name "*.dylib" -o -name "*.a" -o -name "*.rlib" \) \
                    -print
            done < <(find /tmp/cargo-target -type d -name "$profile" -print) | while IFS= read -r artifact; do
                base=$(basename "$artifact")
                if matches_package "$base"; then
                    rel=${artifact#/tmp/cargo-target/}
                    mkdir -p "$out/$(dirname "$rel")"
                    cp -a "$artifact" "$out/$rel"
                fi
            done

            if ! find "$out" -type f -print -quit | grep -q .; then
                echo "WARNING: no final cargo artifacts found to extract from /tmp/cargo-target" >&2
            else
                echo "Extracted GEM cargo artifacts to $out"
            fi
        ' -- "$INNER_CMD"
fi
