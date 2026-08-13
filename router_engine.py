#!/usr/bin/env python3
import time
import subprocess
import json
import urllib.request
import re

# -------------------------------------------------------------------
# EXTENDED CLOUD, TELCO & REGIONAL PROBE TARGETS
# -------------------------------------------------------------------
REGION_TARGETS = {
    # ------------------ MICROSOFT & AZURE ------------------
    "MS_AZURE_SEA": {
        "probe": "20.198.120.1",        # Azure Southeast Asia (Singapore)
        "subnets": ["20.198.120.0/21", "13.75.0.0/16"]
    },
    "MS_AZURE_EASTASIA": {
        "probe": "20.189.112.1",        # Azure East Asia (Hong Kong)
        "subnets": ["20.189.112.0/21", "13.76.0.0/16"]
    },
    "MS_AZURE_US": {
        "probe": "13.86.212.69",        # Azure US East
        "subnets": ["13.86.0.0/15", "52.168.0.0/14"]
    },

    # ------------------ GOOGLE / GCP / WORKSPACE ------------------
    "GCP_ASIA_SOUTHEAST": {
        "probe": "34.87.0.1",           # GCP Singapore (asia-southeast1)
        "subnets": ["34.87.0.0/16", "35.240.0.0/13"]
    },
    "GCP_ASIA_EAST": {
        "probe": "35.220.0.1",          # GCP Taiwan/HK (asia-east1)
        "subnets": ["35.220.0.0/14", "34.92.0.0/14"]
    },
    "GOOGLE_SERVICES_GLOBAL": {
        "probe": "8.8.8.8",             # Google DNS/Global Anycast
        "subnets": ["8.8.8.0/24", "8.8.4.0/24", "142.250.0.0/15", "172.217.0.0/16"]
    },

    # ------------------ ALIBABA CLOUD (ALIYUN) ------------------
    "ALIYUN_SEA": {
        "probe": "47.74.0.1",           # Aliyun Singapore / SEA
        "subnets": ["47.74.0.0/15", "47.88.0.0/15"]
    },
    "ALIYUN_CHINA_MAINLAND": {
        "probe": "47.96.0.1",           # Aliyun East China (Hangzhou/Shanghai)
        "subnets": ["47.96.0.0/12", "121.40.0.0/14", "120.24.0.0/13"]
    },

    # ------------------ ORACLE CLOUD (OCI) ------------------
    "OCI_SINGAPORE": {
        "probe": "134.70.0.1",          # Oracle Cloud Singapore
        "subnets": ["134.70.0.0/16", "140.83.0.0/16"]
    },
    "OCI_US_ASHBURN": {
        "probe": "129.213.0.1",         # Oracle Cloud Ashburn (US East)
        "subnets": ["129.213.0.0/16", "130.35.0.0/16"]
    },

    # ------------------ AWS ------------------
    "AWS_AP_SOUTHEAST": {
        "probe": "15.197.148.33",       # AWS Singapore (ap-southeast-1)
        "subnets": ["15.197.128.0/18", "13.228.0.0/15"]
    },
    "AWS_AP_EAST": {
        "probe": "18.162.0.1",          # AWS Hong Kong (ap-east-1)
        "subnets": ["18.162.0.0/16"]
    },

    # ------------------ TENCENT CLOUD ------------------
    "TENCENT_CHINA_HK": {
        "probe": "129.226.0.1",         # Tencent Cloud HK / Overseas
        "subnets": ["129.226.0.0/16", "43.128.0.0/14"]
    },

    # ------------------ CHINA TELECOM / UNICOM / MOBILE ------------------
    "CHINA_TELECOM_163": {
        "probe": "202.96.128.166",      # China Telecom 163 (AS4134)
        "subnets": ["202.96.0.0/12", "61.128.0.0/10"]
    },
    "CHINA_UNICOM": {
        "probe": "202.108.22.5",        # China Unicom (AS4837)
        "subnets": ["202.108.0.0/16", "220.181.0.0/16"]
    },
    "CHINA_MOBILE": {
        "probe": "211.136.192.6",       # China Mobile (AS9808)
        "subnets": ["211.136.0.0/13", "120.192.0.0/10"]
    },

    # ------------------ CDN PROVIDERS ------------------
    "CLOUDFLARE_ANYCAST": {
        "probe": "1.1.1.1",
        "subnets": ["1.1.1.1/32", "1.0.0.1/32", "104.16.0.0/12"]
    },
    "AKAMAI_GLOBAL": {
        "probe": "23.211.0.1",
        "subnets": ["23.211.0.0/16", "104.64.0.0/10"]
    },
    "FASTLY_CDN": {
        "probe": "151.101.1.140",
        "subnets": ["151.101.0.0/16", "199.232.0.0/16"]
    }
}

