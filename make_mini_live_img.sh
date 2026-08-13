cat << 'EOF' > make_mini_live_img.sh
#!/usr/bin/env bash
# ===================================================================
# Berry Router - Mini Fog All-In-One Live Disk Image Builder
# Creates a raw .img with pre-baked SSH keys, configs, and drivers
# ===================================================================

set -e

IMG_NAME="berry-mini-fog.img"
IMG_SIZE_MB=3500
WORK_DIR="mini_fog_build"
DEB_PKG="berry-router-engine_1.2.0_all.deb"

echo "📦 Checking required image building tools..."
REQUIRED_TOOLS=("parted" "losetup" "mkfs.vfat" "mkfs.ext4" "mksquashfs" "grub-install")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "❌ Missing tool: $tool. Installing build tools..."
        sudo apt update && sudo apt install -y parted dosfstools e2fsprogs squashfs-tools grub-efi-amd64-bin shim-signed
        break
    fi
done

# Step 1: Ensure .deb package exists
if [ ! -f "$DEB_PKG" ]; then
    echo "🔨 Building underlying .deb package first..."
    bash make_deb.sh
fi

echo "🚀 Cleaning previous build artifacts..."
sudo rm -rf "${WORK_DIR}" "$IMG_NAME"
mkdir -p "${WORK_DIR}/squashfs-root"
mkdir -p "${WORK_DIR}/boot"
mkdir -p "${WORK_DIR}/persistence"

# Step 2: Create raw sparse image file
echo "💾 Allocating ${IMG_SIZE_MB}MB image file: ${IMG_NAME}..."
dd if=/dev/zero of="$IMG_NAME" bs=1M count=0 seek=$IMG_SIZE_MB status=none

# Step 3: Partition image (GPT: 2.5GB FAT32 Boot + Remaining EXT4 Persistence)
echo "🔪 Partitioning image (GPT layout)..."
parted -s "$IMG_NAME" mklabel gpt
parted -s "$IMG_NAME" mkpart "BOOT" fat32 1MiB 2500MiB
parted -s "$IMG_NAME" set 1 boot on
parted -s "$IMG_NAME" set 1 esp on
parted -s "$IMG_NAME" mkpart "persistence" ext4 2500MiB 100%

# Step 4: Attach loop device
echo "🔗 Attaching loopback device..."
LOOP_DEV=$(sudo losetup -fP --show "$IMG_NAME")
PART_BOOT="${LOOP_DEV}p1"
PART_PERSIST="${LOOP_DEV}p2"

cleanup() {
    echo "🧹 Detaching loop device and cleaning up..."
    sudo umount "${WORK_DIR}/boot" 2>/dev/null || true
    sudo umount "${WORK_DIR}/persistence" 2>/dev/null || true
    sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
}
trap cleanup EXIT

# Step 5: Format partitions
echo "💾 Formatting Partition 1 (FAT32 Boot)..."
sudo mkfs.vfat -F 32 -n "BERRY_BOOT" "$PART_BOOT" > /dev/null

echo "💾 Formatting Partition 2 (EXT4 Persistence)..."
sudo mkfs.ext4 -F -L "persistence" "$PART_PERSIST" > /dev/null

# Step 6: Mount partitions
sudo mount "$PART_BOOT" "${WORK_DIR}/boot"
sudo mount "$PART_PERSIST" "${WORK_DIR}/persistence"

# -------------------------------------------------------------------
# STEP 7: PRE-BAKE CONFIGURATIONS & KEYS INTO PERSISTENCE PARTITION
# -------------------------------------------------------------------
echo "⚙️ Pre-baking SSH keys, configs, and runtime settings into Persistence Overlay..."

# Enable full system persistence
echo "/ union" | sudo tee "${WORK_DIR}/persistence/persistence.conf" > /dev/null

# Create overlay directory trees
sudo mkdir -p "${WORK_DIR}/persistence/etc/berry-router"
sudo mkdir -p "${WORK_DIR}/persistence/etc/ssh"
sudo mkdir -p "${WORK_DIR}/persistence/root/.ssh"
sudo mkdir -p "${WORK_DIR}/persistence/var/cache/berry-router/drivers"

# 1. Bake Wi-Fi Credentials
cat << 'WIFI_CONF' | sudo tee "${WORK_DIR}/persistence/etc/berry-router/wifi.conf" > /dev/null
WIFI_SSID="MyRouterNetwork"
WIFI_PASS="RouterSecret123"
WIFI_INTERFACE="wlan0"
WIFI_CONF

