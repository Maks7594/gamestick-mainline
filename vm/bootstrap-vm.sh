#!/bin/sh
set -eu

[ "$(uname -m)" = x86_64 ] || { echo "This script is for the x86_64 build VM" >&2; exit 2; }
command -v pacman >/dev/null || { echo "Expected the Arch build VM" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo inside the VM" >&2; exit 2; }

pacman -Syy --noconfirm
pacman -S --needed --noconfirm \
	base-devel bc bison flex git curl wget openssl cpio rsync \
	dtc qemu-user-static qemu-user-static-binfmt android-tools e2fsprogs

systemctl restart systemd-binfmt.service
[ -e /proc/sys/fs/binfmt_misc/qemu-arm ] || {
	echo "qemu-arm binfmt did not register" >&2
	exit 1
}
echo "VM build dependencies are ready"
