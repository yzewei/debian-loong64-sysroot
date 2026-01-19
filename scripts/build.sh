#!/bin/bash
set -e

# env Larch
ARCH="loong64"
DISTRO="sid"
TARGET_DIR="sysroot-loong64"
MIRROR="http://ftp.ports.debian.org/debian-ports"

echo "=== 0. Prepare Build Env ==="
sudo apt-get update
# 注意：这里去掉了 debian-ports-archive-keyring，因为 apt 源里的太老了
sudo apt-get install -y qemu-user-static wget

echo ">>> Fixing Keyring for Debian Ports 2025..."
# 手动下载最新的 keyring 包 (包含 key id C6894E6BB25B9C99)
wget http://ftp.debian.org/debian/pool/main/d/debian-ports-archive-keyring/debian-ports-archive-keyring_2024.01.05_all.deb
sudo dpkg -i debian-ports-archive-keyring_2024.01.05_all.deb
rm debian-ports-archive-keyring_2024.01.05_all.deb

echo "Downloading latest debootstrap..."
rm -rf debootstrap-master
wget -q https://salsa.debian.org/installer-team/debootstrap/-/archive/master/debootstrap-master.tar.gz
tar -xzf debootstrap-master.tar.gz
cd debootstrap-master
sudo make install
cd ..

echo "=== 1. Start Build Debootstrap (First Stage) ==="
# Box64 运行环境所需的库 (注意 t64 后缀)
PACKAGES="libc6,libstdc++6,libgcc-s1,libssl3t64,zlib1g,liblzma5,libzstd1t64,libbz2-1.0,libcrypt1t64,perl-base"

sudo mkdir -p "$TARGET_DIR"

# 这里明确指定 keyring 文件，现在它是最新的了
sudo debootstrap \
    --arch="$ARCH" \
    --foreign \
    --keyring=/usr/share/keyrings/debian-ports-archive-keyring.gpg \
    --include="$PACKAGES" \
    "$DISTRO" \
    "$TARGET_DIR" \
    "$MIRROR"

echo "=== 2. Config (Second Stage) ==="
# 复制 QEMU
sudo cp /usr/bin/qemu-loongarch64-static "$TARGET_DIR/usr/bin/"

# 运行第二阶段配置
sudo chroot "$TARGET_DIR" /debootstrap/debootstrap --second-stage

echo "=== 3. Clean & Fix ==="
# 清理缓存
sudo rm -rf "$TARGET_DIR/var/cache/apt/archives/*"
sudo rm "$TARGET_DIR/usr/bin/qemu-loongarch64-static"

# 修复软链接 (至关重要)
echo "Fixing symlinks to relative paths..."
if [ -f "scripts/fix_links.py" ]; then
    sudo python3 scripts/fix_links.py "$TARGET_DIR"
else
    echo "Warning: scripts/fix_links.py not found, skipping symlink fix!"
fi

echo "=== 4. Package ==="
TAR_NAME="debian-${DISTRO}-${ARCH}-sysroot.tar.gz"
sudo tar -czf "$TAR_NAME" -C "$TARGET_DIR" .
sudo chown $USER:$USER "$TAR_NAME"

echo "Build Success! Artifact: $TAR_NAME"
