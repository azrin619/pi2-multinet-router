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


cat << 'EOF' > make_deb.sh
#!/usr/bin/env bash
# ===================================================================
# Berry Router Engine - Automated .deb Package Builder
# ===================================================================

set -e

PKG_NAME="berry-router-engine"
PKG_VER="1.0.0"
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
mkdir -p "${BUILD_DIR}/lib/systemd/system"
mkdir -p "${BUILD_DIR}/etc/xdg/autostart"
mkdir -p "${BUILD_DIR}/etc/sudoers.d"

# -------------------------------------------------------------------
# 1. CONTROL FILE
# -------------------------------------------------------------------
echo "📝 Writing DEBIAN/control file..."
cat << CONTROL_EOF > "${BUILD_DIR}/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${PKG_VER}
Section: net
Priority: optional
Architecture: all
Depends: python3, iproute2, iputils-ping, curl, systemd, python3-gi, gir1.2-gtk-3.0, pkexec
Maintainer: Berry Router Team <admin@localhost>
Description: Multi-Cloud and Regional Routing Engine with Tray Indicator
 Dynamic route optimizer for AWS, Azure, GCP, Aliyun, Oracle, and Telco
 networks with real-time desktop tray indicators.
CONTROL_EOF

# -------------------------------------------------------------------
# 2. ROUTER ENGINE BACKEND
# -------------------------------------------------------------------
echo "⚙️ Writing /usr/local/bin/router_engine.py..."
cat << 'PY_ENGINE' > "${BUILD_DIR}/usr/local/bin/router_engine.py"
#!/usr/bin/env python3
import time
import subprocess
import json
import urllib.request
import re

CLOUD_REGIONS = {
    "MS_AZURE_SEA": {"probe": "20.198.120.1", "subnets": ["20.198.120.0/21", "13.75.0.0/16"]},
    "MS_AZURE_EASTASIA": {"probe": "20.189.112.1", "subnets": ["20.189.112.0/21", "13.76.0.0/16"]},
    "MS_AZURE_US": {"probe": "13.86.212.69", "subnets": ["13.86.0.0/15", "52.168.0.0/14"]},
    "GOOGLE_CLOUD_ASIA": {"probe": "34.87.0.1", "subnets": ["34.87.0.0/16", "35.240.0.0/13"]},
    "GOOGLE_CLOUD_US": {"probe": "34.120.255.55", "subnets": ["34.120.0.0/14", "35.184.0.0/13"]},
    "GOOGLE_DNS_SERVICES": {"probe": "8.8.8.8", "subnets": ["8.8.8.0/24", "8.8.4.0/24", "142.250.0.0/15"]},
    "ALIYUN_HK_SEA": {"probe": "47.88.255.55", "subnets": ["47.88.0.0/15", "47.91.0.0/16", "47.74.0.0/15"]},
    "ALIYUN_CHINA_MAINLAND": {"probe": "140.205.255.1", "subnets": ["140.205.0.0/16", "106.11.0.0/15", "121.40.0.0/14"]},
    "CHINA_TELECOM": {"probe": "202.96.128.86", "subnets": ["202.96.0.0/12", "116.228.0.0/15", "58.32.0.0/13"]},
    "CHINA_UNICOM": {"probe": "210.22.84.3", "subnets": ["210.22.0.0/15", "58.246.0.0/15", "112.64.0.0/14"]},
    "CHINA_MOBILE": {"probe": "211.136.112.50", "subnets": ["211.136.0.0/13", "120.192.0.0/10"]},
    "ORACLE_CLOUD_ASIA": {"probe": "140.238.0.1", "subnets": ["140.238.0.0/15", "130.61.0.0/16", "150.136.0.0/16"]},
    "ORACLE_CLOUD_US": {"probe": "129.146.0.1", "subnets": ["129.146.0.0/15", "132.145.0.0/16"]},
    "AWS_AP_SOUTHEAST": {"probe": "15.197.148.33", "subnets": ["15.197.128.0/18", "13.228.0.0/15"]},
    "AWS_AP_EAST": {"probe": "18.162.0.1", "subnets": ["18.162.0.0/16"]},
    "CLOUDFLARE_CDN": {"probe": "1.1.1.1", "subnets": ["1.1.1.0/24", "1.0.0.0/24", "104.16.0.0/13"]},
    "AKAMAI_GLOBAL": {"probe": "23.208.0.1", "subnets": ["23.192.0.0/11", "104.64.0.0/10"]}
}

