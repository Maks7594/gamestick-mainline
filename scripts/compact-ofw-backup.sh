#!/bin/sh
set -eu

usage() {
	cat <<'EOF' >&2
Usage: sudo compact-ofw-backup.sh SOURCE_DISK OUTPUT_IMG

Copy the vendor boot area and partitions 1-6 byte-for-byte, then create fresh
empty 128 MiB ext4 rootfs_data and UDISK partitions in a compact regular image.
SOURCE_DISK must be the expected removable OFW disk. The script never writes to
SOURCE_DISK and refuses the disk containing /.
EOF
}

[ "$#" -eq 2 ] || { usage; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo" >&2; exit 2; }
source_disk=$(readlink -f -- "$1")
output=$2

[ -b "$source_disk" ] || { echo "Source is not a block device: $source_disk" >&2; exit 2; }
[ "$(lsblk -dnro TYPE "$source_disk")" = disk ] || { echo "Source is not a whole disk" >&2; exit 2; }
[ "$(lsblk -dnro RM "$source_disk")" = 1 ] || { echo "Source is not marked removable" >&2; exit 2; }

root_source=$(findmnt -n -o SOURCE /)
root_parent=$(lsblk -no PKNAME "$root_source" 2>/dev/null || true)
[ -z "$root_parent" ] || [ "$source_disk" != "/dev/$root_parent" ] || {
	echo "Refusing the disk containing /: $source_disk" >&2
	exit 2
}

for node in $(lsblk -lnpo PATH "$source_disk"); do
	if findmnt -rn -S "$node" >/dev/null 2>&1; then
		echo "Refusing mounted source member: $node" >&2
		exit 2
	fi
done

case "$output" in /|"") echo "Refusing unsafe output: $output" >&2; exit 2;; esac
[ ! -b "$output" ] || { echo "Output cannot be a block device" >&2; exit 2; }
[ ! -e "$output" ] || { echo "Output exists; refusing overwrite: $output" >&2; exit 2; }

table=$(sfdisk -d "$source_disk")
check_partition() {
	printf '%s\n' "$table" | grep -q "start= *$2, size= *$3.*name=\"$1\"" || {
		echo "Unexpected $1 partition geometry" >&2
		exit 2
	}
}
check_partition boot-resource 41464 2048
check_partition env 43512 504
check_partition env-redund 44016 504
check_partition boot 44520 12600
check_partition rootfs 57120 404800
check_partition private 461920 2016
printf '%s\n' "$table" | grep -q 'name="rootfs_data"' || { echo "Missing rootfs_data" >&2; exit 2; }
printf '%s\n' "$table" | grep -q 'name="UDISK"' || { echo "Missing UDISK" >&2; exit 2; }

disk_uuid=$(printf '%s\n' "$table" | sed -n 's/^label-id: //p')
partition_uuid() {
	printf '%s\n' "$table" | sed -n "/name=\"$1\"/s/.*uuid=\([^,]*\).*/\1/p"
}
p1_uuid=$(partition_uuid boot-resource)
p2_uuid=$(partition_uuid env)
p3_uuid=$(partition_uuid env-redund)
p4_uuid=$(partition_uuid boot)
p5_uuid=$(partition_uuid rootfs)
p6_uuid=$(partition_uuid private)
p7_uuid=$(partition_uuid rootfs_data)
p8_uuid=$(partition_uuid UDISK)
for uuid in "$disk_uuid" "$p1_uuid" "$p2_uuid" "$p3_uuid" "$p4_uuid" \
	"$p5_uuid" "$p6_uuid" "$p7_uuid" "$p8_uuid"; do
	[ -n "$uuid" ] || { echo "A required GPT UUID is missing" >&2; exit 2; }
done

sector_size=512
p7_start=463936
p7_size=262144
p8_start=$((p7_start + p7_size))
p8_size=262144
total_sectors=$((p8_start + p8_size + 4))
total_bytes=$((total_sectors * sector_size))
p7_offset=$((p7_start * sector_size))
p8_offset=$((p8_start * sector_size))
fs_blocks=$((p7_size * sector_size / 4096))

mkdir -p "$(dirname -- "$output")"
head -c "$p7_offset" "$source_disk" > "$output"
truncate -s "$total_bytes" "$output"

sfdisk --force "$output" <<EOF
label: gpt
label-id: $disk_uuid
unit: sectors
first-lba: 4
table-length: 8
sector-size: 512

start=41464, size=2048, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=$p1_uuid, name="boot-resource"
start=43512, size=504, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=$p2_uuid, name="env", attrs="GUID:62,63"
start=44016, size=504, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=$p3_uuid, name="env-redund", attrs="GUID:62,63"
start=44520, size=12600, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=$p4_uuid, name="boot", attrs="GUID:62,63"
start=57120, size=404800, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=$p5_uuid, name="rootfs", attrs="GUID:62,63"
start=461920, size=2016, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=$p6_uuid, name="private", attrs="GUID:62,63"
start=$p7_start, size=$p7_size, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=$p7_uuid, name="rootfs_data", attrs="GUID:62,63"
start=$p8_start, size=$p8_size, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=$p8_uuid, name="UDISK", attrs="GUID:62,63"
EOF

mke2fs -q -t ext4 -b 4096 -m 0 -L rootfs_data -O '^64bit' \
	-E "offset=$p7_offset" "$output" "$fs_blocks"
mke2fs -q -t ext4 -b 4096 -m 0 -L UDISK -O '^64bit' \
	-E "offset=$p8_offset" "$output" "$fs_blocks"

# Primary GPT metadata occupies sectors 0-3. Everything after it through p6
# must remain byte-identical to the source.
cmp -i 2048:2048 -n $(((p7_start - 4) * sector_size)) "$source_disk" "$output"
sfdisk -d "$output" > "$output.sfdisk"
sha256sum "$output" > "$output.sha256"

echo "Compact OFW recovery image: $output"
echo "p7 rootfs_data: empty 128 MiB ext4"
echo "p8 UDISK: empty 128 MiB ext4"
echo "Source disk was read only; no block device was written."
