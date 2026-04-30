#!/bin/bash
exec >> /tmp/toggle_input.log 2>&1
echo "=== $(date) ==="

BUS=5
DP="x0f"
HDMI="x11"

CURRENT=$(ddcutil getvcp 60 --bus $BUS --brief 2>/dev/null | tail -1 | awk '{print $NF}')
echo "Current input: $CURRENT"

if [ "$CURRENT" == "$DP" ]; then
    echo "Switching to HDMI..."
    ddcutil setvcp 60 0x11 --bus $BUS --sleep-multiplier 0.1
else
    echo "Switching to DP..."
    ddcutil setvcp 60 0x0f --bus $BUS --sleep-multiplier 0.1
fi
