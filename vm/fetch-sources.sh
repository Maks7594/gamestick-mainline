#!/bin/sh
set -eu

[ "$#" -eq 1 ] || { echo "Usage: fetch-sources.sh WORK_DIR" >&2; exit 2; }
work_dir=$1
case "$work_dir" in /|"") echo "Refusing unsafe work directory" >&2; exit 2;; esac
[ ! -b "$work_dir" ] || { echo "Refusing block device" >&2; exit 2; }
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "$project_dir/VERSION"

mkdir -p "$work_dir/src"
cd "$work_dir/src"
archive="linux-$KERNEL_VERSION.tar.xz"
if [ ! -f "$archive" ]; then
	curl -fL --retry 5 -o "$archive" \
		"https://cdn.kernel.org/pub/linux/kernel/v6.x/$archive"
fi
[ -d "linux-$KERNEL_VERSION" ] || tar -xf "$archive"

if [ ! -d rtl8188eu/.git ]; then
	git clone https://github.com/benetti-engineering/rtl8188eu.git
fi
git -C rtl8188eu fetch --force origin "$RTL8188EU_COMMIT"
git -C rtl8188eu checkout --detach "$RTL8188EU_COMMIT"

sha256sum "$archive"
git -C rtl8188eu rev-parse HEAD
