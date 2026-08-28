#!/bin/sh
set -eu

usage() {
	cat <<'EOF'
Usage: build-install-rtl8188eu.sh DRIVER_SOURCE KERNEL_SOURCE KERNEL_BUILD ROOTFS [CROSS_COMPILE]

Build the pinned 8188eu module against the already-built kernel and install it,
its firmware, and depmod metadata into ROOTFS. All paths must be explicit.
EOF
}

[ "$#" -ge 4 ] && [ "$#" -le 5 ] || { usage >&2; exit 2; }
driver_source=$1
kernel_source=$2
kernel_build=$3
rootfs=$4
cross_compile=${5:-arm-linux-musleabihf-}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

for path in "$driver_source" "$kernel_source" "$kernel_build" "$rootfs"; do
	case "$path" in /|"") echo "Refusing unsafe path: $path" >&2; exit 2;; esac
	[ ! -b "$path" ] || { echo "Refusing block device: $path" >&2; exit 2; }
done
[ -d "$driver_source/.git" ] || { echo "Driver source must be a git checkout" >&2; exit 2; }
[ -f "$kernel_build/.config" ] || { echo "Kernel has not been configured" >&2; exit 2; }
[ -d "$rootfs/etc" ] || { echo "Not a root filesystem: $rootfs" >&2; exit 2; }

expected_commit=f42fc9c45d2086c415dce70d3018031b54a7beef
actual_commit=$(git -C "$driver_source" rev-parse HEAD)
[ "$actual_commit" = "$expected_commit" ] || {
	echo "Expected driver commit $expected_commit, got $actual_commit" >&2
	exit 2
}

for patch in "$script_dir"/0*.patch; do
	if git -C "$driver_source" apply --check "$patch" 2>/dev/null; then
		git -C "$driver_source" apply "$patch"
	elif git -C "$driver_source" apply --reverse --check "$patch" 2>/dev/null; then
		: # Already applied.
	else
		echo "Patch neither applies nor appears installed: $patch" >&2
		exit 1
	fi
done

kernel_release=$(make -s -C "$kernel_source" O="$kernel_build" ARCH=arm \
	CROSS_COMPILE="$cross_compile" kernelrelease)

make -C "$kernel_build" M="$driver_source" clean >/dev/null
make -C "$kernel_build" M="$driver_source" \
	-j"${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}" \
	ARCH=arm CROSS_COMPILE="$cross_compile" USER_MODULE_NAME=8188eu modules

module=$(find "$driver_source" -maxdepth 1 -type f -name '8188eu.ko' -print -quit)
[ -n "$module" ] || { echo "Driver build did not produce 8188eu.ko" >&2; exit 1; }

module_dir="$rootfs/lib/modules/$kernel_release/extra"
mkdir -p "$module_dir" "$rootfs/lib/firmware/rtlwifi"
install -m 0644 "$module" "$module_dir/8188eu.ko"
"${cross_compile}strip" --strip-debug "$module_dir/8188eu.ko"
install -m 0644 "$driver_source/rtl8188eufw.bin" \
	"$rootfs/lib/firmware/rtlwifi/rtl8188eufw.bin"

make -C "$kernel_source" O="$kernel_build" ARCH=arm \
	CROSS_COMPILE="$cross_compile" \
	INSTALL_MOD_PATH="$rootfs" INSTALL_MOD_STRIP=1 modules_install

rm -f "$rootfs/lib/modules/$kernel_release/build" \
	"$rootfs/lib/modules/$kernel_release/source"

depmod -b "$rootfs" "$kernel_release"

modinfo -F alias "$module_dir/8188eu.ko" | grep -qi '^usb:v0BDAp0179' || {
	echo "ERROR: module does not alias USB 0bda:0179" >&2
	exit 1
}
test -s "$rootfs/lib/modules/$kernel_release/modules.dep"
echo "Installed 8188eu and kernel modules for $kernel_release"
