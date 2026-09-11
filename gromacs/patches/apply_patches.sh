#!/bin/sh
set -eu

patch_dir=$1
source_dir=$2

test -d "$patch_dir" || exit 0

for patch_file in "$patch_dir"/*.patch; do
    test -f "$patch_file" || continue

    patch_output="$(patch --dry-run --forward --batch \
        -d "$source_dir" -p1 < "$patch_file" 2>&1)"
    case "$patch_output" in
        *"Ignoring previously applied"*)
            continue
            ;;
        *"Hunk FAILED"*|*"malformed patch"*)
            printf '%s\n' "$patch_output" >&2
            exit 1
            ;;
    esac

    patch --forward --batch -d "$source_dir" -p1 < "$patch_file"
done
