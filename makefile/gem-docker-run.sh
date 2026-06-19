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
shift 5
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

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Pulling GEM builder image: $IMAGE"
    if ! docker pull "$IMAGE"; then
        echo "" >&2
        echo "ERROR: failed to pull GEM builder image: $IMAGE" >&2
        echo "       Ensure you can access ghcr.io/globusmedical/gem-builder." >&2
        echo "       Run 'gh auth login' or set GITHUB_TOKEN, then retry." >&2
        exit 1
    fi
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
