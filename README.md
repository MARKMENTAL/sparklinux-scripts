# Spark Linux Build Scripts

A collection of build scripts for creating customized Spark Linux images based on Alpine Linux Edge.

## Overview

Spark Linux is a lightweight Linux distribution designed for developers, featuring pre-installed development tools and utilities. This repository contains the build scripts used to create Spark Linux images.

Before starting, please familiarize yourself with the mkimage scripts from Alpine Linux, as this is the environment mine is based off of.

[How to make a custom ISO image with mkimage - Alpine Linux](https://wiki.alpinelinux.org/wiki/How_to_make_a_custom_ISO_image_with_mkimage)

## Repository Structure
```
sparklinux-scripts/
├── aports/         # Alpine Linux package build files and scripts
├── build-spark.sh  # Main build script based on Alpine's mkimage
├── iso/            # Output directory for built ISO images
└── tmp/           # Temporary build files
```

## Features

- Based on Alpine Linux Edge
- Pre-installed development tools:
  - Python 3 + pip
  - Docker + CLI tools
  - Neovim
  - Git
  - GCC + build tools
  - Nim compiler
- Custom system information tool (`versioninfo`)
- Integrated Docker management script (`spark-dock`)
- Built-in Python web server
- doas configuration for system administration

## Build Requirements

- Alpine Linux build environment
- `alpine-sdk alpine-conf syslinux xorriso squashfs-tools grub grub-efi doas` packages installed
- `qemu` for testing virtual machine images
- Sufficient disk space (at least 4GB recommended)

## Building

1. Clone the repository:
```bash
git clone https://github.com/markmental/sparklinux-scripts
cd sparklinux-scripts
```

2. Make the build script executable:
```bash
chmod +x build-spark.sh
```

3. Run the build script:
```bash
./build-spark.sh
```

The built ISO will be available in the `iso/` directory.

## Build Script Components

### build-spark.sh
- Based on Alpine Linux's mkimage
- Creates a custom ISO image
- Integrates the overlay files
- Configures boot parameters

### aports/
- Contains package build files
- Custom script modifications
- System configurations

### Key Files
- `genapkovl` script in aports/ for system overlay
- `spark-setup.sh` for system initialization
- Custom tools and configurations

## Custom Tools

#### versioninfo
- Displays system information:
  - Spark Linux version
  - Kernel details
  - CPU usage
  - RAM usage

#### spark-dock
- Interactive Docker management tool
- Container and image management
- Port mapping configuration
- MySQL container setup

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## Testing

To test the built image:
```bash
qemu-system-x86_64 -boot d -cdrom iso/spark-linux-VERSION.iso -m 2048
```

## Acknowledgments

Based on Alpine Linux and built using Alpine's mkimage tool.
