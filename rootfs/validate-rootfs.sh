#!/bin/sh
set -eu

[ "$#" -eq 1 ] || { echo "Usage: validate-rootfs.sh ROOTFS" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo so protected credentials can be validated" >&2; exit 2; }
root=$1
case "$root" in /|"") echo "Refusing unsafe root: $root" >&2; exit 2;; esac
[ -d "$root/etc" ] || { echo "Not a root filesystem: $root" >&2; exit 2; }
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "$project_dir/VERSION"

fail() { echo "ERROR: $*" >&2; exit 1; }
need_file() { [ -s "$root$1" ] || fail "missing $1"; }
need_exec() { [ -x "$root$1" ] || fail "not executable: $1"; }

need_exec /bin/busybox
need_exec /sbin/openrc
need_exec /usr/sbin/dropbear
need_exec /sbin/wpa_supplicant
need_exec /usr/local/sbin/gamestick-networkd
need_exec /usr/local/sbin/gamestick-dropbeard
need_exec /usr/local/libexec/gamestick/wifi-backend-wpa_supplicant
need_file /etc/wpa_supplicant/wpa_supplicant.conf
need_file /etc/apk/repositories
need_file /etc/fstab
need_file /etc/hostname
need_file /etc/banner
need_file /etc/dropbear/dropbear_ed25519_host_key
need_file /etc/dropbear/dropbear_rsa_host_key

[ "$(stat -c %a "$root/etc/wpa_supplicant/wpa_supplicant.conf")" = 600 ] || fail "Wi-Fi config mode is not 0600"
[ "$(stat -c %a "$root/etc/dropbear/dropbear_ed25519_host_key")" = 600 ] || fail "Ed25519 host key mode is not 0600"
[ "$(stat -c %a "$root/etc/dropbear/dropbear_rsa_host_key")" = 600 ] || fail "RSA host key mode is not 0600"
[ -L "$root/etc/runlevels/default/gamestick-network" ] || fail "network service is not enabled"
[ -L "$root/etc/runlevels/default/gamestick-dropbear" ] || fail "Dropbear service is not enabled"
grep -q '^LABEL=rootfs.*ext4' "$root/etc/fstab" || fail "labeled ext4 root is absent from fstab"
grep -q "$ALPINE_BRANCH/main" "$root/etc/apk/repositories" 2>/dev/null || \
	grep -q '/v3\.24/main' "$root/etc/apk/repositories" || fail "Alpine main repository is wrong"
grep -q '^network={' "$root/etc/wpa_supplicant/wpa_supplicant.conf" || fail "no Wi-Fi network block"
grep -q '^8188eu$' "$root/etc/modules" || fail "8188eu is not requested at boot"
grep -q -- '-b /etc/banner' "$root/usr/local/sbin/gamestick-dropbeard" || fail "SSH banner is not enabled"

for forbidden in bash python python3 gcc git tmux Xorg weston; do
	if find "$root/bin" "$root/sbin" "$root/usr/bin" "$root/usr/sbin" \
		-maxdepth 1 -name "$forbidden" -print -quit 2>/dev/null | grep -q .; then
		fail "forbidden milestone-1 program installed: $forbidden"
	fi
done

if find "$root/lib/modules" -type f -name '8188eu.ko*' -print -quit 2>/dev/null | grep -q .; then
	release=$(find "$root/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -1)
	need_file "/lib/modules/$release/modules.dep"
	need_file /lib/firmware/rtlwifi/rtl8188eufw.bin
fi

echo "Root filesystem checks passed"
