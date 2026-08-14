# 🌐 Pi2 Multi-Net Router & Regional Cloud Optimizer

A dynamic multi-WAN router engine and system tray monitor built for **Raspberry Pi, Linux Mint, Ubuntu, and Debian**. 

Automatically measures low-latency paths across **AWS, Azure, Google Cloud, Alibaba Cloud, Oracle OCI, Cloudflare, and China Mainland Networks (Telecom/Unicom/Mobile)** and binds subnets to your fastest WAN interface.

---

## 🚀 Quick Installation (.deb)

Download or build the single `.deb` installer:

```bash
# Clone the repository
git clone [https://github.com/azrin619/pi2-multinet-router.git](https://github.com/azrin619/pi2-multinet-router.git)
cd pi2-multinet-router

# Build the DEB package
bash make_deb.sh

# Install the package
sudo apt install ./berry-router-engine_1.2.0_all.deb

---------------------------------------------------------------------
Changes to Ver 1.2.0 
---------------------------------------------------------------------

## 📊 System Resource Requirements

| Resource | Absolute Minimum | Recommended (Ideal) | Technical Reason |
| --- | --- | --- | --- |
| **CPU** | **64-bit x86 Dual-Core** *(e.g., Intel Core 2 Duo, Atom, Celeron)* | **64-bit Quad-Core** *(e.g., 4th Gen Intel i3/i5 or newer)* | Handles the Python latency probes, background `arping`, and network packet forwarding without bottlenecking. |
| **RAM (Memory)** | **1 GB** | **2 GB – 4 GB** | Headless base system + Python services take **~250–350 MB**. Operating standard Cockpit web management consumes **~150 MB**. |
| **Storage (Disk)** | **4 GB** (USB drive or internal SSD/HDD) | **8 GB – 16 GB** | The SquashFS Live image takes **~1.2 GB**. The remaining space is allocated for the persistent overlay (logs, SSH host keys, and `.deb` driver cache). |
| **Network Interfaces** | **1x Built-in Ethernet** + **1x Built-in Wi-Fi** | **1x Onboard LAN** + **1x USB/PCIe Gigabit LAN** + **1x Wi-Fi** | Needed for multi-WAN routing (`router_engine.py`) to load-balance or failover between multiple connections. |

---

## 🧮 Detailed Resource Calculation & Overhead

### 1. RAM Breakdown (Where does the memory go?)

* **Base Linux Kernel + Init system:** ~120 MB
* **4x Berry Python Services:** ~80 MB total (~20 MB per script: `.88` assigner, Wi-Fi autobind, driver loader, routing engine)
* **OpenSSH + Network Stack:** ~30 MB
* **Cockpit Web Management Interface:** ~120 MB *(only active when you log into `http://<IP>:9090`)*
* **Total Active Overhead:** **~350 MB – 450 MB**
> 💡 *Even an old 2012 laptop with 2 GB RAM will operate at less than 25% total memory usage!*



### 2. Disk Space Calculation (SquashFS + Persistence)

* **`BERRY_BOOT` Partition (FAT32):** **2.5 GB**
* Live Linux Kernel (`vmlinuz`) + Initrd: ~60 MB
* UEFI Bootloader (`BOOTX64.EFI` / GRUB): ~15 MB
* Compressed `filesystem.squashfs`: ~1.2 GB


* **`persistence` Partition (EXT4):** **1.0 GB – 5.5 GB**
* SSH Host Keys + Configs: ~5 MB
* Systemd logs (`journald` capped): ~200 MB
* Driver `.deb` package cache: ~300 MB


* **Total Image/Disk Allocation:** **3.5 GB (Fits easily on a 4 GB or 8 GB USB stick)**

### 3. Network Throughput Capabilities

* **100 Mbps Fast Ethernet (Older Laptops):** Handled effortlessly at < 1% CPU utilization.
* **1 Gbps (Gigabit Ethernet):** Requires a 64-bit processor to avoid packet processing bottlenecks during high throughput (e.g., heavy torrenting or high-speed local network transfers).

---

## 💡 Practical Laptop Recycling Recommendations

1. **Power Settings & Lid Behavior:**
Old laptops automatically go to sleep when closed. The Linux live system is configured to ignore the lid switch, but ensure you disable "Suspend on Lid Close" if you install it permanently to internal storage.
2. **Battery as a Built-in UPS:**
An old laptop makes a *fantastic* router appliance because its worn-out battery acts as an integrated **Uninterruptible Power Supply (UPS)** during power outages!


=============================================NOOB INSTRUCTIONS=================
🛠️ How to Add the Updater to System Services
You can add a systemd timer to check for patches every 6 hours automatically by adding these two files to your build system:

1. /etc/systemd/system/berry-patch-updater.service
Ini, TOML
[Unit]
Description=Berry Router Git Patch & Hotfix Updater
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/berry_patch_updater.sh
2. /etc/systemd/system/berry-patch-updater.timer
Ini, TOML
[Unit]
Description=Run Berry Router Patch Check Every 6 Hours

[Timer]
OnBootSec=10min
OnUnitActiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target
=====================END NOOB INSTRUCTIONS FOR VERSION 1.2===============


