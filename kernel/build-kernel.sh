#!/bin/sh
set -eu

usage() {
	cat <<'EOF'
Usage: build-kernel.sh KERNEL_SOURCE OUTPUT_DIR [CROSS_COMPILE]

Build Linux and the Game Stick DTB. KERNEL_SOURCE must be an extracted Linux
6.18.39 tree. OUTPUT_DIR must not be / and must not be a block device.
The default compiler prefix is arm-linux-musleabihf-.

Set INITRAMFS_SOURCE to a cpio archive or directory to embed an initramfs in
the kernel itself. This is required for diagnostic builds on vendor U-Boot
instances that ignore Android boot-image ramdisks.
EOF
}

[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { usage >&2; exit 2; }

kernel_source=$1
output_dir=$2
cross_compile=${3:-arm-linux-musleabihf-}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)

case "$kernel_source" in /|"") echo "Refusing unsafe kernel source: $kernel_source" >&2; exit 2;; esac
case "$output_dir" in /|"") echo "Refusing unsafe output directory: $output_dir" >&2; exit 2;; esac
[ ! -b "$kernel_source" ] && [ ! -b "$output_dir" ] || {
	echo "Refusing to operate on a block device" >&2
	exit 2
}
[ -f "$kernel_source/Makefile" ] || {
	echo "Not a Linux source tree: $kernel_source" >&2
	exit 2
}

kernel_release=$(make -s -C "$kernel_source" kernelversion)
[ "$kernel_release" = "6.18.39" ] || {
	echo "Expected Linux 6.18.39, got $kernel_release" >&2
	exit 2
}
command -v "${cross_compile}gcc" >/dev/null || {
	echo "Missing cross compiler: ${cross_compile}gcc" >&2
	exit 2
}

mkdir -p "$output_dir"
output_dir=$(CDPATH= cd -- "$output_dir" && pwd)

# The fragment was derived from multi_v7_defconfig, but resolving it on an
# all-disabled baseline prevents unrelated platform child symbols from
# selecting OMAP/QCOM/Tegra/etc. back on behind our explicit exclusions.
make -C "$kernel_source" O="$output_dir" ARCH=arm \
	CROSS_COMPILE="$cross_compile" allnoconfig
"$kernel_source/scripts/kconfig/merge_config.sh" -m -O "$output_dir" \
	"$output_dir/.config" "$script_dir/game-stick.fragment"
if [ -n "${INITRAMFS_SOURCE:-}" ]; then
	[ -r "$INITRAMFS_SOURCE" ] || {
		echo "Missing INITRAMFS_SOURCE: $INITRAMFS_SOURCE" >&2
		exit 2
	}
	"$kernel_source/scripts/config" --file "$output_dir/.config" \
		--set-str INITRAMFS_SOURCE "$INITRAMFS_SOURCE"
else
	"$kernel_source/scripts/config" --file "$output_dir/.config" \
		--set-str INITRAMFS_SOURCE ""
fi
make -C "$kernel_source" O="$output_dir" ARCH=arm \
	CROSS_COMPILE="$cross_compile" olddefconfig

cp "$project_dir/dts/sun8i-t113s-h133-game-stick.dts" \
	"$kernel_source/arch/arm/boot/dts/allwinner/"

jobs=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}
make -C "$kernel_source" O="$output_dir" ARCH=arm \
	CROSS_COMPILE="$cross_compile" -j"$jobs" zImage modules

# A named DTB does not need a permanent upstream Makefile entry when requested
# directly from Kbuild.
make -C "$kernel_source" O="$output_dir" ARCH=arm \
	CROSS_COMPILE="$cross_compile" \
	allwinner/sun8i-t113s-h133-game-stick.dtb

mkdir -p "$output_dir/artifacts"
cp "$output_dir/arch/arm/boot/zImage" "$output_dir/artifacts/zImage"
cp "$output_dir/arch/arm/boot/dts/allwinner/sun8i-t113s-h133-game-stick.dtb" \
	"$output_dir/artifacts/"
cat "$output_dir/artifacts/zImage" \
	"$output_dir/artifacts/sun8i-t113s-h133-game-stick.dtb" \
	> "$output_dir/artifacts/zImage-dtb"
cp "$output_dir/.config" "$output_dir/artifacts/kernel.config"
make -s -C "$kernel_source" O="$output_dir" ARCH=arm \
	CROSS_COMPILE="$cross_compile" kernelrelease \
	> "$output_dir/artifacts/kernel.release"

rm -f "$output_dir/artifacts/SHA256SUMS"
(
	cd "$output_dir/artifacts"
	sha256sum zImage sun8i-t113s-h133-game-stick.dtb zImage-dtb \
		kernel.config kernel.release
) > "$output_dir/artifacts/SHA256SUMS"
echo "Kernel artifacts: $output_dir/artifacts"
