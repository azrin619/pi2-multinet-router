#!/usr/bin/env bash
# ===================================================================
# Berry Router Engine - Universal Debian/Mint Installer
# ===================================================================

set -e

# 1. Ensure Root Privileges
if [ "$EUID" -ne 0 ]; then
  echo "[Error] Please run this installer with sudo: sudo bash install_router_engine.sh"
  exit 1
fi

echo "[1/4] Installing system dependencies..."
apt-get update -qq
apt-get install -y python3 iproute2 iputils-ping curl systemd

# 2. Deploy Python Router Engine
ENGINE_PATH="/usr/local/bin/router_engine.py"
echo "[2/4] Deploying router engine to ${ENGINE_PATH}..."

cat << 'EOF' > ${ENGINE_PATH}
#!/usr/bin/env python3
import time
import subprocess
import json
import urllib.request
import re

CLOUD_REGIONS = {
    # --- MICROSOFT & AZURE ---
    "MS_AZURE_SEA": {"probe": "20.198.120.1", "subnets": ["20.198.120.0/21", "13.75.0.0/16"]},
    "MS_AZURE_EASTASIA": {"probe": "20.189.112.1", "subnets": ["20.189.112.0/21", "13.76.0.0/16"]},
    "MS_AZURE_US": {"probe": "13.86.212.69", "subnets": ["13.86.0.0/15", "52.168.0.0/14"]},

    # --- GOOGLE CLOUD & SERVICES ---
    "GOOGLE_CLOUD_ASIA": {"probe": "34.87.0.1", "subnets": ["34.87.0.0/16", "35.240.0.0/13"]},
    "GOOGLE_CLOUD_US": {"probe": "34.120.255.55", "subnets": ["34.120.0.0/14", "35.184.0.0/13"]},
    "GOOGLE_DNS_SERVICES": {"probe": "8.8.8.8", "subnets": ["8.8.8.0/24", "8.8.4.0/24", "142.250.0.0/15"]},

    # --- ALIBABA CLOUD (ALIYUN) ---
    "ALIYUN_HK_SEA": {"probe": "47.88.255.55", "subnets": ["47.88.0.0/15", "47.91.0.0/16", "47.74.0.0/15"]},
    "ALIYUN_CHINA_MAINLAND": {"probe": "140.205.255.1", "subnets": ["140.205.0.0/16", "106.11.0.0/15", "121.40.0.0/14"]},

    # --- CHINA MAINLAND TELCOS ---
    "CHINA_TELECOM": {"probe": "202.96.128.86", "subnets": ["202.96.0.0/12", "116.228.0.0/15", "58.32.0.0/13"]},
    "CHINA_UNICOM": {"probe": "210.22.84.3", "subnets": ["210.22.0.0/15", "58.246.0.0/15", "112.64.0.0/14"]},
    "CHINA_MOBILE": {"probe": "211.136.112.50", "subnets": ["211.136.0.0/13", "120.192.0.0/10"]},

    # --- ORACLE CLOUD INFRASTRUCTURE (OCI) ---
    "ORACLE_CLOUD_ASIA": {"probe": "140.238.0.1", "subnets": ["140.238.0.0/15", "130.61.0.0/16", "150.136.0.0/16"]},
    "ORACLE_CLOUD_US": {"probe": "129.146.0.1", "subnets": ["129.146.0.0/15", "132.145.0.0/16"]},

    # --- AMAZON WEB SERVICES (AWS) ---
    "AWS_AP_SOUTHEAST": {"probe": "15.197.148.33", "subnets": ["15.197.128.0/18", "13.228.0.0/15"]},
    "AWS_AP_EAST": {"probe": "18.162.0.1", "subnets": ["18.162.0.0/16"]},

    # --- CDNs ---
    "CLOUDFLARE_CDN": {"probe": "1.1.1.1", "subnets": ["1.1.1.0/24", "1.0.0.0/24", "104.16.0.0/13"]},
    "AKAMAI_GLOBAL": {"probe": "23.208.0.1", "subnets": ["23.192.0.0/11", "104.64.0.0/10"]}
}

M365_API_URL = "https://endpoints.office.com/endpoints/worldwide?clientrequestid=b10c5ed1-bad1-445f-b386-b919946339a7"

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
        if "gateway" in r and "dev" in r:
            iface = r["dev"]
            gw = r["gateway"]
            if iface != "lo":
                gateways[iface] = gw
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
EOF

chmod +x ${ENGINE_PATH}

# 3. Create Systemd Service
echo "[3/4] Creating systemd service..."
cat << 'EOF' > /etc/systemd/system/router-engine.service
[Unit]
Description=Universal Multi-Cloud Dynamic Route Optimizer
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/router_engine.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 4. Enable and Start Service
echo "[4/4] Enabling and starting router-engine service..."
systemctl daemon-reload
systemctl enable router-engine
systemctl restart router-engine

echo "==================================================================="
echo "SUCCESS! Berry Router Engine is running on your system."
echo "Check status:  sudo systemctl status router-engine"
echo "View live log: sudo journalctl -u router-engine -f"
echo "==================================================================="
