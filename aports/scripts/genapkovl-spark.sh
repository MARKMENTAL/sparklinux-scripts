#!/bin/sh -e

HOSTNAME="$1"
if [ -z "$HOSTNAME" ]; then
        echo "usage: $0 hostname"
        exit 1
fi

cleanup() {
        rm -rf "$tmp"
}

makefile() {
        OWNER="$1"
        PERMS="$2"
        FILENAME="$3"
        cat > "$FILENAME"
        chown "$OWNER" "$FILENAME"
        chmod "$PERMS" "$FILENAME"
}

rc_add() {
        mkdir -p "$tmp"/etc/runlevels/"$2"
        ln -sf /etc/init.d/"$1" "$tmp"/etc/runlevels/"$2"/"$1"
}

tmp="$(mktemp -d)"
trap cleanup EXIT

mkdir -p "$tmp"/etc
# Move vm creation script into the build
cp ~/aports/scripts/vm-setup-nodl.sh "$tmp"/etc/spark-vm-setup

makefile root:root 0644 "$tmp"/etc/hostname <<EOF
$HOSTNAME
EOF

mkdir -p "$tmp"/etc/apk
makefile root:root 0644 "$tmp"/etc/apk/world <<EOF
alpine-base
EOF

# Add custom message to /etc/motd for the live environment
makefile root:root 0644 "$tmp"/etc/motd <<EOF
Welcome to Spark Linux by markmental! 
This is a Linux distribution based on Alpine Linux Edge.
It is tailored for coders, and provides a lightweight but useful OS, with tools you can use to easily get a coding project started.
Expect to find tools like python3, docker, neovim, gcc, and nim preinstalled, so you can focus on the code instead of installing packages.

To install these customizations & set up your system, please run:
sh /root/spark-setup.sh

This will update your system, install necessary packages, and run the Alpine setup wizard.
EOF

# Add custom /etc/issue file
makefile root:root 0644 "$tmp"/etc/issue <<EOF
Welcome to Spark Linux Alpha 0.1.5
EOF

# Create the spark-setup.sh script in /root
mkdir -p "$tmp"/root
makefile root:root 0755 "$tmp"/root/spark-setup.sh <<EOF
#!/bin/sh

if [ ! -f /etc/spark-setup-done ]; then
    echo "Installing Spark Linux packages..."
    apk update && apk upgrade
    apk add bridge-utils qemu qemu-img qemu-system-x86_64 openntpd neovim docker docker-cli nim git python3 py3-pip gcc build-base doas
    echo "Compiling versioninfo..."
cat << 'EOL' > /usr/bin/versioninfo.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysinfo.h>
#include <sys/utsname.h>

#define PROC_STAT "/proc/stat"

double get_cpu_usage() {
    static long long prev_idle = 0, prev_total = 0;
    long long user, nice, system, idle, iowait, irq, softirq, steal, guest, guest_nice;
    long long total;
    double cpu_usage;
    FILE *fp;

    fp = fopen(PROC_STAT, "r");
    if (fp == NULL) return -1;

    fscanf(fp, "cpu %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld",
           &user, &nice, &system, &idle, &iowait, &irq, &softirq, &steal, &guest, &guest_nice);
    fclose(fp);

    total = user + nice + system + idle + iowait + irq + softirq + steal;

    cpu_usage = (1.0 - (idle - prev_idle) / (double)(total - prev_total)) * 100.0;

    prev_idle = idle;
    prev_total = total;

    return cpu_usage;
}

void get_ram_usage(unsigned long *used, unsigned long *total) {
    struct sysinfo info;
    sysinfo(&info);
    *total = info.totalram / (1024 * 1024);
    *used = *total - (info.freeram / (1024 * 1024));
}

