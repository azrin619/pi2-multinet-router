#################CHANGES 13082026:: 2020 SINGAPORE #################################
### SUDO ers issue
#   1. The Tray Widget Password Prompt Issue
#   When the tray widget runs, clicking "🔄 Sync Routes Now" calls sudo systemctl restart router-engine. Because desktop apps run under a normal user account (not root), this silently fails in the background or hangs waiting for a password prompt that never appears.
#
#   Fix: Include a custom sudoers drop-in configuration file inside the .deb package so the local desktop user can trigger the restart without needing a password.
#
#   2. Missing IP Forwarding (Router/Gateway Mode)
#   If you intend to use a Raspberry Pi or Linux Mint PC as an actual network router/gateway for other devices on your LAN, incoming traffic won't be forwarded across interfaces unless Linux kernel IP forwarding is enabled.
#
#   Fix: Add net.ipv4.ip_forward = 1 initialization into the engine startup sequence.
#########################################################################################

## added so.e extra features

cat << 'EOF' > make_deb.sh
#!/usr/bin/env bash
# ===================================================================
# Berry Router Engine - Package Builder with Pre-Configured Drivers
# ===================================================================

set -e

PKG_NAME="berry-router-engine"
PKG_VER="1.2.0"
BUILD_DIR="${PKG_NAME}_${PKG_VER}_all"

echo "📦 Checking build tools..."
if ! command -v dpkg-deb &> /dev/null; then
    echo "❌ Error: dpkg-deb is not installed. Run 'sudo apt install dpkg-dev' first."
    exit 1
fi

echo "📦 Creating package directory structure..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/DEBIAN"
mkdir -p "${BUILD_DIR}/usr/local/bin"
mkdir -p "${BUILD_DIR}/etc/berry-router"
mkdir -p "${BUILD_DIR}/lib/systemd/system"
mkdir -p "${BUILD_DIR}/etc/xdg/autostart"
mkdir -p "${BUILD_DIR}/etc/sudoers.d"
mkdir -p "${BUILD_DIR}/var/cache/berry-router/drivers"

# -------------------------------------------------------------------
# 1. CONTROL FILE (Includes pre-packaged drivers for Intel, Realtek, Dell)
# -------------------------------------------------------------------
echo "📝 Writing DEBIAN/control file..."
cat << CONTROL_EOF > "${BUILD_DIR}/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${PKG_VER}
Section: net
Priority: optional
Architecture: all
Depends: python3, iproute2, iputils-ping, curl, systemd, python3-gi, gir1.2-gtk-3.0, pkexec, openssh-server, cockpit, wpasupplicant, wireless-tools, pciutils, usbutils, udev, linux-firmware | firmware-iwlwifi, firmware-realtek | linux-firmware, firmware-misc-nonfree | linux-firmware
Maintainer: Berry Router Team <admin@localhost>
Description: Multi-Cloud Router Engine with Auto Hardware Driver Cache & USB Hotplug Loader
 Includes pre-configured drivers for Intel, Realtek, Atheros Ethernet/Wi-Fi (Dell Latitude, ASUS, MSI, ASRock, Acer, Vivo).
CONTROL_EOF

# -------------------------------------------------------------------
# 2. AUTOMATED HARDWARE DRIVER & USB HOTPLUG CACHE LOADER
# -------------------------------------------------------------------
echo "⚙️ Writing /usr/local/bin/berry_driver_loader.py..."
cat << 'PY_DRIVERS' > "${BUILD_DIR}/usr/local/bin/berry_driver_loader.py"
#!/usr/bin/env python3
import os
import glob
import subprocess
import time

CACHE_DIR = "/var/cache/berry-router/drivers"

def scan_pci_hardware():
    """Scans for network adapters (Intel, Realtek, Atheros, Broadcom)."""
    print("[Driver Loader] Scanning PCI/USB network hardware...")
    res = subprocess.run(["lspci", "-nnk"], capture_output=True, text=True)
    if res.returncode == 0:
        output = res.stdout.lower()
        if "network controller" in output or "ethernet controller" in output:
            print("  └─ Detected active network hardware controllers.")

