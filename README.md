# LoongArch Sysroot Builder 🐉

[![Build & Release Sysroot](https://github.com/yzewei/debian-loong64-sysroot/actions/workflows/build.yml/badge.svg)](https://github.com/yzewei/debian-loong64-sysroot/actions/workflows/build.yml)

**Automated CI builder for minimal, clean LoongArch sysroots (Debian and OpenCloudOS Stream).**

This project uses GitHub Actions, QEMU, `debootstrap`, and `dnf` to build pristine LoongArch system root filesystems. It is specifically optimized for:
* **Box64 Emulation**: Providing native libraries to x86/x64 containers running on LoongArch hosts.
* **Cross-Compilation**: Linking against loong64 libraries from x86 machines.

## 🚀 Why use this?

When running x86 containers on LoongArch via Box64, you often need to map native libraries (libc, libssl, libcrypt, etc.) into the container.
Using the host's `/lib64` folder directly is problematic because:
1.  **Symlink Hell**: Host libraries often use absolute symlinks (e.g., `libc.so.6 -> /lib64/libc-2.36.so`). When mounted into a container at a different path, these links break.
2.  **Pollution**: The host system may contain unnecessary or conflicting packages.
3.  **Reproducibility**: Different LoongArch machines have different library versions.

**This builder solves these problems by:**
1.  Building a clean **Debian** base (sid by default).
2.  Building a clean **OpenCloudOS Stream** base (23 by default).
3.  **Auto-fixing symlinks**: Converting absolute symlinks to relative ones (e.g., `../../lib/libc.so.6`).
4.  **Normalizing Debian libs into `/lib64` as real files** so `LD_LIBRARY_PATH` can stay simple (no symlink dependency).

中文：本项目会构建干净的 Debian / OpenCloudOS sysroot，修复链接问题，并把 Debian 的库直接整理到 `/lib64`（真实文件），方便 Box64 使用。

## 🏗 How it Works (CI Pipeline)
This repository uses a GitHub Actions workflow to:
- Setup QEMU: Registers loongarch64 binfmt support on the x86 runner.
- Debootstrap: Downloads Debian Trixie packages for loong64.
- Second Stage: Uses chroot + QEMU to configure the packages.
- Fix Symlinks: Converts absolute symlinks to relative paths.
- Release: Packages the result and uploads it to GitHub Releases (triggered by v* tags).

## 🔨 Manual Build
If you want to build this locally on a Linux machine (x86 or LoongArch):

```bash
# Install dependencies
sudo apt-get install -y qemu-user-static debootstrap debian-ports-archive-keyring

# Run the Debian build script (default)
chmod +x scripts/build.sh
./scripts/build.sh

# Run the OpenCloudOS Stream build
chmod +x scripts/build_ocs.sh
./scripts/build_ocs.sh

# Or via the unified entry point
SYSROOT_FLAVOR=ocs ./scripts/build.sh
```

## 🔐 OpenSSL Source Build (Debian + OpenCloudOS)

Both sysroots use a **shared OpenSSL 3.2.x source-build artifact** by default. The build runs **once** (in a loong64 container) into `src-libs/openssl-<version>` and is then **copied into both Debian and OpenCloudOS sysroots**. This guarantees required symbols (including `SSL_get0_group_name`) and enables the **legacy provider** (needed for `EVP_idea_cfb64`).

中文：默认会在 `src-libs/openssl-<version>` **源码构建 OpenSSL 3.2.x 一次**（loong64 容器内完成），然后**拷贝到 Debian 与 OpenCloudOS sysroot**。这样确保必需符号（如 `SSL_get0_group_name`）和 legacy provider（`EVP_idea_cfb64`）齐全。

The source-build logic lives in `scripts/build_src_libs.sh` and is extensible via `DEB_SRC_BUILDS` / `OCS_SRC_BUILDS` (space/comma-separated list). Currently supported: `openssl`.

中文：源码构建逻辑统一放在 `scripts/build_src_libs.sh`，通过 `DEB_SRC_BUILDS` / `OCS_SRC_BUILDS` 可增删要源码构建的库（目前仅 `openssl`）。

Control flags:

```bash
# Debian (artifacts built in loong64 container)
DEB_SRC_USE_ARTIFACTS=1
DEB_SRC_ARTIFACTS_DIR=src-libs/openssl-3.2.2
DEB_SRC_ARTIFACTS_IMAGE=ghcr.io/loong64/opencloudos:9.4-toolbox-20251019
DEB_SRC_ARTIFACTS_PLATFORM=linux/loong64
DEB_SRC_BUILDS="openssl"          # default; set to "" to disable
DEB_OPENSSL_VERSION="3.2.2"
DEB_OPENSSL_URL="https://www.openssl.org/source/openssl-3.2.2.tar.gz"

# OpenCloudOS (uses the same artifacts by default)
OCS_SRC_USE_ARTIFACTS=1
OCS_SRC_ARTIFACTS_DIR=src-libs/openssl-3.2.2
OCS_SRC_BUILDS="openssl"          # default; set to "" to disable
OCS_OPENSSL_VERSION="3.2.2"
OCS_OPENSSL_URL="https://www.openssl.org/source/openssl-3.2.2.tar.gz"
```

**Note:** If you disable artifacts (`*_SRC_USE_ARTIFACTS=0`), the build falls back to building OpenSSL directly inside the target sysroot.

中文：**注意** 若关闭 artifacts（`*_SRC_USE_ARTIFACTS=0`），将回退为在 sysroot 内部直接源码构建。

## 🧱 OpenCloudOS glibc Override (from Debian)

OpenCloudOS glibc can be too old for some Box64 workloads. The OpenCloudOS build can **copy glibc runtime libs from the Debian sysroot** into the OpenCloudOS sysroot (enabled by default).

中文：OpenCloudOS 的 glibc 版本可能偏旧，默认会从 Debian sysroot 复制 glibc 运行库到 OpenCloudOS sysroot 以提升兼容性。

```bash
OCS_GLIBC_FROM_DEBIAN=1                 # default; set to 0 to disable
DEBIAN_SYSROOT_DIR=./sysroot-loong64    # must exist before OCS build
```

**Note:** In CI, Debian is built first so the OpenCloudOS build can reuse its glibc.

## 📦 Debian /lib64 Layout (for Box64)

Debian multiarch libs are also **copied as real files into `/lib64` and `/usr/lib64`** (not symlinks). This makes Box64 usage simpler:

```bash
LD_LIBRARY_PATH="/abi2-root/lib64:/abi2-root/lib"
```

中文：Debian sysroot 会把多架构库**复制为真实文件到 `/lib64` 与 `/usr/lib64`**，避免软链接导致的路径问题，Box64 的 `LD_LIBRARY_PATH` 可以更简单。

## 📥 Downloads

Go to the [**Releases Page**](../../releases) to download the latest sysroot artifacts.

## 🛠 Usage with Box64 & Docker

(Examples here — customize for your workload.)
