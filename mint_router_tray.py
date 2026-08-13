#!/usr/bin/env python3
import os
import json
import subprocess
import threading
import time

import gi
gi.require_version('Gtk', '3.0')
try:
    gi.require_version('AyatanaAppIndicator3', '0.1')
    from gi.repository import AyatanaAppIndicator3 as AppIndicator
except ValueError:
    gi.require_version('AppIndicator3', '0.1')
    from gi.repository import AppIndicator3 as AppIndicator

from gi.repository import Gtk, GLib

APP_ID = "multi-cloud-router-tray"

CLOUD_PROBES = {
    "Azure SEA": "20.198.120.1",
    "AWS SEA": "15.197.148.33",
    "GCP Asia": "34.87.0.1",
    "Aliyun HK": "47.88.255.55",
    "Cloudflare": "1.1.1.1"
}

class RouterTrayApp:
    def __init__(self):
        self.indicator = AppIndicator.Indicator.new(
            APP_ID,
            "network-transmit-receive",  # System icon name
            AppIndicator.IndicatorCategory.SYSTEM_SERVICES
        )
        self.indicator.set_status(AppIndicator.IndicatorStatus.ACTIVE)
        self.indicator.set_label(" 🌐 Loading...", "")

        self.menu = Gtk.Menu()
        self.indicator.set_menu(self.menu)

        # Start initial background probe thread
        self.update_data()

        # Refresh tray every 30 seconds
        GLib.timeout_add_seconds(30, self.trigger_async_update)

    def trigger_async_update(self):
        threading.Thread(target=self.update_data, daemon=True).start()
        return True

    def get_gateways(self):
        """Parse active network interfaces and default routes."""
        try:
            res = subprocess.run(["ip", "-j", "route", "show"], capture_output=True, text=True)
            routes = json.loads(res.stdout)
            gateways = {}
            for r in routes:
                if "gateway" in r and "dev" in r and r["dev"] != "lo":
                    gateways[r["dev"]] = r["gateway"]
            return gateways
        except Exception:
            return {}

    def ping_target(self, ip):
        """Ping target and return latency float in ms."""
        try:
            res = subprocess.run(["ping", "-c", "1", "-W", "1", ip], capture_output=True, text=True)
            if res.returncode == 0:
                for line in res.stdout.split('\n'):
                    if "time=" in line:
                        time_str = line.split("time=")[1].split(" ")[0]
                        return float(time_str)
        except Exception:
            pass
        return 999.0

    def update_data(self):
        """Fetch metrics and rebuild tray menu items."""
        gateways = self.get_gateways()
        metrics = {}

        # Probe latency to each target
        best_overall = 999.0
        for name, ip in CLOUD_PROBES.items():
            rtt = self.ping_target(ip)
            metrics[name] = rtt
            if rtt < best_overall:
                best_overall = rtt

        # Schedule GTK menu updates on main UI thread
        GLib.idle_add(self.rebuild_menu, gateways, metrics, best_overall)

    def rebuild_menu(self, gateways, metrics, best_overall):
        # Update tray title label
        if best_overall < 999.0:
            self.indicator.set_label(f" ⚡ {best_overall:.0f}ms", "")
        else:
            self.indicator.set_label(" ⚠️ Offline", "")

        # Clear existing menu items
        for item in self.menu.get_children():
            self.menu.remove(item)

        # --- Section: Status Header ---
        status_label = f"Active WANs: {len(gateways)} interface(s)"
        header_item = Gtk.MenuItem(label=f"<b>{status_label}</b>")
        header_item.get_child().set_use_markup(True)
        header_item.set_sensitive(False)
        self.menu.append(header_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        # --- Section: Interfaces & Gateways ---
        if gateways:
            for iface, gw in gateways.items():
                gw_item = Gtk.MenuItem(label=f" 🌐 {iface} ➔ {gw}")
                gw_item.set_sensitive(False)
                self.menu.append(gw_item)
        else:
            no_gw_item = Gtk.MenuItem(label=" ⚠️ No Default Gateways Detected")
            no_gw_item.set_sensitive(False)
            self.menu.append(no_gw_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        # --- Section: Cloud Latencies ---
        cloud_header = Gtk.MenuItem(label="<b>Cloud Metrics (RTT):</b>")
        cloud_header.get_child().set_use_markup(True)
        cloud_header.set_sensitive(False)
        self.menu.append(cloud_header)

        for name, rtt in metrics.items():
            rtt_str = f"{rtt:.1f} ms" if rtt < 999.0 else "Timeout"
            item = Gtk.MenuItem(label=f"   • {name:<12}: {rtt_str}")
            item.set_sensitive(False)
            self.menu.append(item)

        self.menu.append(Gtk.SeparatorMenuItem())

        # --- Section: Actions ---
        sync_item = Gtk.MenuItem(label="🔄 Sync Routes Now")
        sync_item.connect("activate", self.on_sync_clicked)
        self.menu.append(sync_item)

        quit_item = Gtk.MenuItem(label="❌ Quit Tray Indicator")
        quit_item.connect("activate", Gtk.main_quit)
        self.menu.append(quit_item)

        self.menu.show_all()

    def on_sync_clicked(self, widget):
        self.indicator.set_label(" 🔄 Syncing...", "")
        # Restart background router engine service if installed
        threading.Thread(target=self.run_service_restart, daemon=True).start()

    def run_service_restart(self):
        subprocess.run(["sudo", "systemctl", "restart", "router-engine"])
        time.sleep(2)
        self.update_data()

if __name__ == "__main__":
    app = RouterTrayApp()
    Gtk.main()
