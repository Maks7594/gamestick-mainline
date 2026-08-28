#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)

find "$project_dir" -type f -name '*.sh' -print | while IFS= read -r script; do
	sh -n "$script" || exit 1
done

if grep -R -n -E 'psk="[^r]' \
	"$project_dir" --exclude='*.example' --exclude='README.md' \
	--exclude='TROUBLESHOOTING.md' --exclude='validate-source-tree.sh'; then
	echo "Possible embedded credential found" >&2
	exit 1
fi

if grep -R -n -E '(^|[[:space:]])dd[[:space:]].*of=/dev/' "$project_dir"; then
	echo "A block-device dd command is forbidden" >&2
	exit 1
fi

echo "Source tree checks passed"