int main() {
    struct utsname uname_data;
    unsigned long used_ram, total_ram;

    uname(&uname_data);
    get_ram_usage(&used_ram, &total_ram);

    printf("\033[1;33mSpark Linux Alpha 0.1.5 (10-15-2024)\033[0m\n");
    printf("Kernel: %s %s\n", uname_data.sysname, uname_data.release);
    printf("CPU Usage: %.2f%%\n", get_cpu_usage());
    printf("RAM Usage: %lu MB / %lu MB\n", used_ram, total_ram);
    return 0;
}
EOL
    gcc -o /usr/bin/versioninfo /usr/bin/versioninfo.c
    rm /usr/bin/versioninfo.c

    echo "Alpine/Spark install wizard will start soon.." && sleep 5 && setup-alpine

    # Prompt for non-root user
    echo "Please enter the name of a non-root user you created during setup:"
    read NON_ROOT_USER

    # Use Python to detect the install partition and boot partition
    PARTITIONS=\$(python3 -c "
import subprocess
import re

def get_partitions():
    output = subprocess.check_output(['fdisk', '-l'], universal_newlines=True)
    partitions = []
    current_disk = None
    for line in output.split('\n'):
        if line.startswith('Disk /dev/'):
            current_disk = line.split()[1].rstrip(':')
        elif line.startswith('/dev/'):
            parts = line.split()
            if len(parts) >= 7:
                device, boot, start, end, sectors, size, id_type = parts[:7]
                partitions.append({
                    'device': device,
                    'boot': boot == '*',
                    'size': size,
                    'type': ' '.join(parts[6:])
                })
    return partitions

def parse_size(size):
    match = re.match(r'(\d+(\.\d+)?)\s*(\w+)', size)
    if match:
        value, _, unit = match.groups()
        value = float(value)
        if unit == 'G':
            return value * 1024 * 1024 * 1024
        elif unit == 'M':
            return value * 1024 * 1024
        elif unit == 'K':
            return value * 1024
    return float(size)

partitions = get_partitions()
linux_partitions = [p for p in partitions if 'Linux' in p['type'] and not p['boot']]
boot_partition = next((p for p in partitions if p['boot']), None)

if linux_partitions:
    largest = max(linux_partitions, key=lambda p: parse_size(p['size']))
    print(f'{largest['device']},{boot_partition['device'] if boot_partition else ''}')
else:
    print(',')
")

    INSTALL_DEVICE=\$(echo \$PARTITIONS | cut -d',' -f1)
    BOOT_DEVICE=\$(echo \$PARTITIONS | cut -d',' -f2)

    if [ -z "\$INSTALL_DEVICE" ]; then
        echo "Could not automatically detect the install partition. Please enter it manually (e.g., /dev/sda3):"
        read INSTALL_DEVICE
    else
        echo "Before we reboot, here is the final part of the Spark Linux install..."
        echo "Detected install partition: \$INSTALL_DEVICE"
        echo "Detected boot partition: \$BOOT_DEVICE"
        echo "We need to make a couple adjustments to the filesystem before reboot, so your correct partitions are needed."
        echo "If the install partition is incorrect, please enter the correct device, otherwise press Enter:"
        read USER_INPUT
        if [ ! -z "\$USER_INPUT" ]; then
            INSTALL_DEVICE=\$USER_INPUT
        fi
        echo "If the boot partition is incorrect, please enter the correct device, otherwise press Enter:"
        read USER_INPUT
        if [ ! -z "\$USER_INPUT" ]; then
            BOOT_DEVICE=\$USER_INPUT
        fi
    fi

    # Mount the installed system
    mkdir -p /mnt/newsystem
    mount \$INSTALL_DEVICE /mnt/newsystem

    # Mount the boot partition
    mkdir -p /mnt/newboot
    mount \$BOOT_DEVICE /mnt/newboot

    # Copy versioninfo to the installed system
    cp /usr/bin/versioninfo /mnt/newsystem/usr/bin/

    # Modify /etc/os-release
    sed -i 's/^NAME="Alpine Linux"/NAME="Spark Linux"/' /mnt/newsystem/etc/os-release
    sed -i 's/^ID=alpine/ID=spark/' /mnt/newsystem/etc/os-release
    sed -i 's/^VERSION_ID=.*/VERSION_ID=0.1/' /mnt/newsystem/etc/os-release
    sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Spark Linux Alpha 0.1.5"/' /mnt/newsystem/etc/os-release
    echo 'HOME_URL="https://github.com/markmental/SparkLinux"' >> /mnt/newsystem/etc/os-release

    # Modify /boot/extlinux.conf
    sed -i 's/MENU TITLE Alpine/MENU TITLE Spark/' /mnt/newboot/extlinux.conf
    sed -i 's/LABEL alpine/LABEL spark/' /mnt/newboot/extlinux.conf
    sed -i 's/MENU LABEL Alpine/MENU LABEL Spark/' /mnt/newboot/extlinux.conf
    sed -i 's/Alpine will be booted automatically in/Spark Linux will be booted automatically in/' /mnt/newboot/extlinux.conf

    # Comment out lines in /etc/apk/repositories
    sed -i 's/^/#/' /mnt/newsystem/etc/apk/repositories

    # Create an empty /etc/motd for the installed system
    echo -n > /mnt/newsystem/etc/motd

    # Create .profile for root and non-root user
    cat << 'EOL' > /mnt/newsystem/root/.profile
#!/bin/sh
versioninfo
EOL

    if [ ! -z "\$NON_ROOT_USER" ]; then
        cp /mnt/newsystem/root/.profile /mnt/newsystem/home/\$NON_ROOT_USER/.profile
        chown \$NON_ROOT_USER:\$NON_ROOT_USER /mnt/newsystem/home/\$NON_ROOT_USER/.profile
        
        # Create sparkadmins group and add the user to it
        chroot /mnt/newsystem addgroup sparkadmins
        chroot /mnt/newsystem adduser \$NON_ROOT_USER sparkadmins
    fi

    # Set up doas configuration
    mkdir -p /mnt/newsystem/etc/doas.d
    cat << EOL > /mnt/newsystem/etc/doas.d/doas.conf
permit :sparkadmins
permit persist :sparkadmins
EOL

    # Create spark-dock.sh
cat << 'EOL' > /mnt/newsystem/usr/bin/spark-dock
#!/bin/sh

# Check if Docker is running
if ! rc-service docker status | grep -q "started"; then
    echo "Docker is not running. Starting Docker service..."
    rc-service docker start
fi

while true; do
    echo "Docker Management Menu"
    echo "1. Pull Docker Image"
    echo "2. Run/Create Docker Container Interactively"
    echo "3. List All Docker Containers"
    echo "4. List All Docker Images"
    echo "5. Start Interactive Container Session"
    echo "6. Start Detached Container Session"
    echo "7. Delete Docker Image"
    echo "8. Stop Docker Container"
    echo "9. Remove Docker Container"
    echo "10. Access Interactive Shell of Running Container"
    echo "11. Spin Up MySQL Docker Container"
    echo "12. Exit"
    read -p "Choose an option: " option

    case "\$option" in
        1)
            read -p "Enter the Docker image to pull (e.g., alpine): " image
            docker pull "\$image"
            ;;
        2)
            read -p "Enter the Docker image to run interactively (e.g., alpine): " image
            read -p "How many port mappings do you want to add? " port_count
            ports=""
            i=1
            while [ "\$i" -le "\$port_count" ]; do
                read -p "Enter port mapping #\$i (e.g., 8081:8081): " port
                ports="\$ports -p \$port"
                i=\$((i + 1))
            done
            docker run -it \$ports "\$image" /bin/sh
            ;;
        3)
            docker ps -a
            ;;
        4)
            docker images
            ;;
        5)
            read -p "Enter the container ID to start interactively: " containerid
            docker start -ai "\$containerid"
            ;;
        6)
            read -p "Enter the container ID to start in detached mode: " containerid
            docker start "\$containerid"
            ;;
        7)
            read -p "Enter the Docker image name or ID to delete: " image
            docker rmi "\$image"
            ;;
        8)
            read -p "Enter the container ID to stop: " containerid
            docker stop "\$containerid"
            ;;
        9)
            read -p "Enter the container ID to remove: " containerid
            docker rm "\$containerid"
            ;;
        10)
            read -p "Enter the container ID to access an interactive shell: " containerid
            docker exec -it "\$containerid" /bin/sh
            ;;
        11)
            read -p "Enter the port range (e.g., 3306:3306): " port
            read -p "Enter the MySQL root password: " mysql_password
            read -p "Enter the MySQL version tag (e.g., 8): " mysql_version
            docker run -p "\$port" --name mysql-container -e MYSQL_ROOT_PASSWORD="\$mysql_password" -d mysql:"\$mysql_version"
            ;;
        12)
            break
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac
done
EOL

    # Make spark-dock.sh executable
    chmod +x /mnt/newsystem/usr/bin/spark-dock

    # Copy spark-vm-setup to the new system
    cp /etc/spark-vm-setup /mnt/newsystem/usr/sbin/spark-vm
    chmod +x /mnt/newsystem/usr/sbin/spark-vm
    rm /etc/spark-vm-setup

    # Set up Python Web Server
    echo "Setting up Python Web Server..."
    mkdir -p /mnt/newsystem/var/www/html

    # Create a test.html file
    cat << 'EOL' > /mnt/newsystem/var/www/html/test.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to Spark Linux</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background-color: #f0f0f0;
        }
        .container {
            text-align: center;
            padding: 20px;
            background-color: white;
            border-radius: 10px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Hello Spark Linux!</h1>
        <p>This is a test page served by the Python HTTP server.</p>
    </div>
</body>
</html>
EOL

    echo "Test HTML file created."

    cat << 'EOL' > /mnt/newsystem/etc/init.d/pythonwebserver
#!/sbin/openrc-run

name="Python Web Server"
description="Simple HTTP server using Python3"
command="/usr/bin/python3"
command_args="-m http.server 1337"
command_background="yes"
pidfile="/run/${RC_SVCNAME}.pid"
directory="/var/www/html"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath -d -m 0755 -o root:root /var/www/html
}
EOL
    chmod +x /mnt/newsystem/etc/init.d/pythonwebserver

    # Add the service to the default runlevel in the new system
    chroot /mnt/newsystem /sbin/rc-update add pythonwebserver default

    echo "Python Web Server setup complete."

    chroot /mnt/newsystem /sbin/rc-update add openntpd default
    echo "OpenNTPD setup complete..."


    # Unmount the installed system and boot partition
    umount /mnt/newsystem
    umount /mnt/newboot
    rmdir /mnt/newsystem
    rmdir /mnt/newboot

    touch /etc/spark-setup-done
    echo "Spark Linux setup completed. You may reboot."
else
    echo "Spark Linux setup has already been completed."
    echo "If you need to run it again, please delete /etc/spark-setup-done and rerun this script."
fi
EOF

rc_add devfs sysinit
rc_add dmesg sysinit
rc_add mdev sysinit
rc_add hwdrivers sysinit
rc_add modloop sysinit

rc_add hwclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

tar -c -C "$tmp" etc root | gzip -9n > $HOSTNAME.apkovl.tar.gz

