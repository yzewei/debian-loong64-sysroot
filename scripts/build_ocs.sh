#!/bin/bash
set -e

# ================= Configuration =================
SYSROOT_ID="opencloudos-stream"
OCS_RELEASE="${OCS_RELEASE:-23}"
ARCH="loongarch64"
TARGET_DIR="${TARGET_DIR:-sysroot-ocs-${ARCH}}"
if [[ "$TARGET_DIR" != /* ]]; then
    TARGET_DIR="$(pwd)/$TARGET_DIR"
fi
if [ -z "${SUDO:-}" ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        SUDO=""
    fi
fi
OCS_MIRROR="${OCS_MIRROR:-https://mirrors.opencloudos.org/opencloudos-stream/releases/${OCS_RELEASE}}"
# Repos to use (space-separated). Common choices: BaseOS AppStream EPOL
OCS_REPOS="${OCS_REPOS:-BaseOS AppStream}"
OCS_GPGCHECK="${OCS_GPGCHECK:-0}"

# Default package set (override with OCS_PKGS="...").
OCS_PKGS="${OCS_PKGS:-filesystem ca-certificates wget curl bash coreutils glibc libgcc libstdc++ openssl-libs zlib xz-libs zstd bzip2-libs libgcrypt libgpg-error lz4-libs p11-kit libffi libidn2 libunistring libtasn1 gnutls systemd-libs glib2 libxml2 sqlite-libs libatomic libpsl krb5-libs keyutils-libs e2fsprogs-libs brotli libevent openssl}"

# Libraries to validate after install (pkg:pattern).
OCS_LIB_CHECKS=(
    "openssl-libs:libssl.so.*"
    "openssl-libs:libcrypto.so.*"
    "glib2:libglib-2.0.so.*"
    "glib2:libgobject-2.0.so.*"
    "glib2:libgio-2.0.so.*"
    "libxml2:libxml2.so.*"
    "sqlite-libs:libsqlite3.so.*"
    "libatomic:libatomic.so.*"
    "libpsl:libpsl.so.*"
    "krb5-libs:libgssapi_krb5.so.*"
    "krb5-libs:libkrb5.so.*"
    "krb5-libs:libkrb5support.so.*"
    "krb5-libs:libk5crypto.so.*"
    "e2fsprogs-libs:libcom_err.so.*"
    "keyutils-libs:libkeyutils.so.*"
    "brotli:libbrotlidec.so.*"
    "libevent:libevent-2.1.so.*"
    "openssl:legacy.so"
)

find_lib_in_sysroot() {
    local pattern="$1"
    find \
        "$TARGET_DIR/usr/lib" \
        "$TARGET_DIR/usr/lib64" \
        "$TARGET_DIR/lib" \
        "$TARGET_DIR/lib64" \
        -name "$pattern" 2>/dev/null | head -n 1
}

check_libs() {
    local entry pkg pattern found
    for entry in "${OCS_LIB_CHECKS[@]}"; do
        pkg="${entry%%:*}"
        pattern="${entry#*:}"
        found="$(find_lib_in_sysroot "$pattern")"
        if [ -n "$found" ]; then
            echo "✅ Verified: Found $found"
            continue
        fi
        echo "❌ CRITICAL: $pattern not found (missing from $pkg?)"
        return 1
    done
}

enable_openssl_legacy_provider() {
    local conf=""
    if [ -f "$TARGET_DIR/etc/ssl/openssl.cnf" ]; then
        conf="$TARGET_DIR/etc/ssl/openssl.cnf"
    elif [ -f "$TARGET_DIR/etc/pki/tls/openssl.cnf" ]; then
        conf="$TARGET_DIR/etc/pki/tls/openssl.cnf"
    else
        echo "WARNING: openssl.cnf not found; skipping legacy provider enable."
        return 0
    fi

    $SUDO python3 - "$conf" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = f.read()

def has_section(name: str) -> bool:
    return re.search(rf"^\s*\[{re.escape(name)}\]\s*$", data, re.M) is not None

def has_key(section: str, key: str) -> bool:
    pattern = rf"^\s*\[{re.escape(section)}\]\s*$"
    lines = data.splitlines()
    in_section = False
    for line in lines:
        if re.match(r"^\s*\[.*\]\s*$", line):
            in_section = re.match(pattern, line) is not None
            continue
        if in_section and re.match(rf"^\s*{re.escape(key)}\s*=", line):
            return True
    return False

if not re.search(r"^\s*openssl_conf\s*=", data, re.M):
    data = "openssl_conf = openssl_init\n\n" + data

if has_section("provider_sect"):
    if not has_key("provider_sect", "legacy"):
        lines = data.splitlines()
        out = []
        in_section = False
        inserted = False
        for line in lines:
            if re.match(r"^\s*\[.*\]\s*$", line):
                if in_section and not inserted:
                    out.append("legacy = legacy_sect")
                    inserted = True
                in_section = line.strip().lower() == "[provider_sect]"
            out.append(line)
        if in_section and not inserted:
            out.append("legacy = legacy_sect")
        data = "\n".join(out)
else:
    data += (
        "\n\n[openssl_init]\n"
        "providers = provider_sect\n"
        "\n[provider_sect]\n"
        "default = default_sect\n"
        "legacy = legacy_sect\n"
        "\n[default_sect]\n"
        "activate = 1\n"
        "\n[legacy_sect]\n"
        "activate = 1\n"
    )

if not has_section("legacy_sect"):
    data += "\n\n[legacy_sect]\nactivate = 1\n"

with open(path, "w", encoding="utf-8") as f:
    f.write(data)
PY
}

build_repo_args() {
    local repo name base args=()
    for repo in $OCS_REPOS; do
        name="ocs-$(echo "$repo" | tr '[:upper:]' '[:lower:]')"
        base="${OCS_MIRROR}/${repo}/${ARCH}/Packages"
        if curl -fsI "${base}/repodata/repomd.xml" >/dev/null; then
            args+=("--repofrompath=${name},${base}/")
            args+=("--repo=${name}")
            args+=("--setopt=${name}.gpgcheck=${OCS_GPGCHECK}")
        else
            echo "WARNING: ${base}/repodata/repomd.xml not reachable; skipping ${repo}"
        fi
    done
    echo "${args[@]}"
}

echo "=== 0. Prepare Build Env ==="
if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update
    $SUDO apt-get install -y wget curl dnf rpm python3
elif command -v dnf >/dev/null 2>&1; then
    if ! $SUDO dnf -y install wget curl-minimal python3; then
        $SUDO dnf -y install wget curl python3 --allowerasing
    fi
else
    echo "ERROR: no apt-get or dnf available to install host deps."
    exit 1
fi

echo "=== 1. Start Build OpenCloudOS Sysroot ==="
if [ -d "$TARGET_DIR" ]; then $SUDO rm -rf "$TARGET_DIR"; fi
$SUDO mkdir -p "$TARGET_DIR"

# Ensure filesystem package can create /lib and /lib64 as symlinks
$SUDO rm -rf "$TARGET_DIR/lib" "$TARGET_DIR/lib64"

REPO_ARGS="$(build_repo_args)"
if [ -z "$REPO_ARGS" ]; then
    echo "ERROR: No valid OpenCloudOS repos found. Check OCS_MIRROR/OCS_REPOS."
    exit 1
fi

DNF_FORCEARCH="--forcearch=$ARCH"
DNF_IGNOREARCH=""
if ! dnf --forcearch="$ARCH" --version >/dev/null 2>&1; then
    if [ -z "${OCS_IN_CONTAINER:-}" ] && [ "${OCS_USE_DOCKER:-1}" != "0" ] && command -v docker >/dev/null 2>&1; then
        OCS_DOCKER_IMAGE="${OCS_DOCKER_IMAGE:-ghcr.io/loong64/opencloudos:9.4-toolbox-20251019}"
        OCS_DOCKER_PLATFORM="${OCS_DOCKER_PLATFORM:-linux/loong64}"
        echo "INFO: Host dnf/rpm does not recognize arch '$ARCH'; running in container ${OCS_DOCKER_IMAGE} (${OCS_DOCKER_PLATFORM})..."
        if docker buildx version >/dev/null 2>&1; then
            echo "INFO: buildx detected; bootstrapping builder for ${OCS_DOCKER_PLATFORM}"
            docker buildx inspect --bootstrap >/dev/null 2>&1 || true
        fi
        docker run --rm --platform="$OCS_DOCKER_PLATFORM" -v "$PWD:/work" -w /work \
            -e OCS_IN_CONTAINER=1 \
            -e OCS_USE_DOCKER=0 \
            -e OCS_RELEASE="$OCS_RELEASE" \
            -e ARCH="$ARCH" \
            -e TARGET_DIR="sysroot-ocs-${ARCH}" \
            -e OCS_MIRROR="$OCS_MIRROR" \
            -e OCS_REPOS="$OCS_REPOS" \
            -e OCS_GPGCHECK="$OCS_GPGCHECK" \
            -e OCS_PKGS="$OCS_PKGS" \
            "$OCS_DOCKER_IMAGE" \
            bash -lc "dnf -y install wget curl-minimal python3 tar findutils --allowerasing && ./scripts/build_ocs.sh"
        exit $?
    fi
    echo "WARNING: Host dnf/rpm does not recognize arch '$ARCH'; falling back to ignorearch."
    DNF_FORCEARCH=""
    DNF_IGNOREARCH="--setopt=ignorearch=1"
fi

# Install filesystem first to establish /lib and /lib64 symlinks
$SUDO rm -rf "$TARGET_DIR/lib" "$TARGET_DIR/lib64"
$SUDO dnf -y --installroot="$TARGET_DIR" \
    --releasever="$OCS_RELEASE" \
    $DNF_FORCEARCH \
    --setopt=reposdir=/dev/null \
    --setopt=varsdir=/dev/null \
    --setopt=install_weak_deps=False \
    --setopt=tsflags=nodocs,noscripts \
    --setopt=keepcache=0 \
    --setopt=cachedir="$TARGET_DIR/var/cache/dnf" \
    $DNF_IGNOREARCH \
    $REPO_ARGS \
    --allowerasing \
    install filesystem

echo "Installing packages into $TARGET_DIR..."
$SUDO dnf -y --installroot="$TARGET_DIR" \
    --releasever="$OCS_RELEASE" \
    $DNF_FORCEARCH \
    --setopt=reposdir=/dev/null \
    --setopt=varsdir=/dev/null \
    --setopt=install_weak_deps=False \
    --setopt=tsflags=nodocs,noscripts \
    --setopt=keepcache=0 \
    --setopt=cachedir="$TARGET_DIR/var/cache/dnf" \
    $DNF_IGNOREARCH \
    $REPO_ARGS \
    --allowerasing \
    install $OCS_PKGS

echo ">>> Verifying Runtime Libraries..."
if ! check_libs; then
    exit 1
fi

echo ">>> Enabling OpenSSL legacy provider..."
enable_openssl_legacy_provider

echo "=== 2. Clean & Fix ==="
$SUDO rm -rf "$TARGET_DIR/var/cache/dnf"

echo "Fixing symlinks..."
# Add Debian-compatible multiarch libdir for consumers
if [ ! -e "$TARGET_DIR/usr/lib/loongarch64-linux-gnu" ]; then
    $SUDO ln -s ../lib64 "$TARGET_DIR/usr/lib/loongarch64-linux-gnu"
fi
if [ -f "scripts/fix_links.py" ]; then $SUDO python3 scripts/fix_links.py "$TARGET_DIR"; fi

# ==========================================
# 3. Package Runtime Libs
# ==========================================
echo "=== 3. Package Runtime Libs (For Box64) ==="
RUNTIME_TAR="${SYSROOT_ID}-${OCS_RELEASE}-${ARCH}-runtime-libs.tar.gz"
TEMP_RUNTIME="runtime-libs-temp"
rm -rf "$TEMP_RUNTIME"
mkdir -p "$TEMP_RUNTIME/usr"

echo "Copying libraries..."
$SUDO cp -a "$TARGET_DIR/lib" "$TEMP_RUNTIME/" || true
$SUDO cp -a "$TARGET_DIR/lib64" "$TEMP_RUNTIME/" || true
$SUDO cp -a "$TARGET_DIR/usr/lib" "$TEMP_RUNTIME/usr/" || true
$SUDO cp -a "$TARGET_DIR/usr/lib64" "$TEMP_RUNTIME/usr/" || true
$SUDO cp -a "$TARGET_DIR/etc" "$TEMP_RUNTIME/" || true

echo "Packaging Runtime Artifact: $RUNTIME_TAR ..."
$SUDO tar -czf "$RUNTIME_TAR" -C "$TEMP_RUNTIME" .
$SUDO chown $USER:$USER "$RUNTIME_TAR"
$SUDO rm -rf "$TEMP_RUNTIME"

# ==========================================
# 4. Package Full Sysroot
# ==========================================
echo "=== 4. Package Full Sysroot ==="
FULL_TAR="${SYSROOT_ID}-${OCS_RELEASE}-${ARCH}-sysroot.tar.gz"
echo "Packaging Full Artifact: $FULL_TAR ..."
$SUDO tar -czf "$FULL_TAR" -C "$TARGET_DIR" .
$SUDO chown $USER:$USER "$FULL_TAR"

echo "Build Success!"
