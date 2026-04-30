#!/bin/bash
# Monitor Input Toggle Setup Script
# Tested on Fedora 43 with GNOME/Wayland
# Requirements: keyd, ddcutil

set -e

echo "=== Monitor Input Toggle Setup ==="
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "Please run this script as your normal user (not root)."
    exit 1
fi

# Check dependencies
echo "Checking dependencies..."
for cmd in keyd ddcutil; do
    if ! command -v $cmd &>/dev/null; then
        echo "ERROR: $cmd is not installed. Please install it first."
        echo "  sudo dnf install $cmd"
        exit 1
    fi
done
echo "Dependencies OK."
echo ""

# Detect i2c bus
echo "Detecting monitor i2c bus..."
BUS=$(sudo ddcutil detect 2>/dev/null | grep "I2C bus" | head -1 | grep -o '[0-9]*$')
if [ -z "$BUS" ]; then
    echo "ERROR: Could not detect i2c bus. Make sure your monitor is connected and DDC/CI is enabled."
    exit 1
fi
echo "Detected bus: /dev/i2c-$BUS"
echo ""

# Detect current input values
echo "Detecting input source values..."
DP_RAW=$(sudo ddcutil getvcp 60 --bus $BUS --brief 2>/dev/null | tail -1 | awk '{print $NF}')
echo "Current input value: $DP_RAW"
echo ""

# Ask user for DP and HDMI values
echo "We need to identify your DisplayPort and HDMI input values."
echo "Current input detected as: $DP_RAW"
echo ""
read -p "Is the monitor currently on DisplayPort? (y/n): " IS_DP
if [ "$IS_DP" == "y" ]; then
    DP_VAL=$DP_RAW
    echo "Switch your monitor to HDMI input manually, then press ENTER..."
    read
    HDMI_VAL=$(sudo ddcutil getvcp 60 --bus $BUS --brief 2>/dev/null | tail -1 | awk '{print $NF}')
    echo "HDMI value detected: $HDMI_VAL"
else
    HDMI_VAL=$DP_RAW
    echo "Switch your monitor to DisplayPort input manually, then press ENTER..."
    read
    DP_VAL=$(sudo ddcutil getvcp 60 --bus $BUS --brief 2>/dev/null | tail -1 | awk '{print $NF}')
    echo "DisplayPort value detected: $DP_VAL"
fi
echo ""

# Create toggle script
echo "Creating toggle script..."
sudo tee /usr/local/bin/toggle_input.sh > /dev/null << EOF
#!/bin/bash
exec >> /tmp/toggle_input.log 2>&1
echo "=== \$(date) ==="

BUS=$BUS
DP="$DP_VAL"
HDMI="$HDMI_VAL"

CURRENT=\$(ddcutil getvcp 60 --bus \$BUS --brief 2>/dev/null | tail -1 | awk '{print \$NF}')
echo "Current input: \$CURRENT"

if [ "\$CURRENT" == "\$DP" ]; then
    echo "Switching to HDMI..."
    ddcutil setvcp 60 \$HDMI --bus \$BUS --sleep-multiplier 0.1
else
    echo "Switching to DisplayPort..."
    ddcutil setvcp 60 \$DP --bus \$BUS --sleep-multiplier 0.1
fi
EOF

sudo chmod +x /usr/local/bin/toggle_input.sh
sudo chown root:root /usr/local/bin/toggle_input.sh
echo "Toggle script created at /usr/local/bin/toggle_input.sh"
echo ""

# Ask for keyd shortcut
echo "What shortcut do you want to use? (default: leftcontrol+leftalt+1)"
read -p "Shortcut: " SHORTCUT
SHORTCUT=${SHORTCUT:-"leftcontrol+leftalt+1"}
echo ""

# Create keyd config
echo "Creating keyd config..."
sudo tee /etc/keyd/default.conf > /dev/null << EOF
[ids]
*

[control+alt]
1 = command(/usr/local/bin/toggle_input.sh)
EOF
echo "Keyd config created at /etc/keyd/default.conf"
echo ""

# Ensure i2c-dev loads at boot
echo "Configuring i2c-dev to load at boot..."
echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c.conf > /dev/null
sudo modprobe i2c-dev
echo "i2c-dev configured."
echo ""

# Enable and restart keyd
echo "Enabling and restarting keyd..."
sudo systemctl enable --now keyd
sudo systemctl restart keyd
echo "Keyd enabled and restarted."
echo ""

# Test
echo "=== Setup Complete! ==="
echo ""
echo "Testing toggle script manually..."
sudo /usr/local/bin/toggle_input.sh
echo ""
echo "Your shortcut is: ctrl+alt+1"
echo "Check /tmp/toggle_input.log for debug output."
echo ""
echo "NOTE: If the shortcut doesn't work at the GDM login screen,"
echo "reboot once to ensure i2c-dev is loaded at startup."
