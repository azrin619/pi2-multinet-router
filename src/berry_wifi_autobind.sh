#!/usr/bin/env bash
set -e

CONF_FILE="/etc/berry-router/wifi.conf"
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"

if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
else
    WIFI_SSID="MyRouterNetwork"
    WIFI_PASS="RouterSecret123"
fi

get_wifi_interface() {
    ip -j link show | grep -oP '"ifname":"\K(wlan[0-9]+|wlp[0-9]+s[0-9]+)' | head -n 1
}

while true; do
    IFACE=$(get_wifi_interface)

    if [ -n "$IFACE" ]; then
        ip link set "$IFACE" up 2>/dev/null || true

        # Check if interface is connected to target SSID
        if ! iwconfig "$IFACE" 2>/dev/null | grep -q "$WIFI_SSID"; then
            echo "[Wi-Fi AutoBind] Target SSID '$WIFI_SSID' not connected on $IFACE. Initiating secure binding..."

            # Securely write wpa_supplicant config
            mkdir -p /etc/wpa_supplicant
            touch "$WPA_CONF"
            chmod 600 "$WPA_CONF"
            
            wpa_passphrase "$WIFI_SSID" "$WIFI_PASS" > "$WPA_CONF"

            # Clean up stale supplicant processes for this specific interface
            pkill -f "wpa_supplicant.*$IFACE" || true
            sleep 1

            # Connect and request lease
            wpa_supplicant -B -i "$IFACE" -c "$WPA_CONF" &>/dev/null || true
            dhclient -v "$IFACE" &>/dev/null || true
        fi
    fi
    sleep 15
done
