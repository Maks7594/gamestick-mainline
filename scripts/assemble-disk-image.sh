#!/bin/sh
set -eu

usage() {
	cat <<'EOF' >&2
Usage: sudo assemble-disk-image.sh REFERENCE_IMG BOOT_IMG ROOTFS_DIR OUTPUT_IMG SIZE_MIB

Create a new regular disk image. The raw bootloader area and partitions 1-3
come byte-for-byte from REFERENCE_IMG, partition 4 receives BOOT_IMG, and one
read-write ext4 partition 5 fills the remainder. This never accepts a block
device and never flashes media.
EOF
}

[ "$#" -eq 5 ] || { usage; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo "Run this inside the VM with sudo" >&2; exit 2; }
reference=$1
boot_image=$2
rootfs=$3
output=$4
size_mib=$5

for input in "$reference" "$boot_image"; do
	[ -f "$input" ] || { echo "Missing regular input file: $input" >&2; exit 2; }
	[ ! -b "$input" ] || { echo "Refusing block device: $input" >&2; exit 2; }
done
[ -d "$rootfs/etc" ] || { echo "Not a root filesystem: $rootfs" >&2; exit 2; }
case "$output" in /|"") echo "Refusing unsafe output: $output" >&2; exit 2;; esac
[ ! -b "$output" ] || { echo "Refusing block-device output: $output" >&2; exit 2; }
[ ! -e "$output" ] || { echo "Output already exists; refusing overwrite: $output" >&2; exit 2; }
case "$size_mib" in *[!0-9]*|"") echo "SIZE_MIB must be an integer" >&2; exit 2;; esac
[ "$size_mib" -ge 512 ] || { echo "SIZE_MIB must be at least 512" >&2; exit 2; }

command -v sfdisk >/dev/null || { echo "sfdisk is required" >&2; exit 2; }
command -v mke2fs >/dev/null || { echo "mke2fs is required" >&2; exit 2; }

boot_start=44520
boot_sectors=12600
root_start=57120
sector_size=512
boot_offset=$((boot_start * sector_size))
root_offset=$((root_start * sector_size))
boot_limit=$((boot_sectors * sector_size))
total_bytes=$((size_mib * 1024 * 1024))
total_sectors=$((total_bytes / sector_size))
root_sectors=$((total_sectors - root_start - 4))
[ "$root_sectors" -gt 0 ] || { echo "Output is too small" >&2; exit 2; }

# Confirm that the reference really is this board's known GPT before copying
# any bytes from it.
table=$(sfdisk -d "$reference")
printf '%s\n' "$table" | grep -q 'start= *41464, size= *2048.*name="boot-resource"' || {
	echo "Reference boot-resource partition does not match" >&2; exit 2;
}
printf '%s\n' "$table" | grep -q 'start= *43512, size= *504.*name="env"' || {
	echo "Reference env partition does not match" >&2; exit 2;
}
printf '%s\n' "$table" | grep -q 'start= *44016, size= *504.*name="env-redund"' || {
	echo "Reference env-redund partition does not match" >&2; exit 2;
}
printf '%s\n' "$table" | grep -q 'start= *44520, size= *12600.*name="boot"' || {
	echo "Reference boot partition does not match" >&2; exit 2;
}

disk_uuid=$(printf '%s\n' "$table" | sed -n 's/^label-id: //p')
partition_uuid() {
	printf '%s\n' "$table" | sed -n "/name=\"$1\"/s/.*uuid=\([^,]*\).*/\1/p"
}
boot_resource_uuid=$(partition_uuid boot-resource)
env_uuid=$(partition_uuid env)
env_redund_uuid=$(partition_uuid env-redund)
boot_uuid=$(partition_uuid boot)
root_uuid=$(partition_uuid rootfs)
for uuid in "$disk_uuid" "$boot_resource_uuid" "$env_uuid" \
	"$env_redund_uuid" "$boot_uuid" "$root_uuid"; do
	[ -n "$uuid" ] || { echo "Reference is missing a required GPT UUID" >&2; exit 2; }
done

boot_size=$(stat -c %s "$boot_image")
[ "$boot_size" -le "$boot_limit" ] || {
	echo "Boot image exceeds the $boot_limit-byte partition" >&2
	exit 2
}

mkdir -p "$(dirname -- "$output")"
head -c "$boot_offset" "$reference" > "$output"
cat "$boot_image" >> "$output"
truncate -s "$root_offset" "$output"
truncate -s "$total_bytes" "$output"

# Recreate only the GPT metadata. Raw bootloader bytes outside the GPT sectors
# remain those copied from the reference image.
sfdisk --force "$output" <<EOF
label: gpt
label-id: $disk_uuid
unit: sectors
first-lba: 4
table-length: 8
sector-size: 512

start=41464, size=2048, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=$boot_resource_uuid, name="boot-resource"
start=43512, size=504, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=$env_uuid, name="env", attrs="GUID:62,63"
start=44016, size=504, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=$env_redund_uuid, name="env-redund", attrs="GUID:62,63"
start=44520, size=12600, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=$boot_uuid, name="boot", attrs="GUID:62,63"
start=57120, size=$root_sectors, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, uuid=$root_uuid, name="rootfs"
EOF

root_blocks=$((root_sectors * sector_size / 4096))
mke2fs -q -t ext4 -b 4096 -m 0 -L rootfs -O '^64bit' \
	-E "offset=$root_offset" -d "$rootfs" "$output" "$root_blocks"

sfdisk -d "$output" > "$output.sfdisk"
sha256sum "$output" > "$output.sha256"
echo "Created regular image only: $output"
echo "Partition 5: $root_sectors sectors, ext4, read-write"
echo "No block device was opened and nothing was flashed."
