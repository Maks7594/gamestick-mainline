#!/bin/sh
set -eu

usage() {
	echo "Usage: build-diagnostic-initramfs.sh STATIC_BUSYBOX OUTPUT_INITRAMFS" >&2
}

[ "$#" -eq 2 ] || { usage; exit 2; }
busybox=$1
output=$2

[ -f "$busybox" ] || { echo "Missing BusyBox: $busybox" >&2; exit 2; }
[ ! -b "$busybox" ] || { echo "Refusing block device BusyBox input" >&2; exit 2; }
case "$output" in /|"") echo "Refusing unsafe output: $output" >&2; exit 2;; esac
[ ! -b "$output" ] || { echo "Refusing block-device output" >&2; exit 2; }

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
stage=$(mktemp -d "${TMPDIR:-/tmp}/gamestick-initramfs.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM

install -d -m 0755 "$stage/bin" "$stage/proc" "$stage/sys" "$stage/dev" "$stage/newroot"
install -m 0755 "$busybox" "$stage/bin/busybox"
for applet in mount mkdir sleep sync switch_root; do
	ln -s busybox "$stage/bin/$applet"
done
install -m 0755 "$script_dir/initramfs/init" "$stage/init"

output_dir=$(dirname -- "$output")
mkdir -p "$output_dir"
output_dir=$(CDPATH= cd -- "$output_dir" && pwd)
output="$output_dir/$(basename -- "$output")"
case "$output" in
*.gz)
	( cd "$stage" && find . -print | cpio -o -H newc | gzip -9 ) > "$output"
	;;
*)
	( cd "$stage" && find . -print | cpio -o -H newc ) > "$output"
	;;
esac
printf 'Diagnostic initramfs: %s\n' "$output"
stat -c '%n %s bytes' "$output"
