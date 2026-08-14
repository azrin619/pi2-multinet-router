#!/usr/bin/env python3
import json
import time
import subprocess
import ipaddress

FALLBACK_ADMIN_IP = "10.10.88.88/24"

def get_network_interfaces():
    res = subprocess.run(["ip", "-j", "link", "show"], capture_output=True, text=True)
    eth_links = []
    if res.returncode == 0 and res.stdout.strip():
        try:
            links = json.loads(res.stdout)
            for link in links:
                ifname = link.get("ifname", "")
                if (ifname.startswith("eth") or ifname.startswith("en")) and link.get("operstate") != "DOWN":
                    eth_links.append(ifname)
        except json.JSONDecodeError:
            pass
    return eth_links if eth_links else ["eth0"]

def is_ip_in_use(ip_str, iface):
    res = subprocess.run(["arping", "-c", "2", "-w", "2", "-I", iface, ip_str], capture_output=True)
    return res.returncode == 0

def assign_smart_ip():
    ifaces = get_network_interfaces()
    primary_iface = ifaces[0]
    secondary_iface = ifaces[1] if len(ifaces) > 1 else None

    res = subprocess.run(["ip", "-j", "addr", "show", "dev", primary_iface], capture_output=True, text=True)
    
    has_valid_private_ip = False
    
    if res.returncode == 0 and res.stdout.strip():
        try:
            data = json.loads(res.stdout)
            if data and "addr_info" in data[0]:
                for addr in data[0]["addr_info"]:
                    if addr.get("family") == "inet" and addr.get("scope") == "global":
                        current_ip = addr.get("local", "")
                        prefixlen = addr.get("prefixlen", 24)

                        ip_obj = ipaddress.IPv4Address(current_ip)

                        # 🛑 CHECK 1: PUBLIC IP SAFETY GATE
                        if not ip_obj.is_private or ip_obj.is_link_local:
                            print(f"⚠️ [IP Security] Public or APIPA IP ({current_ip}) detected on {primary_iface}!")
                            print("🔒 Skipping .88 static IP assignment on Public interface to prevent WAN exposure.")
                            continue

                        has_valid_private_ip = True

                        # ✅ CHECK 2: PRIVATE IP - Assign .88 on Subnet
                        interface_net = ipaddress.IPv4Interface(f"{current_ip}/{prefixlen}")
                        network = interface_net.network
                        
                        target_ip = ipaddress.IPv4Address(int(network.network_address) + 88)
                        target_cidr = f"{target_ip}/{prefixlen}"

                        already_assigned = any(
                            a.get("local") == str(target_ip) for a in data[0]["addr_info"]
                        )
                        if already_assigned:
                            return

                        if is_ip_in_use(str(target_ip), primary_iface):
                            print(f"⚠️ [IP Bootstrap] {target_ip} is occupied by another host. Skipping.")
                            return

                        print(f"✅ [IP Bootstrap] Private IP detected ({current_ip}). Binding .88 Static IP: {target_cidr} to {primary_iface}")
                        subprocess.run(["ip", "addr", "add", target_cidr, "dev", primary_iface], capture_output=True)
                        return

        except Exception as e:
            print(f"[IP Bootstrap Error] {e}")

    # 🛑 CHECK 3: NO VALID IP OR APIPA (169.254.x.x) - Fallback to 10.10.88.88
    if not has_valid_private_ip:
        target_dev = secondary_iface if secondary_iface else primary_iface
        
        # Verify if 10.10.88.88 is already assigned
        chk = subprocess.run(["ip", "-j", "addr", "show", "dev", target_dev], capture_output=True, text=True)
        if FALLBACK_ADMIN_IP.split('/')[0] not in chk.stdout:
            print(f"🚨 [IP Bootstrap] Public/Invalid/No IP on WAN. Emergency Fallback: Binding {FALLBACK_ADMIN_IP} to {target_dev} for cross-over cable admin access.")
            subprocess.run(["ip", "addr", "add", FALLBACK_ADMIN_IP, "dev", target_dev], capture_output=True)

if __name__ == "__main__":
    while True:
        assign_smart_ip()
        time.sleep(15)
