#!/usr/bin/env python3
import time
import subprocess
import json
from concurrent.futures import ThreadPoolExecutor

CLOUD_TARGETS = ["1.1.1.1", "8.8.8.8", "9.9.9.9"]
LATENCY_HYSTERESIS_MS = 15.0  # Minimum latency gain required to switch default routes
current_primary_iface = None

def get_active_gateways():
    res = subprocess.run(["ip", "-j", "route", "show"], capture_output=True, text=True)
    gateways = {}
    if res.returncode == 0 and res.stdout.strip():
        try:
            routes = json.loads(res.stdout)
            for route in routes:
                if route.get("dst") == "default" and "dev" in route and "gateway" in route:
                    gateways[route["dev"]] = route["gateway"]
        except json.JSONDecodeError:
            pass
    return gateways

def ping_target(args):
    iface, target = args
    cmd = ["ping", "-c", "2", "-W", "2", "-I", iface, target]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode == 0:
        for line in res.stdout.split("\n"):
            if "rtt min/avg/max/mdev" in line or "round-trip" in line:
                try:
                    avg_rtt = float(line.split("/")[4])
                    return iface, avg_rtt
                except (IndexError, ValueError):
                    pass
    return iface, 9999.0

def measure_interface_latency(gateways):
    tasks = []
    for iface in gateways.keys():
        for target in CLOUD_TARGETS:
            tasks.append((iface, target))

    results = {iface: [] for iface in gateways.keys()}
    
    # Parallel execution prevents thread blocking on dead links
    with ThreadPoolExecutor(max_workers=6) as executor:
        for iface, latency in executor.map(ping_target, tasks):
            if latency < 9999.0:
                results[iface].append(latency)

    avg_latencies = {}
    for iface, latencies in results.items():
        if latencies:
            avg_latencies[iface] = sum(latencies) / len(latencies)
        else:
            avg_latencies[iface] = 9999.0  # Down/Unreachable
            
    return avg_latencies

def update_default_route(best_iface, best_gw, current_iface):
    print(f"🔄 Switching primary default route to {best_iface} via {best_gw}")
    subprocess.run(["ip", "route", "replace", "default", "via", best_gw, "dev", best_iface], capture_output=True)

def main():
    global current_primary_iface
    print("=== Berry Router Multi-Cloud Routing Engine Started ===")

    while True:
        try:
            gateways = get_active_gateways()
            if not gateways:
                time.sleep(5)
                continue

            latencies = measure_interface_latency(gateways)
            sorted_ifaces = sorted(latencies.items(), key=lambda x: x[1])
            best_iface, best_latency = sorted_ifaces[0]

            if best_latency == 9999.0:
                print("⚠️ All WAN interfaces disconnected or blocking ICMP.")
            else:
                if current_primary_iface is None:
                    current_primary_iface = best_iface
                    update_default_route(best_iface, gateways[best_iface], current_primary_iface)
                elif best_iface != current_primary_iface:
                    current_latency = latencies.get(current_primary_iface, 9999.0)
                    # Hysteresis check prevents route flapping
                    if (current_latency - best_latency) > LATENCY_HYSTERESIS_MS:
                        update_default_route(best_iface, gateways[best_iface], current_primary_iface)
                        current_primary_iface = best_iface

        except Exception as e:
            print(f"[Routing Engine Error] {e}")

        time.sleep(10)

if __name__ == "__main__":
    main()