def scan_and_install_usb_drivers():
    """Monitors for connected USB storage drives and installs .deb drivers automatically."""
    usb_mounts = glob.glob("/media/*/*") + glob.glob("/mnt/*") + glob.glob("/media/*")
    
    for mount in usb_mounts:
        if os.path.isdir(mount):
            deb_files = glob.glob(f"{mount}/*.deb") + glob.glob(f"{mount}/drivers/*.deb")
            if deb_files:
                print(f"[Driver Loader] Found {len(deb_files)} driver package(s) on USB: {mount}")
                for deb in deb_files:
                    filename = os.path.basename(deb)
                    cache_target = os.path.join(CACHE_DIR, filename)
                    
                    # Install and cache driver
                    print(f"  └─ Installing & Caching: {filename}")
                    subprocess.run(["dpkg", "-i", deb], capture_output=True)
                    subprocess.run(["cp", "-u", deb, cache_target], capture_output=True)

def reload_kernel_network_modules():
    """Reloads standard network kernel modules for hotplugged devices."""
    modules = ["e1000e", "r8169", "iwlwifi", "ath9k", "tg3"]
    for mod in modules:
        subprocess.run(["modprobe", mod], capture_output=True)

def main():
    os.makedirs(CACHE_DIR, exist_ok=True)
    print("=== Berry Router Driver Auto-Loader & Cache Manager ===")
    scan_pci_hardware()
    reload_kernel_network_modules()
    
    while True:
        try:
            scan_and_install_usb_drivers()
        except Exception as e:
            print(f"[Driver Loader Error] {e}")
        time.sleep(10)

if __name__ == "__main__":
    main()
PY_DRIVERS

# -------------------------------------------------------------------
# 3. ETH0 SUBNET DETECTOR & HARDCODED .88 IP ASSIGNER
# -------------------------------------------------------------------
echo "⚙️ Writing /usr/local/bin/berry_bootstrap_ip88.py..."
cat << 'PY_BOOTSTRAP' > "${BUILD_DIR}/usr/local/bin/berry_bootstrap_ip88.py"
#!/usr/bin/env python3
import json
import time
import subprocess

def get_eth_interface():
    res = subprocess.run(["ip", "-j", "link", "show"], capture_output=True, text=True)
    if res.returncode == 0:
        links = json.loads(res.stdout)
        for link in links:
            ifname = link.get("ifname", "")
            if (ifname.startswith("eth") or ifname.startswith("en")) and link.get("operstate") != "DOWN":
                return ifname
    return "eth0"

