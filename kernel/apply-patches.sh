#!/bin/sh
set -eu

usage() {
	cat <<'USAGE'
Usage: apply-patches.sh KERNEL_SOURCE

Apply this project's patches to an extracted Linux 6.18.39 tree, in order.

Safe to re-run: a patch that is already applied is detected and skipped, so
this does not corrupt a tree that has been prepared before.
USAGE
}

[ "$#" -eq 1 ] || { usage >&2; exit 2; }
kernel_source=$1
case "$kernel_source" in /|"") echo "Refusing unsafe kernel source: $kernel_source" >&2; exit 2;; esac
[ ! -b "$kernel_source" ] || { echo "Refusing block device" >&2; exit 2; }
[ -f "$kernel_source/Makefile" ] || {
	echo "Not a Linux source tree: $kernel_source" >&2
	exit 2
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "$project_dir/VERSION"

kernel_release=$(make -s -C "$kernel_source" kernelversion)
[ "$kernel_release" = "$KERNEL_VERSION" ] || {
	echo "Expected Linux $KERNEL_VERSION, got $kernel_release" >&2
	exit 2
}

applied=0
skipped=0
for patch_file in "$script_dir"/patches/*.patch; do
	name=$(basename "$patch_file")
	# A patch that reverses cleanly is already in the tree.
	if patch -d "$kernel_source" -p1 -R --dry-run -s -f < "$patch_file" >/dev/null 2>&1; then
		echo "already applied: $name"
		skipped=$((skipped + 1))
		continue
	fi
	if ! patch -d "$kernel_source" -p1 --dry-run -s -f < "$patch_file" >/dev/null 2>&1; then
		echo "WILL NOT APPLY: $name" >&2
		exit 1
	fi
	patch -d "$kernel_source" -p1 -s -f < "$patch_file"
	echo "applied:         $name"
	applied=$((applied + 1))
done

echo "$applied applied, $skipped already present"
