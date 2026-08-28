#!/bin/sh
set -eu

usage() {
	cat <<'EOF'
Usage: sudo build-rootfs.sh OUTPUT_ROOT WIFI_CONF [AUTHORIZED_KEYS] [ROOT_PASSWORD_HASH_FILE]

Build an Alpine armv7 root directory. WIFI_CONF is a real wpa_supplicant
configuration kept outside this repository. At least one of AUTHORIZED_KEYS or
ROOT_PASSWORD_HASH_FILE must be supplied. The password file must contain one
crypt(3) hash, never a plaintext password.
EOF
}

[ "$#" -ge 2 ] && [ "$#" -le 4 ] || { usage >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo "Run this inside the VM with sudo" >&2; exit 2; }

output_root=$1
wifi_conf=$2
authorized_keys=${3:-}
password_hash_file=${4:-}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "$project_dir/VERSION"

case "$output_root" in /|"") echo "Refusing unsafe output root: $output_root" >&2; exit 2;; esac
[ ! -b "$output_root" ] || { echo "Refusing block device: $output_root" >&2; exit 2; }
[ -f "$wifi_conf" ] || { echo "Missing Wi-Fi configuration: $wifi_conf" >&2; exit 2; }
grep -q '^network={' "$wifi_conf" || { echo "Wi-Fi config has no network block" >&2; exit 2; }
if grep -q 'replace-me' "$wifi_conf"; then
	echo "Refusing placeholder Wi-Fi credentials" >&2
	exit 2
fi
if [ -z "$authorized_keys" ] && [ -z "$password_hash_file" ]; then
	echo "Recovery image needs an SSH public key or root password hash" >&2
	exit 2
fi
[ -z "$authorized_keys" ] || [ -s "$authorized_keys" ] || { echo "Empty authorized_keys" >&2; exit 2; }
[ -z "$password_hash_file" ] || [ -s "$password_hash_file" ] || { echo "Empty password hash file" >&2; exit 2; }

command -v qemu-arm-static >/dev/null || {
	echo "qemu-arm-static is required in the VM" >&2
	exit 2
}
if [ ! -e /proc/sys/fs/binfmt_misc/qemu-arm ]; then
	echo "ARM binfmt is not active; install/enable qemu-user-static-binfmt in the VM" >&2
	exit 2
fi

archive="alpine-minirootfs-$ALPINE_VERSION-armv7.tar.gz"
url="https://dl-cdn.alpinelinux.org/alpine/$ALPINE_BRANCH/releases/armv7/$archive"
cache_dir=${CACHE_DIR:-$project_dir/cache}
mkdir -p "$cache_dir"
if [ ! -f "$cache_dir/$archive" ]; then
	curl -fL --retry 5 -o "$cache_dir/$archive" "$url"
fi
curl -fL --retry 5 -o "$cache_dir/$archive.sha256" "$url.sha256"
(cd "$cache_dir" && sha256sum -c "$archive.sha256")

if [ -e "$output_root" ]; then
	[ -d "$output_root" ] || { echo "Output exists and is not a directory" >&2; exit 2; }
	[ -z "$(find "$output_root" -mindepth 1 -maxdepth 1 -print -quit)" ] || {
		echo "Output root must be empty: $output_root" >&2
		exit 2
	}
else
	mkdir -p "$output_root"
fi
output_root=$(CDPATH= cd -- "$output_root" && pwd)

tar -xpf "$cache_dir/$archive" -C "$output_root"
cp /usr/bin/qemu-arm-static "$output_root/usr/bin/qemu-arm-static"
cp /etc/resolv.conf "$output_root/etc/resolv.conf"

cat > "$output_root/etc/apk/repositories" <<EOF
https://dl-cdn.alpinelinux.org/alpine/$ALPINE_BRANCH/main
https://dl-cdn.alpinelinux.org/alpine/$ALPINE_BRANCH/community
EOF

chroot "$output_root" /bin/sh -eu <<'EOF'
export PATH=/sbin:/bin:/usr/sbin:/usr/bin
apk update
apk add --no-cache openrc dropbear wpa_supplicant iw kmod ca-certificates
update-ca-certificates
install -d -m 0700 /etc/dropbear
dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null
dropbearkey -t rsa -s 2048 -f /etc/dropbear/dropbear_rsa_host_key >/dev/null
chmod 0600 /etc/dropbear/dropbear_*_host_key
rc-update add devfs sysinit
rc-update add dmesg sysinit
rc-update add hwclock boot 2>/dev/null || true
rc-update add hwdrivers sysinit
rc-update add modules boot
rc-update add sysctl boot
rc-update add hostname boot
rc-update add bootmisc boot
rc-update add localmount boot
EOF

cp -a "$script_dir/files/." "$output_root/"
install -d -m 0700 "$output_root/root/.ssh"
if [ -n "$authorized_keys" ]; then
	install -m 0600 "$authorized_keys" "$output_root/root/.ssh/authorized_keys"
fi
if [ -n "$password_hash_file" ]; then
	hash=$(sed -n '1p' "$password_hash_file")
	case "$hash" in
		\$*) ;;
		*) echo "Root password must be supplied as a crypt hash" >&2; exit 2;;
	esac
	printf 'root:%s\n' "$hash" > "$output_root/tmp/root-password"
	chmod 0600 "$output_root/tmp/root-password"
	chroot "$output_root" /bin/sh -eu -c 'export PATH=/sbin:/bin:/usr/sbin:/usr/bin; chpasswd -e < /tmp/root-password; rm -f /tmp/root-password'
fi

install -d -m 0700 "$output_root/etc/wpa_supplicant"
install -m 0600 "$wifi_conf" "$output_root/etc/wpa_supplicant/wpa_supplicant.conf"
printf '%s\n' gamestick > "$output_root/etc/hostname"

cat > "$output_root/etc/inittab" <<'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
ttyS0::respawn:/sbin/getty -L 115200 ttyS0 vt100
tty1::respawn:/sbin/getty 38400 tty1
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
EOF

chmod 0755 \
	"$output_root/etc/init.d/gamestick-network" \
	"$output_root/etc/init.d/gamestick-dropbear" \
	"$output_root/usr/local/sbin/gamestick-networkd" \
	"$output_root/usr/local/sbin/gamestick-dropbeard" \
	"$output_root/usr/local/libexec/gamestick/wifi-backend-wpa_supplicant"
chmod 0600 \
	"$output_root/etc/gamestick/network.conf" \
	"$output_root/etc/gamestick/dropbear.conf" \
	"$output_root/etc/wpa_supplicant/wpa_supplicant.conf"

ln -snf /etc/init.d/gamestick-network \
	"$output_root/etc/runlevels/default/gamestick-network"
ln -snf /etc/init.d/gamestick-dropbear \
	"$output_root/etc/runlevels/default/gamestick-dropbear"

rm -f "$output_root/usr/bin/qemu-arm-static"
rm -f "$output_root/etc/resolv.conf"
rm -rf "$output_root/var/cache/apk/"* \
	"$output_root/usr/share/man" \
	"$output_root/usr/share/doc" \
	"$output_root/usr/share/info" \
	"$output_root/usr/share/locale"
mkdir -p "$output_root/var/log" "$output_root/run"
chmod 0755 "$output_root/var/log" "$output_root/run"

echo "Alpine armv7 root directory: $output_root"
