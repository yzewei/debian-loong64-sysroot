#!/bin/bash
set -e

# env Larch
ARCH="loong64"
DISTRO="sid"
TARGET_DIR="sysroot-loong64"
MIRROR="http://ftp.ports.debian.org/debian-ports"

echo "0. prepare build env"
sudo apt-get update
sudo apt-get install -y qemu-user-static debian-ports-archive-keyring wget

echo "get newer debootstrap..."
wget https://salsa.debian.org/installer-team/debootstrap/-/archive/master/debootstrap-master.tar.gz
tar -xzf debootstrap-master.tar.gz
cd debootstrap-master
sudo make install
cd ..

echo "1. start build Debootstrap"
# --foreign only tar not config
# --include: prepare build box64 need libs.
PACKAGES="libc6,libstdc++6,libgcc-s1,libssl3,zlib1g,liblzma5,libzstd1,libbz2-1.0,libcrypt1,perl-base"

sudo mkdir -p "$TARGET_DIR"

sudo debootstrap --arch="$ARCH" --foreign --include="$PACKAGES" "$DISTRO" "$TARGET_DIR" "$MIRROR"

echo "2. config"
sudo cp /usr/bin/qemu-loongarch64-static "$TARGET_DIR/usr/bin/"
sudo chroot "$TARGET_DIR" /debootstrap/debootstrap --second-stage

echo "3. clean"
sudo rm -rf "$TARGET_DIR/var/cache/apt/archives/*"
sudo rm "$TARGET_DIR/usr/bin/qemu-loongarch64-static"

# 修复软链接 (将绝对路径改为相对路径，这对 Sysroot 至关重要)
echo "正在修复软链接为相对路径..."
sudo python3 scripts/fix_links.py "$TARGET_DIR"

echo "4. packages"
TAR_NAME="debian-${DISTRO}-${ARCH}-sysroot.tar.gz"
sudo tar -czf "$TAR_NAME" -C "$TARGET_DIR" .
sudo chown $USER:$USER "$TAR_NAME"

echo "build success!"
