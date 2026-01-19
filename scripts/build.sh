#!/bin/bash
set -e

# env Larch
ARCH="loong64"
DISTRO="sid"
TARGET_DIR="sysroot-loong64"
MIRROR="http://ftp.ports.debian.org/debian-ports"

echo "=== 0. Prepare Build Env ==="
sudo apt-get update
# 安装基础工具，包括 curl (用于抓取文件名)
sudo apt-get install -y qemu-user-static wget curl

echo ">>> Detecting and installing latest Debian Ports Keyring..."
# 1. 定义仓库目录 URL
REPO_URL="http://ftp.debian.org/debian/pool/main/d/debian-ports-archive-keyring/"

# 2. 动态获取最新的包名 (不要写死版本号)
# 逻辑：获取网页内容 -> 提取 .deb 文件名 -> 版本号排序 -> 取最新的一个
LATEST_DEB=$(curl -s $REPO_URL | grep -o 'debian-ports-archive-keyring_[0-9.]\+_all.deb' | sort -V | tail -n 1)

if [ -z "$LATEST_DEB" ]; then
    echo "Error: Failed to detect latest keyring version. Network issue?"
    exit 1
fi

echo "Found latest keyring: $LATEST_DEB"

# 3. 下载并安装
wget "${REPO_URL}${LATEST_DEB}"
sudo dpkg -i "$LATEST_DEB"
rm "$LATEST_DEB"

echo "Downloading latest debootstrap..."
rm -rf debootstrap-master
wget -q https://salsa.debian.org/installer-team/debootstrap/-/archive/master/debootstrap-master.tar.gz
tar -xzf debootstrap-master.tar.gz
cd debootstrap-master
sudo make install
cd ..

echo "=== 1. Start Build Debootstrap (First Stage) ==="
# Box64 运行环境所需的库 (使用 t64 后缀适配 Sid)
PACKAGES="libc6,libstdc++6,libgcc-s1,libssl3t64,zlib1g,
