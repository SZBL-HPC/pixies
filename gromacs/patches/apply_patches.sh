#!/bin/sh
set -eu

patch_dir=$1
source_dir=$2

test -d "$patch_dir" || exit 0

for patch_file in "$patch_dir"/*.patch; do
    test -f "$patch_file" || continue

    if ! patch_output="$(patch --dry-run --forward --batch \
        -d "$source_dir" -p1 < "$patch_file" 2>&1)"; then
        printf '%s\n' "$patch_output" >&2
        exit 1
    fi

    patch --forward --batch -d "$source_dir" -p1 < "$patch_file"
done