# 2. Bake SSH Public Key (Pulls host key if available, or generates a default)
if [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    echo "🔑 Injecting host public key ($HOME/.ssh/id_rsa.pub) into root authorized_keys..."
    cat "$HOME/.ssh/id_rsa.pub" | sudo tee "${WORK_DIR}/persistence/root/.ssh/authorized_keys" > /dev/null
elif [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    echo "🔑 Injecting host public key ($HOME/.ssh/id_ed25519.pub) into root authorized_keys..."
    cat "$HOME/.ssh/id_ed25519.pub" | sudo tee "${WORK_DIR}/persistence/root/.ssh/authorized_keys" > /dev/null
else
    echo "🔑 Generating new SSH keypair for Live root access..."
    ssh-keygen -t ed25519 -f "${WORK_DIR}/fog_root_key" -N "" -q
    cat "${WORK_DIR}/fog_root_key.pub" | sudo tee "${WORK_DIR}/persistence/root/.ssh/authorized_keys" > /dev/null
    echo "  └─ Saved private SSH key to: ./mini_fog_build/fog_root_key"
fi
sudo chmod 700 "${WORK_DIR}/persistence/root/.ssh"
sudo chmod 600 "${WORK_DIR}/persistence/root/.ssh/authorized_keys"

# 3. Pre-generate SSH Host Keys (prevents host-key verification warnings on reboots)
sudo ssh-keygen -A -f "${WORK_DIR}/persistence" > /dev/null 2>&1 || true

# -------------------------------------------------------------------
# STEP 8: BUILD AND COPY LIVE OS FILES TO BOOT PARTITION
# -------------------------------------------------------------------
echo "📦 Packing Live SquashFS and Kernel..."
KERNEL_PATH=$(ls -1 /vmlinuz /boot/vmlinuz-* 2>/dev/null | head -n 1)
INITRD_PATH=$(ls -1 /initrd.img /boot/initrd.img-* 2>/dev/null | head -n 1)

sudo mkdir -p "${WORK_DIR}/boot/live"
sudo mkdir -p "${WORK_DIR}/boot/EFI/BOOT"
sudo mkdir -p "${WORK_DIR}/boot/boot/grub"

sudo cp "$KERNEL_PATH" "${WORK_DIR}/boot/live/vmlinuz"
sudo cp "$INITRD_PATH" "${WORK_DIR}/boot/live/initrd.img"

# Install Berry Engine package inside SquashFS
cp "$DEB_PKG" "${WORK_DIR}/squashfs-root/"
cat << 'INSTALL_INSIDE' > "${WORK_DIR}/squashfs-root/install.sh"
#!/bin/sh
dpkg -i /berry-router-engine_1.2.0_all.deb || apt-get install -f -y
rm -f /berry-router-engine_1.2.0_all.deb /install.sh
INSTALL_INSIDE
chmod +x "${WORK_DIR}/squashfs-root/install.sh"

sudo mksquashfs "${WORK_DIR}/squashfs-root" "${WORK_DIR}/boot/live/filesystem.squashfs" -comp xz > /dev/null

# Configure GRUB for Persistence Live Boot
echo "⚙️ Writing GRUB bootloader menu..."
cat << 'GRUB_EOF' | sudo tee "${WORK_DIR}/boot/boot/grub/grub.cfg" > /dev/null
set default=0
set timeout=3

menuentry "🌐 Berry Mini Fog Live Router (Persistent)" {
    linux /live/vmlinuz boot=live persistence quiet splash net.ifnames=0 biosdevname=0
    initrd /live/initrd.img
}

menuentry "⚡ Berry Mini Fog Live Router (RAM / Read-Only)" {
    linux /live/vmlinuz boot=live toram quiet splash net.ifnames=0 biosdevname=0
    initrd /live/initrd.img
}
GRUB_EOF

# Copy GRUB config to EFI path
sudo cp "${WORK_DIR}/boot/boot/grub/grub.cfg" "${WORK_DIR}/boot/EFI/BOOT/grub.cfg"

# Copy EFI Binaries (Shim + GRUB)
SHIM_BIN=$(ls -1 /usr/lib/shim/shimx64.efi.signed /usr/lib/shim/shimx64.efi 2>/dev/null | head -n 1)
GRUB_SIGNED_BIN=$(ls -1 /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed /usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed 2>/dev/null | head -n 1)

if [ -n "$SHIM_BIN" ] && [ -n "$GRUB_SIGNED_BIN" ]; then
    sudo cp "$SHIM_BIN" "${WORK_DIR}/boot/EFI/BOOT/BOOTX64.EFI"
    sudo cp "$GRUB_SIGNED_BIN" "${WORK_DIR}/boot/EFI/BOOT/grubx64.efi"
fi

echo ""
echo "==================================================================="
echo "🎉 SUCCESS! Built Mini Fog Live Disk Image:"
echo "   👉 ${IMG_NAME}"
echo "==================================================================="
echo "📌 Flash to physical USB:"
echo "   sudo dd if=${IMG_NAME} of=/dev/sdX status=progress bs=4M"
echo ""
echo "📌 Or test directly in QEMU VM:"
echo "   qemu-system-x86_64 -enable-kvm -m 2048 -hda ${IMG_NAME} -bios /usr/share/ovmf/OVMF.fd"
echo "==================================================================="
EOF
chmod +x make_mini_live_img.sh
