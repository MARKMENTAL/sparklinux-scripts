profile_standard() {
        title="Standard"
        desc="Alpine as it was intended.
                Just enough to get you started.
                Network connection is required."
        profile_base
        profile_abbrev="std"
        image_ext="iso"
        arch="aarch64 armv7 x86 x86_64 ppc64le s390x loongarch64"
        output_format="iso"
        kernel_addons="xtables-addons"
        case "$ARCH" in
        s390x)
                apks="$apks s390-tools"
                initfs_features="$initfs_features dasd_mod qeth zfcp"
                initfs_cmdline="modules=loop,squashfs,dasd_mod,qeth,zfcp quiet"
                ;;
        ppc64le)
                initfs_cmdline="modules=loop,squashfs,sd-mod,usb-storage,ibmvscsi quiet"
                ;;
        esac
        apks="$apks iw wpa_supplicant"
}


profile_custom_preloaded() {
    profile_standard
    kernel_cmdline="console=tty0 console=ttyS0,115200"
    syslinux_serial="0 115200"
    apks="$apks gcc bash neofetch python3 neovim"
    apkovl="genapkovl-custom_preloaded.sh"
}