M365_API_URL = "https://endpoints.office.com/endpoints/worldwide?clientrequestid=b10c5ed1-bad1-445f-b386-b919946339a7"

def enable_ip_forwarding():
    """Enables packet forwarding for router functionality."""
    subprocess.run(["sysctl", "-w", "net.ipv4.ip_forward=1"], capture_output=True)

def get_active_gateways():
    res = subprocess.run(["ip", "-j", "route", "show"], capture_output=True, text=True)
    if res.returncode != 0:
        return {}
    try:
        routes = json.loads(res.stdout)
    except json.JSONDecodeError:
        return {}

    gateways = {}
    for r in routes:
        if "gateway" in r and "dev" in r and r["dev"] != "lo":
            gateways[r["dev"]] = r["gateway"]
    return gateways

def apply_ecmp_routing(gateways):
    if not gateways:
        return
    cmd = ["ip", "route", "replace", "default"]
    for iface, gw in gateways.items():
        cmd.extend(["nexthop", "via", gw, "dev", iface, "weight", "1"])
    subprocess.run(cmd, capture_output=True, text=True)

def fetch_m365_optimize_subnets():
    try:
        req = urllib.request.urlopen(M365_API_URL, timeout=5)
        data = json.loads(req.read().decode())
        ips = []
        for item in data:
            if item.get("category") == "Optimize" and "ips" in item:
                for cidr in item["ips"]:
                    if re.match(r'^\d+\.\d+\.\d+\.\d+/\d+$', cidr):
                        ips.append(cidr)
        return ips[:20]
    except Exception:
        return []

def probe_latency(iface, target_ip):
    cmd = ["ping", "-I", iface, "-c", "2", "-W", "2", target_ip]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode == 0:
        for line in res.stdout.split('\n'):
            if "rtt min/avg/max/mdev" in line:
                return float(line.split('/')[4])
    return 9999.0

def optimize_regional_routes(gateways):
    print("\n[Multi-Cloud Optimizer] Evaluating lowest latency routes...")
    for zone, config in CLOUD_REGIONS.items():
        probe_ip = config["probe"]
        subnets = config["subnets"]
        best_iface, best_rtt = None, 9999.0

        for iface in gateways.keys():
            rtt = probe_latency(iface, probe_ip)
            if rtt < best_rtt:
                best_rtt, best_iface = rtt, iface

        if best_iface and best_rtt < 9999.0:
            gw = gateways[best_iface]
            for subnet in subnets:
                subprocess.run(["ip", "route", "replace", subnet, "via", gw, "dev", best_iface], capture_output=True)
            print(f"  └─ [{zone}] -> Routed via {best_iface} [{best_rtt:.1f}ms]")

    m365_subnets = fetch_m365_optimize_subnets()
    if m365_subnets and gateways:
        best_ms_iface = min(gateways.keys(), key=lambda iface: probe_latency(iface, "20.198.120.1"))
        best_ms_gw = gateways[best_ms_iface]
        for cidr in m365_subnets:
            subprocess.run(["ip", "route", "replace", cidr, "via", best_ms_gw, "dev", best_ms_iface], capture_output=True)

def main():
    print("=== Universal Multi-Cloud Router Engine Active ===")
    enable_ip_forwarding()
    while True:
        try:
            gateways = get_active_gateways()
            if gateways:
                apply_ecmp_routing(gateways)
                optimize_regional_routes(gateways)
        except Exception as e:
            print(f"[Engine Error] {e}")
        time.sleep(1800)

