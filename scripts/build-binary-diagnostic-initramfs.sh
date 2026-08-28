#!/bin/sh
set -eu

[ "$#" -eq 2 ] || {
	echo "Usage: build-binary-diagnostic-initramfs.sh CROSS_CC OUTPUT_CPIO" >&2
	exit 2
}
cc=$1
output=$2
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
stage=$(mktemp -d "${TMPDIR:-/tmp}/gamestick-binary-init.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM

case "$output" in /|"") echo "Refusing unsafe output" >&2; exit 2;; esac
[ ! -b "$output" ] || { echo "Refusing block-device output" >&2; exit 2; }
command -v "$cc" >/dev/null || { echo "Missing compiler: $cc" >&2; exit 2; }

mkdir -p "$stage/proc" "$stage/sys" "$stage/dev" "$stage/newroot"
"$cc" -static -no-pie -s -Os -fno-ident -march=armv7-a -mfloat-abi=hard \
	-mfpu=vfpv3-d16 "$script_dir/diagnostic-init.c" -o "$stage/init"

output_dir=$(dirname -- "$output")
mkdir -p "$output_dir"
output_dir=$(CDPATH= cd -- "$output_dir" && pwd)
output="$output_dir/$(basename -- "$output")"
(cd "$stage" && find . -print | cpio -o -H newc --owner=0:0) > "$output"
file "$stage/init"
stat -c '%n %s bytes' "$output"