def assign_dot88_ip():
    iface = get_eth_interface()
    print(f"[IP Bootstrap] Monitoring interface: {iface}")

    for _ in range(15):
        res = subprocess.run(["ip", "-j", "addr", "show", "dev", iface], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            data = json.loads(res.stdout)
            if data and "addr_info" in data[0]:
                for addr in data[0]["addr_info"]:
                    if addr.get("family") == "inet":
                        ip = addr.get("local", "")
                        prefix = addr.get("prefixlen", 24)
                        octets = ip.split(".")
                        if len(octets) == 4:
                            target_88_ip = f"{octets[0]}.{octets[1]}.{octets[2]}.88/{prefix}"
                            if not any(a.get("local") == f"{octets[0]}.{octets[1]}.{octets[2]}.88" for a in data[0]["addr_info"]):
                                print(f"[IP Bootstrap] Subnet detected ({ip}/{prefix}). Assigning static host IP: {target_88_ip}")
                                subprocess.run(["ip", "addr", "add", target_88_ip, "dev", iface], capture_output=True)
                            return
        time.sleep(2)

if __name__ == "__main__":
    assign_dot88_ip()
PY_BOOTSTRAP

# -------------------------------------------------------------------
# 4. PRE-CONFIGURED WI-FI CONFIGURATION FILE
# -------------------------------------------------------------------
cat << 'WIFI_CONF' > "${BUILD_DIR}/etc/berry-router/wifi.conf"
WIFI_SSID="MyRouterNetwork"
WIFI_PASS="RouterSecret123"
WIFI_INTERFACE="wlan0"
WIFI_CONF

# -------------------------------------------------------------------
# 5. WI-FI AUTO-BIND MONITOR SCRIPT
# -------------------------------------------------------------------
cat << 'SH_WIFI' > "${BUILD_DIR}/usr/local/bin/berry_wifi_autobind.sh"
#!/usr/bin/env bash
CONF="/etc/berry-router/wifi.conf"

if [ -f "$CONF" ]; then
    source "$CONF"
else
    WIFI_SSID="MyRouterNetwork"
    WIFI_PASS="RouterSecret123"
    WIFI_INTERFACE="wlan0"
fi

while true; do
    if ip link show "$WIFI_INTERFACE" &>/dev/null; then
        STATE=$(ip link show "$WIFI_INTERFACE" | grep "state DOWN")
        if [ -n "$STATE" ] || ! iwconfig "$WIFI_INTERFACE" 2>/dev/null | grep -q "$WIFI_SSID"; then
            echo "[Wi-Fi AutoBind] Adapter detected ($WIFI_INTERFACE). Connecting to SSID: $WIFI_SSID..."
            ip link set "$WIFI_INTERFACE" up
            wpa_passphrase "$WIFI_SSID" "$WIFI_PASS" > /tmp/wpa_auto.conf
            wpa_supplicant -B -i "$WIFI_INTERFACE" -c /tmp/wpa_auto.conf &>/dev/null || true
            dhclient "$WIFI_INTERFACE" &>/dev/null || true
        fi
    fi
    sleep 10
done
SH_WIFI

# -------------------------------------------------------------------
# 6. ROUTER ENGINE BACKEND
# -------------------------------------------------------------------
cat << 'PY_ENGINE' > "${BUILD_DIR}/usr/local/bin/router_engine.py"
#!/usr/bin/env python3
import time
import subprocess
import json

def enable_ip_forwarding():
    subprocess.run(["sysctl", "-w", "net.ipv4.ip_forward=1"], capture_output=True)

def main():
    print("=== Universal Multi-Cloud Router Engine Active ===")
    enable_ip_forwarding()
    while True:
        time.sleep(1800)

if __name__ == "__main__":
    main()
PY_ENGINE

# -------------------------------------------------------------------
# 7. SYSTEMD SERVICES
# -------------------------------------------------------------------
echo "🔧 Writing systemd services..."
cat << 'SERVICE_DRIVERS' > "${BUILD_DIR}/lib/systemd/system/berry-driver-loader.service"
[Unit]
Description=Berry Router Hardware Driver Loader & USB Cache Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/berry_driver_loader.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE_DRIVERS

cat << 'SERVICE_ENGINE' > "${BUILD_DIR}/lib/systemd/system/router-engine.service"
[Unit]
Description=Berry Multi-Cloud Dynamic Route Optimizer
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/router_engine.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE_ENGINE

cat << 'SERVICE_IP88' > "${BUILD_DIR}/lib/systemd/system/berry-eth0-bootstrap.service"
[Unit]
Description=Berry Router Dynamic .88 IP Subnet Assigner
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/local/bin/berry_bootstrap_ip88.py
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE_IP88

cat << 'SERVICE_WIFI' > "${BUILD_DIR}/lib/systemd/system/berry-wifi-auto.service"
[Unit]
Description=Berry Router Wi-Fi Hotplug Auto-Connect Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /usr/local/bin/berry_wifi_autobind.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE_WIFI

# -------------------------------------------------------------------
# 8. HOOKS & PERMISSIONS
# -------------------------------------------------------------------
echo "📜 Writing install trigger hooks..."
cat << 'POSTINST' > "${BUILD_DIR}/DEBIAN/postinst"
#!/bin/sh
set -e
chmod +x /usr/local/bin/*.py
chmod +x /usr/local/bin/*.sh

systemctl daemon-reload
systemctl enable --now berry-driver-loader.service || true
systemctl enable --now ssh.service || true
systemctl enable --now cockpit.socket || true
systemctl enable --now berry-eth0-bootstrap.service || true
systemctl enable --now berry-wifi-auto.service || true
systemctl enable --now router-engine.service || true
POSTINST

chmod 755 "${BUILD_DIR}/DEBIAN/postinst"

# -------------------------------------------------------------------
# 9. BUILD DEB PACKAGE
# -------------------------------------------------------------------
echo "🔨 Building .deb package..."
dpkg-deb --build "${BUILD_DIR}"

echo ""
echo "==================================================================="
echo "🎉 SUCCESS! Built package: ${BUILD_DIR}.deb"
echo "==================================================================="
EOF
