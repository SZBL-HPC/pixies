#!/bin/sh
set -eu

patch_dir=$1
source_dir=$2

test -d "$patch_dir" || exit 0

patch_output_has_error() {
    printf '%s\n' "$1" | grep -Eiq \
        'Hunk .*FAILED|malformed patch|Only garbage was found|cannot find file to patch|No file to patch|patch: \*\*\*\*'
}

patch_output_is_safe_skip() {
    printf '%s\n' "$1" | grep -Eiq \
        'Reversed \(or previously applied\) patch detected|previously applied|hunk ignored'
}

remove_safe_rejects() {
    while IFS= read -r line; do
        case "$line" in
            *saving\ rejects\ to\ *)
                reject_file=${line#*saving rejects to }
                reject_file=${reject_file#file }
                reject_file=${reject_file#\'}
                reject_file=${reject_file%\'}
                case "$reject_file" in
                    ""|-) ;;
                    /*) rm -f "$reject_file" ;;
                    *) rm -f "$source_dir/$reject_file" ;;
                esac
                ;;
        esac
    done
}

for patch_file in "$patch_dir"/*.patch; do
    test -f "$patch_file" || continue

    dry_run_status=0
    dry_run_output="$(patch --dry-run --forward --batch \
        -d "$source_dir" -p1 < "$patch_file" 2>&1)" || dry_run_status=$?
    if [ "$dry_run_status" -ne 0 ] && {
        patch_output_has_error "$dry_run_output" ||
        ! patch_output_is_safe_skip "$dry_run_output"
    }; then
        printf '%s\n' "$dry_run_output" >&2
        exit 1
    fi

    patch_status=0
    patch_output="$(patch --forward --batch \
        -d "$source_dir" -p1 < "$patch_file" 2>&1)" || patch_status=$?
    if [ "$patch_status" -ne 0 ] && {
        patch_output_has_error "$patch_output" ||
        ! patch_output_is_safe_skip "$patch_output"
    }; then
        printf '%s\n' "$patch_output" >&2
        exit 1
    fi
    if [ "$patch_status" -ne 0 ]; then
        remove_safe_rejects <<EOF
$patch_output
EOF
        printf 'Patch already applied or partially applied: %s\n' "$patch_file"
    else
        printf '%s\n' "$patch_output"
    fi
done
