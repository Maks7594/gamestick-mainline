#!/bin/sh
set -eu

[ "$#" -eq 1 ] || { echo "Usage: validate-config.sh KERNEL_CONFIG" >&2; exit 2; }
config=$1
[ -f "$config" ] || { echo "Missing kernel config: $config" >&2; exit 2; }

required_y='ARCH_SUNXI MACH_SUN8I SMP ARM_APPENDED_DTB CMDLINE_FORCE BINFMT_ELF BINFMT_SCRIPT BLK_DEV_INITRD INITRAMFS_FORCE DEVTMPFS DEVTMPFS_MOUNT DEVMEM PROC_FS SYSFS TMPFS EXT4_FS MODULES FW_LOADER MMC MMC_BLOCK MMC_SUNXI TTY SERIAL_8250 SERIAL_8250_CONSOLE SERIAL_8250_DW USB USB_EHCI_HCD USB_EHCI_HCD_PLATFORM USB_OHCI_HCD USB_OHCI_HCD_PLATFORM GENERIC_PHY PHY_SUN4I_USB NET UNIX PACKET INET WIRELESS RFKILL WLAN'
required_m='CFG80211 USB_USBNET USB_NET_CDCETHER'
for option in $required_y; do
	grep -qx "CONFIG_$option=y" "$config" || {
		echo "ERROR: CONFIG_$option must be built in" >&2
		exit 1
	}
done
for option in $required_m; do
	grep -qx "CONFIG_$option=m" "$config" || {
		echo "ERROR: CONFIG_$option must be a module" >&2
		exit 1
	}
done
# FB was forbidden for milestone 1, but simple-framebuffer on the display
# U-Boot already initialised is the only console this board has without a UART
# adapter. DRM is now allowed - see below - but DRM_SIMPLEDRM must stay off,
# because FB_SIMPLE depends on !DRM_SIMPLEDRM and simplefb is the fallback
# console if the ported HDMI PHY fails to bring the pipeline up.
for option in ARM_ATAG_DTB_COMPAT ARM_ATAG_DTB_COMPAT_CMDLINE_FROM_BOOTLOADER ARM_ATAG_DTB_COMPAT_CMDLINE_EXTEND CMDLINE_EXTEND DRM_SIMPLEDRM BT MEDIA_SUPPORT; do
	if grep -Eq "^CONFIG_$option=[ym]$" "$config"; then
		echo "ERROR: CONFIG_$option must remain disabled for milestone 1" >&2
		exit 1
	fi
done
# The fallback only exists if both paths are actually compiled in.
for option in FB_SIMPLE DRM DRM_SUN4I DRM_SUN8I_MIXER DRM_SUN8I_DW_HDMI DRM_FBDEV_EMULATION; do
	grep -qx "CONFIG_$option=y" "$config" || {
		echo "ERROR: CONFIG_$option must be built in for the display pipeline" >&2
		exit 1
	}
done

echo "Kernel configuration checks passed"
