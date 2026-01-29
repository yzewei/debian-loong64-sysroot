#!/usr/bin/env bash
set -euo pipefail

# Build source-based library artifacts (OpenSSL) in a loong64 container.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

OPENSSL_VERSION="${OPENSSL_VERSION:-3.2.2}"
OPENSSL_URL="${OPENSSL_URL:-https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz}"

SRC_ARTIFACTS_DIR="${SRC_ARTIFACTS_DIR:-$ROOT_DIR/src-libs/openssl-${OPENSSL_VERSION}}"
SRC_ARTIFACTS_IMAGE="${SRC_ARTIFACTS_IMAGE:-ghcr.io/loong64/debian:trixie-slim-fix}"
SRC_ARTIFACTS_PLATFORM="${SRC_ARTIFACTS_PLATFORM:-linux/loong64}"

if [ -f "$SRC_ARTIFACTS_DIR/usr/lib64/libcrypto.so.3" ] && [ -f "$SRC_ARTIFACTS_DIR/usr/lib64/libssl.so.3" ]; then
    echo "✅ OpenSSL artifacts already present: $SRC_ARTIFACTS_DIR"
    exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found; cannot build source artifacts."
    exit 1
fi

mkdir -p "$SRC_ARTIFACTS_DIR"

rel="${SRC_ARTIFACTS_DIR#$ROOT_DIR/}"
if [ "$rel" = "$SRC_ARTIFACTS_DIR" ]; then
    echo "ERROR: SRC_ARTIFACTS_DIR must be under repo root ($ROOT_DIR)."
    exit 1
fi

echo "=== Building OpenSSL ${OPENSSL_VERSION} artifacts in loong64 container ==="
docker run --rm --platform="$SRC_ARTIFACTS_PLATFORM" \
    --entrypoint /usr/bin/env \
    -v "$ROOT_DIR:/work" -w /work \
    "$SRC_ARTIFACTS_IMAGE" \
    -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/root \
    LANG=C \
    LC_ALL=C \
    SRC_BUILD_MODE=native \
    SYSROOT_DIR="/work/$rel" \
    SRC_BUILDS=openssl \
    OPENSSL_VERSION="$OPENSSL_VERSION" \
    OPENSSL_URL="$OPENSSL_URL" \
    /bin/bash --noprofile --norc -c "./scripts/build_src_libs.sh"
