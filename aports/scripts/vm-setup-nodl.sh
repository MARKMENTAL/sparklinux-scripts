#!/bin/ash

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

echo "QEMU VM Launcher with Bridge Setup"
echo "=================================="

# Default values
ISO_FILE="Fedora-KDE-Live-x86_64-40-1.14.iso"
DISK_FILE="fedorakde.qcow2"
RAM_SIZE=2048
VNC_DISPLAY=0
DISK_SIZE=25G
BRIDGE_NAME="br0"
PHYSICAL_IF="eth0"

# Function to list available network interfaces
list_interfaces() {
    echo "Available network interfaces:"
    ip link show | awk -F': ' '{print $2}' | grep -v lo | sed 's/@.*//'
}

# Function to set up bridge
setup_bridge() {
    echo "Setting up bridge $BRIDGE_NAME with interface $PHYSICAL_IF"

    # Get current IP, netmask, and gateway
    IP_ADDR=$(ip -f inet addr show "$PHYSICAL_IF" | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')
    NETMASK=$(ip -f inet addr show "$PHYSICAL_IF" | sed -En -e 's/.*inet [0-9.]+\/([0-9]+).*/\1/p')
    GATEWAY=$(ip route | grep default | awk '{print $3}')

    # Convert CIDR notation to dotted decimal
    NETMASK=$(ipcalc -m $IP_ADDR/$NETMASK | cut -d= -f2)

    # Check if bridge already exists
    if ip link show "$BRIDGE_NAME" >/dev/null 2>&1; then
        echo "Bridge $BRIDGE_NAME already exists. Skipping creation."
    else
        # Create bridge
        ip link add name "$BRIDGE_NAME" type bridge
        ip link set dev "$BRIDGE_NAME" up
    fi

    # Check if interface is already part of the bridge
    if ! ip link show "$PHYSICAL_IF" | grep -q "master $BRIDGE_NAME"; then
        # Add physical interface to bridge
        ip link set dev "$PHYSICAL_IF" master "$BRIDGE_NAME"
    fi

    # Remove IP from physical interface if it exists
    ip addr flush dev "$PHYSICAL_IF"

    # Check if IP is already assigned to the bridge
    if ! ip addr show dev "$BRIDGE_NAME" | grep -q "$IP_ADDR"; then
        # Set IP on bridge
        ip addr add "$IP_ADDR/$NETMASK" dev "$BRIDGE_NAME"
    else
        echo "IP $IP_ADDR is already assigned to $BRIDGE_NAME"
    fi

    # Set default gateway
    ip route replace default via "$GATEWAY" dev "$BRIDGE_NAME"

    # Update /etc/network/interfaces
    cp /etc/network/interfaces /etc/network/interfaces.bak
    cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto $PHYSICAL_IF
iface $PHYSICAL_IF inet manual

auto $BRIDGE_NAME
iface $BRIDGE_NAME inet static
    bridge_ports $PHYSICAL_IF
    address $IP_ADDR
    netmask $NETMASK
    gateway $GATEWAY
EOF

    # Prepare bridge for QEMU
    mkdir -p /etc/qemu
    echo "allow $BRIDGE_NAME" >> /etc/qemu/bridge.conf

    # Create /dev/net/tun if it doesn't exist
    if [ ! -c /dev/net/tun ]; then
        mkdir -p /dev/net
        mknod /dev/net/tun c 10 200
        chmod 666 /dev/net/tun
    fi

    # Set correct permissions for QEMU bridge helper
    chown root:root /usr/lib/qemu/qemu-bridge-helper
    chmod u+s /usr/lib/qemu/qemu-bridge-helper

    echo "Bridge setup complete. Running network diagnostics..."

    # Network diagnostics
    echo "Current IP configuration:"
    ip addr show "$BRIDGE_NAME"
    echo "\nCurrent routing table:"
    ip route
    echo "\nTrying to ping gateway..."
    ping -c 4 "$GATEWAY"

    echo "\nBridge setup and diagnostics complete."
    echo "You may need to restart networking for changes to take effect:"
    echo "Run 'rc-service networking restart' or reboot the system."
}

# Prompt for ISO file
echo -n "Enter ISO file name (default: $ISO_FILE): "
read input
[ -n "$input" ] && ISO_FILE=$input

# Check if ISO file exists
if [ ! -f "$ISO_FILE" ]; then
    echo "Warning: ISO file '$ISO_FILE' not found."
fi

# Prompt for disk file
echo -n "Enter QCOW2 disk file name (default: $DISK_FILE): "
read input
[ -n "$input" ] && DISK_FILE=$input

# Check if QCOW2 file exists, offer to create if it doesn't
if [ ! -f "$DISK_FILE" ]; then
    echo "QCOW2 file '$DISK_FILE' not found."
    echo -n "Do you want to create it? (y/n): "
    read create_disk
    if [ "$create_disk" = "y" ] || [ "$create_disk" = "Y" ]; then
        echo -n "Enter disk size (default: $DISK_SIZE): "
        read input
        [ -n "$input" ] && DISK_SIZE=$input
        qemu-img create -f qcow2 "$DISK_FILE" "$DISK_SIZE"
        if [ $? -ne 0 ]; then
            echo "Failed to create QCOW2 file. Exiting."
            exit 1
        fi
        echo "QCOW2 file created successfully."
    else
        echo "QCOW2 file is required but not found. Exiting."
        exit 1
    fi
fi

# Prompt for RAM size
echo -n "Enter RAM size in MB (default: $RAM_SIZE): "
read input
[ -n "$input" ] && RAM_SIZE=$input

# Prompt for VNC display
echo -n "Enter VNC display number (default: $VNC_DISPLAY): "
read input
[ -n "$input" ] && VNC_DISPLAY=$input

# Prompt for network bridge setup
echo -n "Do you want to set up a network bridge? (y/n): "
read setup_bridge
if [ "$setup_bridge" = "y" ] || [ "$setup_bridge" = "Y" ]; then
    list_interfaces
    echo -n "Enter the name of the physical interface to bridge (default: $PHYSICAL_IF): "
    read input
    [ -n "$input" ] && PHYSICAL_IF=$input
    echo -n "Enter the name for the bridge interface (default: $BRIDGE_NAME): "
    read input
    [ -n "$input" ] && BRIDGE_NAME=$input
    setup_bridge
else
    BRIDGE_NAME=""
fi

# Construct the QEMU command
if [ -n "$BRIDGE_NAME" ]; then
    QEMU_CMD="qemu-system-x86_64 -m $RAM_SIZE -cdrom $ISO_FILE -boot d -enable-kvm -hda $DISK_FILE -nic bridge,br=$BRIDGE_NAME,model=virtio,helper=/usr/lib/qemu/qemu-bridge-helper -vnc :$VNC_DISPLAY"
else
    QEMU_CMD="qemu-system-x86_64 -m $RAM_SIZE -cdrom $ISO_FILE -boot d -enable-kvm -hda $DISK_FILE -net nic -net user -vnc :$VNC_DISPLAY"
fi

echo "Executing: $QEMU_CMD"
eval $QEMU_CMD

