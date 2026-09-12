#!/bin/bash
# Retry-connect a Bluetooth device at login, since BlueZ only auto-reconnects
# on link loss (suspend/resume), not on a fresh boot.
MAC="${1:?usage: bt-autoconnect.sh AA:BB:CC:DD:EE:FF}"
ATTEMPTS=20
INTERVAL=5

for i in $(seq 1 "$ATTEMPTS"); do
    if bluetoothctl info "$MAC" | grep -q "Connected: yes"; then
        exit 0
    fi
    bluetoothctl connect "$MAC" >/dev/null 2>&1
    sleep "$INTERVAL"
done

exit 1
