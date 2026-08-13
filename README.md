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
sudo apt install ./berry-router-engine_1.0.0_all.deb
