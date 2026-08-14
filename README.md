# 🌐 Pi2 Multi-Net Router & Regional Cloud Optimizer
### *(Berry Router Engine Appliance — v1.2.0)*

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)]()
[![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi%20%7C%20Linux%20Mint%20%7C%20Ubuntu%20%7C%20Debian-blue.svg)]()
[![Architecture](https://img.shields.io/badge/arch-x86__64%20%7C%20aarch64%20%7C%20armhf-orange.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)]()

> A dynamic multi-WAN routing engine, regional cloud optimizer, and system tray monitor built for Raspberry Pi, Linux PCs, and recycled laptops. Measures ultra-low latency paths across **AWS, Azure, Google Cloud, Alibaba Cloud, Oracle OCI, Cloudflare, and China Mainland Networks** to route traffic through your fastest WAN interface automatically.

---

## 🖥️ Web Interface Console Preview (`http://<ROUTER-IP>:9090`)

```text
┌──────────────────────────────────────────────────────────────────────────────────────────────────┐
│ 🍓 BERRY ROUTER OS | Mini Fork Appliance                      👤 root  │  ⚙️ Settings  │ 🔔 0  │
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                  │
│  📊 SYSTEM OVERVIEW                                                                             │
│  ─────────────────────────────────────────────────────────────────────────────────────────────── │
│  Host Name:       berry-router-live             Uptime:      0d 02h 14m                          │
│  Kernel:          Linux 6.8.0-generic           CPUs:        4x Intel(R) Core(TM) i5            │
│  Memory Usage:    412 MB / 2048 MB (20%)        Storage:     850 MB / 1000 MB (Overlay EXT4)    │
│                                                                                                  │
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                  │
│  🌐 NETWORK INTERFACES & SMART IP ASSIGNER (berry_bootstrap_ip88.py)                             │
│  ─────────────────────────────────────────────────────────────────────────────────────────────── │
│  Interface  Type        DHCP IP            Static IP / Fallback   IP Mode   Status               │
│  ─────────  ──────────  ─────────────────  ────────────────────   ───────   ───────────────────  │
│  eth0       Ethernet    192.168.1.105/24   192.168.1.88/24 🟢    PRIVATE   CONNECTED (.88 Active)
│  eth1       Ethernet    203.0.113.15/24    Skipped (Public IP)🔒  PUBLIC    WAN DIRECT (Safe)    │
│  wlan0      Wireless    10.0.0.45/24       10.10.88.88/24 (Fallback) PRIVATE CONNECTED            │
│                                                                                                  │
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                  │
│  ⚡ REGIONAL CLOUD & MULTI-WAN ROUTING ENGINE (router_engine.py)                                 │
│  ─────────────────────────────────────────────────────────────────────────────────────────────── │
│  Current Default Route:   eth0 (via 192.168.1.1)                                                 │
│  Engine Hysteresis:       15.0 ms threshold                                                      │
│                                                                                                  │
│  Multi-Cloud Latency Probes (Parallel ICMP):                                                     │
│  ├── 🌐 AWS / Azure / GCP ─────►  eth0: 12.4 ms 🟢  │  wlan0: 28.1 ms                           │
│  ├── 🌐 Alibaba / Oracle OCI ──►  eth0: 18.2 ms 🟢  │  wlan0: 34.5 ms                           │
│  ├── 🌐 Cloudflare Edge ───────►  eth0: 09.1 ms 🟢  │  wlan0: 22.0 ms                           │
│  └── 🇨🇳 China Telecom/Unicom ─►  eth0: 45.3 ms 🟢   │  wlan0: 68.2 ms                            │
│                                                                                                  │
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                  │
│  🔌 HOTPLUG USB DRIVER AUTO-LOADER & AUTOMATED GIT PATCHER                                       │
│  ─────────────────────────────────────────────────────────────────────────────────────────────── │
│  Driver Cache: /var/cache/berry-router/drivers/                                                  │
│  Git Patch Status: Up to date (Checked via berry-patch-updater.timer) 🟢                         │
│                                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘



🏗️ System Architecture Flowchart

┌────────────────────────┐
                                 │   Physical Interfaces  │
                                 └───────────┬────────────┘
                                             │
                      ┌──────────────────────┴──────────────────────┐
                      ▼                                             ▼
          ┌───────────────────────┐                     ┌───────────────────────┐
          │     eth0 / eth1       │                     │    wlan0 / wlan1      │
          └───────────┬───────────┘                     └───────────┬───────────┘
                      │                                             │
                      ▼                                             ▼
   ┌─────────────────────────────────────┐       ┌─────────────────────────────────────┐
   │      berry_bootstrap_ip88.py        │       │       berry_wifi_autobind.sh        │
   ├─────────────────────────────────────┤       ├─────────────────────────────────────┤
   │ 1. Check IP type (Public vs Private)│       │ 1. Dynamic wireless interface discovery│
   │ 2. Public IP ──► Skip .88 binding   │       │ 2. Secure 0600 wpa_supplicant config│
   │ 3. Private IP ──► ARPING & bind .88 │       │ 3. Auto-reconnect & DHCP request    │
   │ 4. No IP ──► Fallback 10.10.88.88/24│       └──────────────────┬──────────────────┘
   └──────────────────┬──────────────────┘                          │
                      │                                             │
                      └──────────────────────┬──────────────────────┘
                                             │
                                             ▼
                          ┌─────────────────────────────────────┐
                          │          router_engine.py           │
                          ├─────────────────────────────────────┤
                          │ • Parallel ThreadPool ICMP Probes   │
                          │ • AWS, GCP, Azure, OCI, China Net   │
                          │ • 15ms Hysteresis Route Switching   │
                          └──────────────────┬──────────────────┘
                                             │
                                             ▼
                          ┌─────────────────────────────────────┐
                          │      berry_patch_updater.sh         │
                          ├─────────────────────────────────────┤
                          │ • Checks GitHub for latest hotfixes │
                          │ • Rebuilds DEB & restarts daemons   │
                          └─────────────────────────────────────┘


🚀 Quick Installation (.deb)
To install the routing engine onto your system:

# 1. Clone the repository
git clone [https://github.com/azrin619/pi2-multinet-router.git](https://github.com/azrin619/pi2-multinet-router.git)
cd pi2-multinet-router

# 2. Build the DEB package
bash make_deb.sh

# 3. Install the package
sudo apt install ./berry-router-engine_1.2.0_all.deb


Resource,Absolute Minimum,Recommended (Ideal),Technical Reason
CPU,64-bit x86 Dual-Core (or Raspberry Pi 3/4/5),"64-bit Quad-Core (e.g., Intel Core i3/i5 or Pi 4/5)","Handles parallel multi-cloud ICMP latency probes, arping, and packet forwarding without bottlenecks."
RAM (Memory),1 GB,2 GB – 4 GB,Headless base system takes ~250–350 MB. Operating standard Cockpit web management consumes ~150 MB.
Storage (Disk),4 GB (USB Drive / SD / SSD),8 GB – 16 GB,Compressed SquashFS Live image takes ~1.2 GB. Remaining space is used for logs and .deb driver caches.
Network Interfaces,1x Built-in Ethernet + 1x Wi-Fi,2x Gigabit Ethernet + 1x Wi-Fi,Required for multi-WAN routing (router_engine.py) to handle load balancing and rapid failover.

🧮 Resource Breakdown & Calculations
1. Memory Overhead Breakdown
Base Linux Kernel + Init System: ~120 MB

4x Berry Python Services: ~80 MB (~20 MB each for IP assigner, Wi-Fi binder, driver loader, and cloud router engine)

OpenSSH + Network Stack: ~30 MB

Cockpit Web Console: ~120 MB (active only during active dashboard login)

Total Active Memory: ~350 MB – 450 MB (Operating at <25% memory usage on a 2 GB RAM system)

2. Disk Allocation (SquashFS + Persistent Overlay)
BERRY_BOOT Partition (FAT32): 2.5 GB

Kernel (vmlinuz) + Initrd: ~60 MB

UEFI / GRUB Bootloader: ~15 MB

Compressed filesystem.squashfs: ~1.2 GB

persistence Partition (EXT4): 1.0 GB – 5.5 GB

SSH Host Keys & Configs: ~5 MB

System Logs (journald capped): ~200 MB

Driver Package Cache: ~300 MB

Total Image Footprint: ~3.5 GB (Fits on 4 GB or 8 GB media)

💡 Old Laptop Recycling Tips
Power Settings & Lid Behavior: Linux is configured to ignore the laptop lid switch by default. Ensure "Suspend on Lid Close" is disabled in your OS power settings if installed permanently.

Built-in UPS: Old laptops make exceptional router appliances because their battery acts as an integrated Uninterruptible Power Supply (UPS) during unexpected power outages.

🛠️ Automated Git Updater Setup (Noob Guide)
To configure your system to automatically check GitHub for security hotfixes and patches every 6 hours, create these two files on your system:

Step 1: Create Service File
Create /etc/systemd/system/berry-patch-updater.service:

[Unit]
Description=Berry Router Git Patch & Hotfix Updater
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/berry_patch_updater.sh

Step 2: Create Timer File
Create /etc/systemd/system/berry-patch-updater.timer:

[Unit]
Description=Run Berry Router Patch Check Every 6 Hours

[Timer]
OnBootSec=10min
OnUnitActiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target

Step 3: Enable and Start the Timer
Run the following commands in your terminal:

sudo systemctl daemon-reload
sudo systemctl enable --now berry-patch-updater.timer

🌐 Management & Monitoring
Once installed or booted:

Web Management Console: https://192.168.1.88:9090 (or https://10.10.88.88:9090 via cross-over cable)

SSH Access: ssh root@192.168.1.88

Service Controls:

systemctl status berry-eth0-bootstrap.service  # Smart .88 Subnet Assigner
systemctl status berry-wifi-auto.service        # Wi-Fi Auto-Binder
systemctl status berry-driver-loader.service    # USB Driver Auto-Installer
systemctl status router-engine.service          # Multi-Cloud Router Engine
systemctl status berry-patch-updater.timer      # Automatic Patch Checker



