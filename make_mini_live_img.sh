#!/usr/bin/env bash
# ===================================================================
# Berry Router - Mini Fork All-In-One Live Disk Image Builder
# ===================================================================

set -e

IMG_NAME="berry-mini-fork.img"
IMG_SIZE_MB=3500
WORK_DIR="mini_fork_build"
DEB_PKG="berry-router-engine_1.2.0_all.deb"

echo "📦 Pre-flight check: Verifying Linux kernel availability..."
KERNEL_PATH=$(ls -1 /vmlinuz /boot/vmlinuz-* 2>/dev/null | head -n 1 || true)
INITRD_PATH=$(ls -1 /initrd.img /boot/initrd.img-* 2>/dev/null | head -n 1 || true)

if [ -z "$KERNEL_PATH" ] || [ -z "$INITRD_PATH" ]; then
    echo "⚠️ Kernel/Initrd not found in build environment (WSL/Container detected)."
    echo "📥 Installing linux-image-generic..."
    sudo apt update && sudo apt install -y linux-image-generic
    KERNEL_PATH=$(ls -1 /boot/vmlinuz-* | head -n 1)
    INITRD_PATH=$(ls -1 /boot/initrd.img-* | head -n 1)
fi

echo "📦 Checking required image building tools..."
REQUIRED_TOOLS=("parted" "losetup" "mkfs.vfat" "mkfs.ext4" "mksquashfs" "arping")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "❌ Installing missing tool: $tool..."
        sudo apt update && sudo apt install -y parted dosfstools e2fsprogs squashfs-tools grub-efi-amd64-bin shim-signed iputils-arping
        break
    fi
done

# Build underlying DEB package if missing
if [ ! -f "$DEB_PKG" ]; then
    echo "🔨 Building underlying .deb package first..."
    bash make_deb.sh
fi

echo "🚀 Cleaning previous build workspace..."
sudo rm -rf "${WORK_DIR}" "$IMG_NAME"
mkdir -p "${WORK_DIR}/squashfs-root"
mkdir -p "${WORK_DIR}/boot"
mkdir -p "${WORK_DIR}/persistence"

echo "💾 Allocating ${IMG_SIZE_MB}MB disk image..."
dd if=/dev/zero of="$IMG_NAME" bs=1M count=0 seek=$IMG_SIZE_MB status=none

echo "🔪 Creating partition table..."
parted -s "$IMG_NAME" mklabel gpt
parted -s "$IMG_NAME" mkpart "BOOT" fat32 1MiB 2500MiB
parted -s "$IMG_NAME" set 1 boot on
parted -s "$IMG_NAME" set 1 esp on
parted -s "$IMG_NAME" mkpart "persistence" ext4 2500MiB 100%

LOOP_DEV=$(sudo losetup -fP --show "$IMG_NAME")
PART_BOOT="${LOOP_DEV}p1"
PART_PERSIST="${LOOP_DEV}p2"

cleanup() {
    echo "🧹 Cleaning up loop mounts..."
    sudo umount "${WORK_DIR}/boot" 2>/dev/null || true
    sudo umount "${WORK_DIR}/persistence" 2>/dev/null || true
    sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
}
trap cleanup EXIT

echo "💾 Formatting partitions..."
sudo mkfs.vfat -F 32 -n "BERRY_BOOT" "$PART_BOOT" > /dev/null
sudo mkfs.ext4 -F -L "persistence" "$PART_PERSIST" > /dev/null

sudo mount "$PART_BOOT" "${WORK_DIR}/boot"
sudo mount "$PART_PERSIST" "${WORK_DIR}/persistence"

# Configure OverlayFS persistence
echo "/ union" | sudo tee "${WORK_DIR}/persistence/persistence.conf" > /dev/null

# Copy Kernel, Initrd & GRUB
sudo mkdir -p "${WORK_DIR}/boot/live"
sudo mkdir -p "${WORK_DIR}/boot/EFI/BOOT"
sudo mkdir -p "${WORK_DIR}/boot/boot/grub"

sudo cp "$KERNEL_PATH" "${WORK_DIR}/boot/live/vmlinuz"
sudo cp "$INITRD_PATH" "${WORK_DIR}/boot/live/initrd.img"

# Compress SquashFS filesystem
cp "$DEB_PKG" "${WORK_DIR}/squashfs-root/"
cat << 'INSTALL_INSIDE' > "${WORK_DIR}/squashfs-root/install.sh"
#!/bin/sh
dpkg -i /berry-router-engine_1.2.0_all.deb || apt-get install -f -y
rm -f /berry-router-engine_1.2.0_all.deb /install.sh
INSTALL_INSIDE
chmod +x "${WORK_DIR}/squashfs-root/install.sh"

sudo mksquashfs "${WORK_DIR}/squashfs-root" "${WORK_DIR}/boot/live/filesystem.squashfs" -comp xz > /dev/null

# Configure GRUB menu
cat << 'GRUB_EOF' | sudo tee "${WORK_DIR}/boot/boot/grub/grub.cfg" > /dev/null
set default=0
set timeout=3

menuentry "🌐 Berry Mini Fork Live Router (Persistent)" {
    linux /live/vmlinuz boot=live persistence quiet splash net.ifnames=0 biosdevname=0
    initrd /live/initrd.img
}
GRUB_EOF

sudo cp "${WORK_DIR}/boot/boot/grub/grub.cfg" "${WORK_DIR}/boot/EFI/BOOT/grub.cfg"

# Copy EFI Shim/GRUB binaries
SHIM_BIN=$(ls -1 /usr/lib/shim/shimx64.efi.signed /usr/lib/shim/shimx64.efi 2>/dev/null | head -n 1 || true)
GRUB_SIGNED_BIN=$(ls -1 /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed 2>/dev/null | head -n 1 || true)

if [ -n "$SHIM_BIN" ] && [ -n "$GRUB_SIGNED_BIN" ]; then
    sudo cp "$SHIM_BIN" "${WORK_DIR}/boot/EFI/BOOT/BOOTX64.EFI"
    sudo cp "$GRUB_SIGNED_BIN" "${WORK_DIR}/boot/EFI/BOOT/grubx64.efi"
fi

echo ""
echo "==================================================================="
echo "🎉 SUCCESS! Built Mini Fork Disk Image: ${IMG_NAME}"
echo "==================================================================="
