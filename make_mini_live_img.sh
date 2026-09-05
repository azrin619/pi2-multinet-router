### REMOVE IF U JUST DO MANUAL IN LINUX cat << 'EOF' > make_mini_live_iso.sh
#!/usr/bin/env bash
set -e

ISO_DIR="iso_workspace"
OUTPUT_ISO="berry-router-engine-1.2.0.iso"
SQUASH_DIR="squashfs_root"

echo "==================================================================="
echo "🚀 Starting Berry Router Classic ISO Build (4GB+ Fix Applied)"
echo "==================================================================="

if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root: sudo ./make_mini_live_iso.sh"
  exit 1
fi

echo "🧹 [1/7] Cleaning up previous workspace folders..."
rm -rf "$ISO_DIR" "$OUTPUT_ISO" "$SQUASH_DIR"
mkdir -v -p "$ISO_DIR/isolinux" "$ISO_DIR/live" "$SQUASH_DIR"

echo "📦 [2/7] Installing dependencies..."
apt update && apt install -y squashfs-tools isolinux syslinux-utils genisoimage live-boot casper rsync

echo "🔨 [3/7] Building Debian package..."
bash make_deb.sh

echo "📁 [4/7] Copying clean OS root (excluding /home and large files)..."
rsync -av --progress \
  --exclude=/proc \
  --exclude=/sys \
  --exclude=/dev \
  --exclude=/tmp \
  --exclude=/run \
  --exclude=/mnt \
  --exclude=/media \
  --exclude=/lost+found \
  --exclude=/var/cache \
  --exclude=/home/* \
  --exclude="squashfs_root" \
  --exclude="iso_workspace" \
  --exclude="*.iso" \
  --exclude="*.vhdx" \
  --exclude="*.vdi" \
  / "$SQUASH_DIR/"

echo "⚙️ [5/7] Injecting Berry Router scripts and strict IPv4 rules..."
mkdir -v -p "$SQUASH_DIR/usr/local/bin"
cp -v src/*.py "$SQUASH_DIR/usr/local/bin/" 2>/dev/null || true
cp -v src/*.sh "$SQUASH_DIR/usr/local/bin/" 2>/dev/null || true
chmod +x "$SQUASH_DIR/usr/local/bin/"*

# Ensure root directory exists for live-boot
mkdir -p "$SQUASH_DIR/root" "$SQUASH_DIR/home"

cat << 'SYS_EOF' > "$SQUASH_DIR/etc/sysctl.d/99-disable-ipv6.conf"
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
SYS_EOF

echo "🗜️ [6/7] Compressing SquashFS OS image..."
mksquashfs "$SQUASH_DIR" "$ISO_DIR/live/filesystem.squashfs" -comp xz

echo "💿 [7/7] Generating ISO with Large File Support (-allow-limited-size)..."
CP_KERNEL=$(ls -1 /boot/vmlinuz-* | tail -n 1)
CP_INITRD=$(ls -1 /boot/initrd.img-* | tail -n 1)

cp -v "$CP_KERNEL" "$ISO_DIR/isolinux/vmlinuz"
cp -v "$CP_INITRD" "$ISO_DIR/isolinux/initrd.img"

cp -v /usr/lib/ISOLINUX/isolinux.bin "$ISO_DIR/isolinux/"
cp -v /usr/lib/syslinux/modules/bios/ldlinux.c32 "$ISO_DIR/isolinux/" 2>/dev/null || true
cp -v /usr/lib/syslinux/modules/bios/libcom32.c32 "$ISO_DIR/isolinux/" 2>/dev/null || true
cp -v /usr/lib/syslinux/modules/bios/libutil.c32 "$ISO_DIR/isolinux/" 2>/dev/null || true
cp -v /usr/lib/syslinux/modules/bios/vesamenu.c32 "$ISO_DIR/isolinux/" 2>/dev/null || true

cat << 'ISOLINUX_EOF' > "$ISO_DIR/isolinux/isolinux.cfg"
DEFAULT berry
PROMPT 0
TIMEOUT 50

LABEL berry
  MENU LABEL Berry Router Engine v1.2.0 (IPv4 Strict)
  KERNEL /isolinux/vmlinuz
  APPEND initrd=/isolinux/initrd.img boot=live components ipv6.disable=1 net.ipv6.conf.all.disable_ipv6=1 quiet splash
ISOLINUX_EOF

# -iso-level 3 and -allow-limited-size enable files larger than 4GB
genisoimage -v -J -R -iso-level 3 -allow-limited-size -V "BERRY_ROUTER" \
  -b isolinux/isolinux.bin \
  -c isolinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -o "$OUTPUT_ISO" "$ISO_DIR"

isohybrid -v "$OUTPUT_ISO"

rm -rf "$ISO_DIR" "$SQUASH_DIR"

echo "==================================================================="
echo "🎉 SUCCESS! Clean ISO built: $OUTPUT_ISO"
echo "==================================================================="
EOF