M365_API_URL = "https://endpoints.office.com/endpoints/worldwide?clientrequestid=b10c5ed1-bad1-445f-b386-b919946339a7"

def get_active_gateways():
    """Scans active network interfaces and extracts default gateways."""
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
    """Applies global multipath ECMP route across all interfaces."""
    if not gateways:
        print("[ECMP] No active gateways found.")
        return

    cmd = ["ip", "route", "replace", "default"]
    for iface, gw in gateways.items():
        cmd.extend(["nexthop", "via", gw, "dev", iface, "weight", "1"])

    subprocess.run(cmd, capture_output=True, text=True)
    print(f"[ECMP] Established multipath default route across {list(gateways.keys())}")

def fetch_m365_optimize_subnets():
    """Fetches Microsoft 365 'Optimize' priority IP ranges via official API."""
    try:
        req = urllib.request.urlopen(M365_API_URL, timeout=5)
        data = json.loads(req.read().decode())
        ips = []
        for item in data:
            if item.get("category") == "Optimize" and "ips" in item:
                for cidr in item["ips"]:
                    if re.match(r'^\d+\.\d+\.\d+\.\d+/\d+$', cidr):
                        ips.append(cidr)
        return ips[:20]  # Limit to top 20 subnets to conserve routing memory on Pi 2
    except Exception as e:
        print(f"[M365 API Warning] Couldn't fetch endpoints: {e}")
        return []

def probe_latency(iface, target_ip):
    """Measures RTT to a specific target IP over a chosen network interface."""
    cmd = ["ping", "-I", iface, "-c", "2", "-W", "2", target_ip]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode == 0:
        for line in res.stdout.split('\n'):
            if "rtt min/avg/max/mdev" in line:
                return float(line.split('/')[4])
    return 9999.0

def optimize_regional_routes(gateways):
    """Probes latency to each cloud/telco zone and binds subnets to the fastest WAN interface."""
    print("[Regional Optimizer] Measuring latency per zone across interfaces...")
    
    # 1. Optimize all defined regional cloud, CDN, and China telco zones
    for zone, config in REGION_TARGETS.items():
        probe_ip = config["probe"]
        subnets = config["subnets"]
        
        best_iface = None
        best_rtt = 9999.0

        for iface in gateways.keys():
            rtt = probe_latency(iface, probe_ip)
            if rtt < best_rtt:
                best_rtt = rtt
                best_iface = iface

        if best_iface and best_rtt < 9999.0:
            gw = gateways[best_iface]
            for subnet in subnets:
                subprocess.run(["ip", "route", "replace", subnet, "via", gw, "dev", best_iface], capture_output=True)
            print(f"[Zone Route] {zone} -> Routed via {best_iface} (GW: {gw}) [{best_rtt:.1f}ms]")

    # 2. Dynamic Microsoft 365 Optimization
    m365_subnets = fetch_m365_optimize_subnets()
    if m365_subnets and gateways:
        best_ms_iface = min(gateways.keys(), key=lambda iface: probe_latency(iface, "20.198.120.1"))
        best_ms_gw = gateways[best_ms_iface]
        
        for cidr in m365_subnets:
            subprocess.run(["ip", "route", "replace", cidr, "via", best_ms_gw, "dev", best_ms_iface], capture_output=True)
        print(f"[M365 Route] Bound {len(m365_subnets)} Microsoft 365 priority ranges to {best_ms_iface}")

def main():
    print("=== Berry Router Dynamic Multi-Cloud Engine Started ===")
    while True:
        try:
            gateways = get_active_gateways()
            if gateways:
                apply_ecmp_routing(gateways)
                optimize_regional_routes(gateways)
            else:
                print("[Warning] No active gateways detected.")
        except Exception as e:
            print(f"[Engine Error] {e}")

        # Re-evaluate best paths every 30 minutes
        time.sleep(1800)

if __name__ == "__main__":
    main()
