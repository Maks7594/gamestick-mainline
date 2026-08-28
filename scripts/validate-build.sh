#!/bin/sh
set -eu

usage() {
	echo "Usage: validate-build.sh KERNEL_SOURCE KERNEL_BUILD ROOTFS [BOOT_IMG] [DISK_IMG]" >&2
}

[ "$#" -ge 3 ] && [ "$#" -le 5 ] || { usage; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo so protected rootfs files can be validated" >&2; exit 2; }
kernel_source=$1
kernel_build=$2
rootfs=$3
boot_image=${4:-}
disk_image=${5:-}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)

for path in "$kernel_source" "$kernel_build" "$rootfs"; do
	case "$path" in /|"") echo "Refusing unsafe path: $path" >&2; exit 2;; esac
	done

"$project_dir/kernel/validate-config.sh" "$kernel_build/.config"
"$project_dir/rootfs/validate-rootfs.sh" "$rootfs"

dtb="$kernel_build/arch/arm/boot/dts/allwinner/sun8i-t113s-h133-game-stick.dtb"
[ -s "$dtb" ] || { echo "ERROR: DTB is missing" >&2; exit 1; }
"$kernel_build/scripts/dtc/dtc" -I dtb -O dts "$dtb" >/dev/null

release=$(make -s -C "$kernel_source" O="$kernel_build" ARCH=arm kernelrelease)
module="$rootfs/lib/modules/$release/extra/8188eu.ko"
[ -s "$module" ] || { echo "ERROR: 8188eu module is missing" >&2; exit 1; }
[ -s "$rootfs/lib/modules/$release/modules.dep" ] || { echo "ERROR: modules.dep is missing" >&2; exit 1; }
[ -s "$rootfs/lib/modules/$release/modules.alias" ] || { echo "ERROR: modules.alias is missing" >&2; exit 1; }
[ -s "$rootfs/lib/firmware/rtlwifi/rtl8188eufw.bin" ] || { echo "ERROR: RTL8188EU firmware is missing" >&2; exit 1; }
grep -qi 'usb:v0BDAp0179' "$rootfs/lib/modules/$release/modules.alias" || {
	echo "ERROR: depmod aliases do not include USB 0bda:0179" >&2
	exit 1
}

if [ -n "$boot_image" ]; then
	[ -f "$boot_image" ] && [ ! -b "$boot_image" ] || { echo "ERROR: invalid boot image" >&2; exit 1; }
	[ "$(stat -c %s "$boot_image")" -le $((12600 * 512)) ] || { echo "ERROR: boot image is too large" >&2; exit 1; }
	file "$boot_image" | grep -q 'Android bootimg' || { echo "ERROR: not an Android boot image" >&2; exit 1; }
fi

if [ -n "$disk_image" ]; then
	[ -f "$disk_image" ] && [ ! -b "$disk_image" ] || { echo "ERROR: invalid disk image" >&2; exit 1; }
	table=$(sfdisk -d "$disk_image")
	[ "$(printf '%s\n' "$table" | grep -c '^.*start=')" -eq 5 ] || { echo "ERROR: disk image does not have five partitions" >&2; exit 1; }
	printf '%s\n' "$table" | grep -q 'start= *57120.*name="rootfs"' || { echo "ERROR: rootfs is not partition 5" >&2; exit 1; }
fi

echo "All firmware validation checks passed"
