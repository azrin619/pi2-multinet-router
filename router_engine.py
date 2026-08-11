#!/usr/bin/env python3
import time
import subprocess
import json

TARGETS = {
    "AWS": "15.197.148.33",
    "AZURE": "13.86.212.69",
    "GCP": "34.120.255.55",
    "ALIYUN": "47.88.255.55",
    "CLOUDFLARE": "1.1.1.1"
}

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
        print("[ECMP] No active gateways found.")
        return

    cmd = ["ip", "route", "replace", "default"]
    for iface, gw in gateways.items():
        cmd.extend(["nexthop", "via", gw, "dev", iface, "weight", "1"])

    print(f"[ECMP] Executing: {' '.join(cmd)}")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode == 0:
        print("[ECMP] Successfully established multipath route.")
    else:
        print(f"[ECMP] Route error: {res.stderr.strip()}")

def probe_latency(iface, target_ip):
    cmd = ["ping", "-I", iface, "-c", "2", "-W", "2", target_ip]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode == 0:
        for line in res.stdout.split('\n'):
            if "rtt min/avg/max/mdev" in line:
                return float(line.split('/')[4])
    return 9999.0

def optimize_specific_routes(gateways):
    for cloud, ip in TARGETS.items():
        best_iface = None
        best_rtt = 9999.0
        for iface in gateways.keys():
            rtt = probe_latency(iface, ip)
            if rtt < best_rtt:
                best_rtt = rtt
                best_iface = iface
        if best_iface and best_rtt < 9999.0:
            subprocess.run(["ip", "route", "replace", ip, "dev", best_iface])
            print(f"[Optimize] {cloud} ({ip}) routed via {best_iface} [{best_rtt}ms]")

def main():
    while True:
        try:
            gateways = get_active_gateways()
            if gateways:
                apply_ecmp_routing(gateways)
                optimize_specific_routes(gateways)
        except Exception as e:
            print(f"[Error] {e}")
        time.sleep(60)

if __name__ == "__main__":
    main()
