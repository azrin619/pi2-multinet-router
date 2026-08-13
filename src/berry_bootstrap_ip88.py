#!/usr/bin/env python3
import json
import time
import subprocess
import ipaddress

def get_eth_interface():
    res = subprocess.run(["ip", "-j", "link", "show"], capture_output=True, text=True)
    if res.returncode == 0 and res.stdout.strip():
        try:
            links = json.loads(res.stdout)
            for link in links:
                ifname = link.get("ifname", "")
                if (ifname.startswith("eth") or ifname.startswith("en")) and link.get("operstate") != "DOWN":
                    return ifname
        except json.JSONDecodeError:
            pass
    return "eth0"

def is_ip_in_use(ip_str, iface):
    """Probes the local LAN via ARPING to avoid IP address collisions."""
    res = subprocess.run(["arping", "-c", "2", "-w", "2", "-I", iface, ip_str], capture_output=True)
    return res.returncode == 0

def assign_dot88_ip():
    iface = get_eth_interface()

    res = subprocess.run(["ip", "-j", "addr", "show", "dev", iface], capture_output=True, text=True)
    if res.returncode != 0 or not res.stdout.strip():
        return

    try:
        data = json.loads(res.stdout)
        if not data or "addr_info" not in data[0]:
            return

        for addr in data[0]["addr_info"]:
            if addr.get("family") == "inet" and addr.get("scope") == "global":
                current_ip = addr.get("local", "")
                prefixlen = addr.get("prefixlen", 24)

                # Compute proper network base address using ipaddress module
                interface_net = ipaddress.IPv4Interface(f"{current_ip}/{prefixlen}")
                network = interface_net.network
                
                # Calculate host .88 within the given CIDR subnet
                base_int = int(network.network_address)
                target_int = base_int + 88
                target_ip = ipaddress.IPv4Address(target_int)
                target_cidr = f"{target_ip}/{prefixlen}"

                # Check if .88 is already assigned locally to this interface
                already_assigned = any(
                    a.get("local") == str(target_ip) for a in data[0]["addr_info"]
                )
                if already_assigned:
                    return

                # Check for external IP collisions via ARP
                if is_ip_in_use(str(target_ip), iface):
                    print(f"⚠️ [IP Bootstrap] Warning: {target_ip} is already occupied on {iface}! Skipping binding.")
                    return

                print(f"✅ [IP Bootstrap] Subnet detected ({network}). Binding static host IP: {target_cidr} to {iface}")
                subprocess.run(["ip", "addr", "add", target_cidr, "dev", iface], capture_output=True)
                return

    except Exception as e:
        print(f"[IP Bootstrap Error] {e}")

if __name__ == "__main__":
    while True:
        assign_dot88_ip()
        time.sleep(15)
