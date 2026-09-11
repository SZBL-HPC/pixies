#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="$project_root/local/bin"
selection="${1:-}"

shopt -s nullglob
versions=()
for gmxrc in "$project_root"/local/*/bin/GMXRC; do
    [[ -f "$gmxrc" && -f "${gmxrc}.bash" ]] || continue
    version="${gmxrc#$project_root/local/}"
    version="${version%/bin/GMXRC}"
    [[ "$version" == */* ]] || versions+=("$version")
done

if (( ${#versions[@]} == 0 )); then
    case "$selection" in
        --help|-h)
            printf 'Usage: %s [VERSION|NUMBER]\n' "$(basename "$0")"
            printf 'With no argument, choose an installed version interactively.\n'
            exit 0
            ;;
        --list|list)
            printf 'No installed GROMACS versions were found under %s/local/.\n' "$project_root"
            exit 0
            ;;
    esac
    printf 'No installed GROMACS versions were found under %s/local/.\n' "$project_root" >&2
    exit 1
fi

sorted_versions="$(printf '%s\n' "${versions[@]}" | LC_ALL=C sort -t. -k1,1n -k2,2n)"
versions=()
while IFS= read -r version; do
    [[ -n "$version" ]] && versions+=("$version")
done <<< "$sorted_versions"

current_version=""
if [[ -L "$bin_dir/GMXRC" ]]; then
    current_target="$(readlink "$bin_dir/GMXRC")"
    current_target="${current_target#$project_root/local/}"
    current_version="${current_target#../}"
    current_version="${current_version%/bin/GMXRC}"
fi

print_versions() {
    printf 'Available GROMACS versions:\n'
    local i marker
    for ((i = 0; i < ${#versions[@]}; i++)); do
        marker=' '
        [[ "${versions[$i]}" == "$current_version" ]] && marker='*'
        printf ' %s[%d] %s\n' "$marker" "$((i + 1))" "${versions[$i]}"
    done
}

case "$selection" in
    --help|-h)
        printf 'Usage: %s [VERSION|NUMBER]\n' "$(basename "$0")"
        printf 'With no argument, choose an installed version interactively.\n\n'
        print_versions
        exit 0
        ;;
    --list|list)
        print_versions
        exit 0
        ;;
esac

if [[ -z "$selection" ]]; then
    print_versions
    printf 'Select a version number (or enter q to quit): '
    IFS= read -r selection || exit 1
    case "$selection" in
        q|Q) exit 0 ;;
    esac
fi

if [[ "$selection" =~ ^[0-9]+$ ]]; then
    index=$((10#$selection))
    if (( index < 1 || index > ${#versions[@]} )); then
        printf 'Invalid selection: %s\n' "$selection" >&2
        exit 2
    fi
    version="${versions[$((index - 1))]}"
else
    version="$selection"
    found=0
    for candidate in "${versions[@]}"; do
        [[ "$candidate" == "$version" ]] && found=1
    done
    if (( found == 0 )); then
        printf 'GROMACS version is not installed: %s\n' "$version" >&2
        print_versions >&2
        exit 2
    fi
fi

prefix="$project_root/local/$version"
for script in GMXRC GMXRC.bash; do
    if [[ ! -f "$prefix/bin/$script" ]]; then
        printf 'Missing %s; build and install GROMACS %s first.\n' "$prefix/bin/$script" "$version" >&2
        exit 1
    fi
done

mkdir -p "$bin_dir"
ln -sfn "../$version/bin/GMXRC" "$bin_dir/GMXRC"
ln -sfn "../$version/bin/GMXRC.bash" "$bin_dir/GMXRC.bash"

printf '  %s -> %s\n' "$bin_dir/GMXRC" "../$version/bin/GMXRC"
printf '  %s -> %s\n' "$bin_dir/GMXRC.bash" "../$version/bin/GMXRC.bash"
