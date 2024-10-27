profile_custom_gcc_bash() {
    profile_standard
    kernel_cmdline="console=tty0 console=ttyS0,115200"
    syslinux_serial="0 115200"
    apks="$apks gcc bash neofetch python3 neovim"
    local _k _a
    for _k in $kernel_flavors; do
        apks="$apks linux-$_k"
        for _a in $kernel_addons; do
            apks="$apks $_a-$_k"
        done
    done
    apks="$apks linux-firmware"
    
    # Create a custom script to install packages
    local tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir"/etc/local.d
    cat > "$tmpdir"/etc/local.d/custom-packages.start <<EOF
#!/bin/sh

# Check if packages are already installed
if ! apk info -e gcc bash neofetch python3 neovim > /dev/null 2>&1; then
    echo "Installing custom packages..."
    apk update
    apk add gcc bash neofetch python3 neovim
fi
EOF
    chmod +x "$tmpdir"/etc/local.d/custom-packages.start

    # Create an overlay tarball
    tar -c -C "$tmpdir" etc | gzip -9n > "$WORKDIR"/custom-packages.apkovl.tar.gz
    rm -rf "$tmpdir"
}
