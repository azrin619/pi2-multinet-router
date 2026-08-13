cat << 'EOF' > make_uefi_iso.sh
#!/usr/bin/env bash
# ===================================================================
# Berry Router - Pure UEFI Bootable Live ISO Builder
# Compatible with UEFI-only hardware (Dell, ASUS, MSI, Acer, Intel)
# ===================================================================

set -e

ISO_NAME="berry-router-uefi-1.2.0-x86_64.iso"
WORK_DIR="uefi_iso_build"
DEB_PKG="berry-router-engine_1.2.0_all.deb"

echo "📦 Checking required UEFI build tools..."
REQUIRED_TOOLS=("xorriso" "grub-mkrescue" "mtools" "squashfs-tools")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "❌ Missing tool: $tool. Installing build tools..."
        sudo apt update && sudo apt install -y xorriso grub-pc-bin grub-efi-amd64-bin mtools squashfs-tools
        break
    fi
done

# Step 1: Ensure .deb package is built
if [ ! -f "$DEB_PKG" ]; then
    echo "🔨 Building underlying .deb package first..."
    bash make_deb.sh
fi

echo "🚀 Preparing UEFI ISO directory layout..."
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}/iso/boot/grub"
mkdir -p "${WORK_DIR}/iso/EFI/BOOT"
mkdir -p "${WORK_DIR}/iso/live"
mkdir -p "${WORK_DIR}/squashfs-root/var/cache/berry-router/drivers"

# Step 2: Configure UEFI GRUB Bootloader
echo "⚙️ Writing UEFI GRUB configuration (grub.cfg)..."
cat << 'GRUB_EOF' > "${WORK_DIR}/iso/boot/grub/grub.cfg"
set default=0
set timeout=5

menuentry "🌐 Berry Multi-Cloud Router (UEFI Live System)" {
    linux /live/vmlinuz boot=live quiet splash net.ifnames=0 biosdevname=0
    initrd /live/initrd.img
}

menuentry "⚡ Berry Multi-Cloud Router (UEFI Live - RAM Mode)" {
    linux /live/vmlinuz boot=live toram quiet splash net.ifnames=0 biosdevname=0
    initrd /live/initrd.img
}

menuentry "🛠️ System Utilities - UEFI Shell" {
    chainloader /EFI/BOOT/shellx64.efi
}
GRUB_EOF

# Step 3: Inject Kernel, Initrd, and Berry Engine Package
echo "📦 Injecting Linux kernel and Berry Router dependencies..."
KERNEL_PATH=$(ls -1 /vmlinuz 2>/dev/null || ls -1 /boot/vmlinuz-* | head -n 1)
INITRD_PATH=$(ls -1 /initrd.img 2>/dev/null || ls -1 /boot/initrd.img-* | head -n 1)

cp "$KERNEL_PATH" "${WORK_DIR}/iso/live/vmlinuz"
cp "$INITRD_PATH" "${WORK_DIR}/iso/live/initrd.img"

# Pre-install Berry Engine into the Live ISO SquashFS root
cp "$DEB_PKG" "${WORK_DIR}/squashfs-root/"
echo "Installing $DEB_PKG into ISO filesystem root..."
cat << 'INSTALL_INSIDE' > "${WORK_DIR}/squashfs-root/install.sh"
#!/bin/sh
dpkg -i /berry-router-engine_1.2.0_all.deb || apt-get install -f -y
rm -f /berry-router-engine_1.2.0_all.deb /install.sh
INSTALL_INSIDE
chmod +x "${WORK_DIR}/squashfs-root/install.sh"

# Compress into Live SquashFS Image
echo "🗜️ Creating SquashFS filesystem..."
mksquashfs "${WORK_DIR}/squashfs-root" "${WORK_DIR}/iso/live/filesystem.squashfs" -comp xz

# Step 4: Build UEFI Hybrid ISO with grub-mkrescue
echo "💿 Generating UEFI ISO image..."
grub-mkrescue -o "$ISO_NAME" "${WORK_DIR}/iso" \
    -- -volid "BERRY_UEFI" \
    -efi-boot-part --efi-boot-image

echo ""
echo "==================================================================="
echo "🎉 SUCCESS! Built UEFI ISO: ${ISO_NAME}"
echo "👉 Flash to USB drive using Rufus (DD Mode) or dd:"
echo "   sudo dd if=${ISO_NAME} of=/dev/sdX status=progress bs=4M"
echo "==================================================================="
EOF
chmod +x make_uefi_iso.sh
