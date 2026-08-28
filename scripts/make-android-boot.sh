#!/bin/sh
set -eu

usage() {
	echo "Usage: make-android-boot.sh ZIMAGE DTB OUTPUT_BOOT_IMG [RAMDISK]" >&2
}

[ "$#" -eq 3 ] || [ "$#" -eq 4 ] || { usage; exit 2; }
zimage=$1
dtb=$2
output=$3
ramdisk=${4:-}
partition_bytes=$((12600 * 512))

for input in "$zimage" "$dtb" ${ramdisk:+"$ramdisk"}; do
	[ -f "$input" ] || { echo "Missing input: $input" >&2; exit 2; }
	[ ! -b "$input" ] || { echo "Refusing block device: $input" >&2; exit 2; }
done
case "$output" in /|"") echo "Refusing unsafe output: $output" >&2; exit 2;; esac
[ ! -b "$output" ] || { echo "Refusing block-device output: $output" >&2; exit 2; }
command -v mkbootimg >/dev/null || {
	echo "mkbootimg is required inside the VM" >&2
	exit 2
}

output_dir=$(dirname -- "$output")
mkdir -p "$output_dir"
output_dir=$(CDPATH= cd -- "$output_dir" && pwd)
output="$output_dir/$(basename -- "$output")"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/gamestick-boot.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

cat "$zimage" "$dtb" > "$tmp_dir/zImage-dtb"
if [ -z "$ramdisk" ]; then
	printf 'ramdisk.img\n' > "$tmp_dir/ramdisk-stub"
	ramdisk="$tmp_dir/ramdisk-stub"
fi

mkbootimg \
	--header_version 0 \
	--kernel "$tmp_dir/zImage-dtb" \
	--ramdisk "$ramdisk" \
	--base 0x40000000 \
	--kernel_offset 0x00008000 \
	--ramdisk_offset 0x01000000 \
	--second_offset 0x00f00000 \
	--tags_offset 0x00000100 \
	--pagesize 2048 \
	--board h133-p2nor \
	--output "$output"

size=$(stat -c %s "$output")
if [ "$size" -gt "$partition_bytes" ]; then
	rm -f "$output"
	echo "Boot image is $size bytes; partition 4 holds only $partition_bytes" >&2
	exit 1
fi
file "$output"
sha256sum "$output"
echo "Android boot image: $output ($size/$partition_bytes bytes)"