if __name__ == "__main__":
    main()
PY_ENGINE

# -------------------------------------------------------------------
# 3. TRAY WIDGET FRONTEND
# -------------------------------------------------------------------
echo "🖥️ Writing /usr/local/bin/mint_router_tray.py..."
cat << 'PY_TRAY' > "${BUILD_DIR}/usr/local/bin/mint_router_tray.py"
#!/usr/bin/env python3
import json
import subprocess
import threading
import time

import gi
gi.require_version('Gtk', '3.0')
try:
    gi.require_version('AyatanaAppIndicator3', '0.1')
    from gi.repository import AyatanaAppIndicator3 as AppIndicator
except ValueError:
    gi.require_version('AppIndicator3', '0.1')
    from gi.repository import AppIndicator3 as AppIndicator

from gi.repository import Gtk, GLib

APP_ID = "multi-cloud-router-tray"
CLOUD_PROBES = {
    "Azure SEA": "20.198.120.1",
    "AWS SEA": "15.197.148.33",
    "GCP Asia": "34.87.0.1",
    "Aliyun HK": "47.88.255.55",
    "Cloudflare": "1.1.1.1"
}

class RouterTrayApp:
    def __init__(self):
        self.indicator = AppIndicator.Indicator.new(
            APP_ID, "network-transmit-receive", AppIndicator.IndicatorCategory.SYSTEM_SERVICES
        )
        self.indicator.set_status(AppIndicator.IndicatorStatus.ACTIVE)
        self.indicator.set_label(" 🌐 Loading...", "")

        self.menu = Gtk.Menu()
        self.indicator.set_menu(self.menu)

        self.update_data()
        GLib.timeout_add_seconds(30, self.trigger_async_update)

    def trigger_async_update(self):
        threading.Thread(target=self.update_data, daemon=True).start()
        return True

    def get_gateways(self):
        try:
            res = subprocess.run(["ip", "-j", "route", "show"], capture_output=True, text=True)
            routes = json.loads(res.stdout)
            gateways = {}
            for r in routes:
                if "gateway" in r and "dev" in r and r["dev"] != "lo":
                    gateways[r["dev"]] = r["gateway"]
            return gateways
        except Exception:
            return {}

    def ping_target(self, ip):
        try:
            res = subprocess.run(["ping", "-c", "1", "-W", "1", ip], capture_output=True, text=True)
            if res.returncode == 0:
                for line in res.stdout.split('\n'):
                    if "time=" in line:
                        return float(line.split("time=")[1].split(" ")[0])
        except Exception:
            pass
        return 999.0

    def update_data(self):
        gateways = self.get_gateways()
        metrics = {}
        best_overall = 999.0

        for name, ip in CLOUD_PROBES.items():
            rtt = self.ping_target(ip)
            metrics[name] = rtt
            if rtt < best_overall:
                best_overall = rtt

        GLib.idle_add(self.rebuild_menu, gateways, metrics, best_overall)

    def rebuild_menu(self, gateways, metrics, best_overall):
        if best_overall < 999.0:
            self.indicator.set_label(f" ⚡ {best_overall:.0f}ms", "")
        else:
            self.indicator.set_label(" ⚠️ Offline", "")

        for item in self.menu.get_children():
            self.menu.remove(item)

        status_label = f"Active WANs: {len(gateways)} interface(s)"
        header_item = Gtk.MenuItem(label=f"<b>{status_label}</b>")
        header_item.get_child().set_use_markup(True)
        header_item.set_sensitive(False)
        self.menu.append(header_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        if gateways:
            for iface, gw in gateways.items():
                gw_item = Gtk.MenuItem(label=f" 🌐 {iface} ➔ {gw}")
                gw_item.set_sensitive(False)
                self.menu.append(gw_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        cloud_header = Gtk.MenuItem(label="<b>Cloud Metrics (RTT):</b>")
        cloud_header.get_child().set_use_markup(True)
        cloud_header.set_sensitive(False)
        self.menu.append(cloud_header)

        for name, rtt in metrics.items():
            rtt_str = f"{rtt:.1f} ms" if rtt < 999.0 else "Timeout"
            item = Gtk.MenuItem(label=f"   • {name:<12}: {rtt_str}")
            item.set_sensitive(False)
            self.menu.append(item)

        self.menu.append(Gtk.SeparatorMenuItem())

        sync_item = Gtk.MenuItem(label="🔄 Sync Routes Now")
        sync_item.connect("activate", self.on_sync_clicked)
        self.menu.append(sync_item)

        quit_item = Gtk.MenuItem(label="❌ Quit Tray Indicator")
        quit_item.connect("activate", Gtk.main_quit)
        self.menu.append(quit_item)

        self.menu.show_all()

    def on_sync_clicked(self, widget):
        self.indicator.set_label(" 🔄 Syncing...", "")
        threading.Thread(target=self.run_service_restart, daemon=True).start()

    def run_service_restart(self):
        # Uses passwordless sudo rule installed via sudoers.d/berry-router
        subprocess.run(["sudo", "/bin/systemctl", "restart", "router-engine"])
        time.sleep(2)
        self.update_data()

if __name__ == "__main__":
    app = RouterTrayApp()
    Gtk.main()
PY_TRAY

# -------------------------------------------------------------------
# 4. SYSTEMD SERVICE
# -------------------------------------------------------------------
echo "🔧 Writing systemd unit file..."
cat << 'SERVICE_EOF' > "${BUILD_DIR}/lib/systemd/system/router-engine.service"
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
SERVICE_EOF

# -------------------------------------------------------------------
# 5. DESKTOP AUTOSTART
# -------------------------------------------------------------------
echo "🖥️ Writing desktop autostart entry..."
cat << 'AUTOSTART_EOF' > "${BUILD_DIR}/etc/xdg/autostart/router-tray.desktop"
[Desktop Entry]
Type=Application
Name=Multi-Cloud Router Tray
Comment=Real-time routing and cloud latency indicator
Exec=/usr/bin/python3 /usr/local/bin/mint_router_tray.py
Icon=network-transmit-receive
Terminal=false
Categories=Network;
X-GNOME-Autostart-enabled=true
AUTOSTART_EOF

# -------------------------------------------------------------------
# 6. SUDOERS POLICY (Allows passwordless tray sync)
# -------------------------------------------------------------------
echo "🔐 Writing sudoers rule..."
cat << 'SUDO_EOF' > "${BUILD_DIR}/etc/sudoers.d/berry-router"
ALL ALL=(ALL) NOPASSWD: /bin/systemctl restart router-engine
SUDO_EOF

# -------------------------------------------------------------------
# 7. HOOKS & PERMISSIONS
# -------------------------------------------------------------------
echo "📜 Writing install trigger hooks..."
cat << 'POSTINST' > "${BUILD_DIR}/DEBIAN/postinst"
#!/bin/sh
set -e
chmod 0440 /etc/sudoers.d/berry-router
systemctl daemon-reload
systemctl enable router-engine.service
systemctl restart router-engine.service || true
POSTINST

cat << 'PRERM' > "${BUILD_DIR}/DEBIAN/prerm"
#!/bin/sh
set -e
systemctl stop router-engine.service || true
systemctl disable router-engine.service || true
PRERM

chmod 755 "${BUILD_DIR}/DEBIAN/postinst"
chmod 755 "${BUILD_DIR}/DEBIAN/prerm"
chmod +x "${BUILD_DIR}/usr/local/bin/router_engine.py"
chmod +x "${BUILD_DIR}/usr/local/bin/mint_router_tray.py"

# -------------------------------------------------------------------
# 8. BUILD DEB PACKAGE
# -------------------------------------------------------------------
echo "🔨 Building .deb package..."
dpkg-deb --build "${BUILD_DIR}"

echo ""
echo "==================================================================="
echo "🎉 SUCCESS! Built package: ${BUILD_DIR}.deb"
echo "==================================================================="
EOF
