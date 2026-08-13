#!/usr/bin/env python3
import os
import glob
import subprocess
import time

CACHE_DIR = "/var/cache/berry-router/drivers"

def scan_pci_hardware():
    res = subprocess.run(["lspci", "-nnk"], capture_output=True, text=True)
    if res.returncode == 0:
        output = res.stdout.lower()
        if "network controller" in output or "ethernet controller" in output:
            print("[Driver Loader] Active network hardware controllers detected.")

def install_and_cache_deb(deb_path):
    filename = os.path.basename(deb_path)
    cache_target = os.path.join(CACHE_DIR, filename)

    print(f"[Driver Loader] Verifying package integrity: {filename}")
    
    # Check structure/integrity before running any package scripts
    check = subprocess.run(["dpkg-deb", "-I", deb_path], capture_output=True)
    if check.returncode != 0:
        print(f"❌ [Driver Loader] Invalid or corrupt package: {filename}")
        return

    # Install package safely
    install_res = subprocess.run(["dpkg", "-i", deb_path], capture_output=True, text=True)
    if install_res.returncode == 0:
        print(f"✅ [Driver Loader] Successfully installed driver: {filename}")
        subprocess.run(["cp", "-u", deb_path, cache_target], capture_output=True)
        
        # Trigger kernel module probe for hotplug adapters
        subprocess.run(["udevadm", "trigger", "--subsystem-match=net"], capture_output=True)
    else:
        print(f"❌ [Driver Loader] Installation failed for {filename}: {install_res.stderr}")

def scan_usb_drives():
    usb_mounts = glob.glob("/media/*/*") + glob.glob("/mnt/*") + glob.glob("/media/*")
    for mount in usb_mounts:
        if os.path.isdir(mount):
            deb_files = glob.glob(f"{mount}/*.deb") + glob.glob(f"{mount}/drivers/*.deb")
            for deb in deb_files:
                filename = os.path.basename(deb)
                cached_file = os.path.join(CACHE_DIR, filename)
                if not os.path.exists(cached_file):
                    install_and_cache_deb(deb)

def main():
    os.makedirs(CACHE_DIR, exist_ok=True)
    print("=== Berry Router Driver Auto-Loader Active ===")
    scan_pci_hardware()

    while True:
        try:
            scan_usb_drives()
        except Exception as e:
            print(f"[Driver Loader Error] {e}")
        time.sleep(10)

if __name__ == "__main__":
    main()
