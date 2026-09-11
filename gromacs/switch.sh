#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
local_root="$project_root/local"
bin_dir="$local_root/bin"
mode="gromacs"
selection=""
list_all=0

usage() {
    printf 'Usage:\n'
    printf '  %s gromacs [VERSION|NUMBER]\n' "$(basename "$0")"
    printf '  %s plumed [ENVIRONMENT|NUMBER]\n' "$(basename "$0")"
    printf '  %s [VERSION|NUMBER]\n' "$(basename "$0")"
    printf '\n'
    printf 'Use --list after a software name, or without a name to list both.\n'
}

print_items() {
    local noun="$1"
    local current="$2"
    shift 2
    local -a items=()
    local item
    for item in "$@"; do
        [[ -n "$item" ]] && items+=("$item")
    done
    local i marker

    printf 'Available %s:\n' "$noun"
    if (( ${#items[@]} == 0 )); then
        printf ' (none)\n'
        return
    fi
    for ((i = 0; i < ${#items[@]}; i++)); do
        marker=' '
        [[ "${items[$i]}" == "$current" ]] && marker='*'
        printf ' %s[%d] %s\n' "$marker" "$((i + 1))" "${items[$i]}"
    done
}

choose_item() {
    local noun="$1"
    local current="$2"
    local requested="$3"
    shift 3
    local -a items=("$@")
    local index item found

    if [[ -z "$requested" ]]; then
        print_items "$noun" "$current" "${items[@]}"
        printf 'Select a %s number (or enter q to quit): ' "$noun"
        IFS= read -r requested || exit 1
        case "$requested" in
            q|Q) exit 0 ;;
        esac
    fi

    if [[ "$requested" =~ ^[0-9]+$ ]]; then
        index=$((10#$requested))
        if (( index < 1 || index > ${#items[@]} )); then
            printf 'Invalid selection: %s\n' "$requested" >&2
            exit 2
        fi
        selected_item="${items[$((index - 1))]}"
        return
    fi

    found=0
    for item in "${items[@]}"; do
        if [[ "$item" == "$requested" ]]; then
            found=1
            break
        fi
    done
    if (( found == 0 )); then
        printf '%s is not installed: %s\n' "$noun" "$requested" >&2
        print_items "$noun" "$current" "${items[@]}" >&2
        exit 2
    fi
    selected_item="$requested"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

case "${1:-}" in
    gromacs|gmx)
        mode="gromacs"
        selection="${2:-}"
        ;;
    plumed)
        mode="plumed"
        selection="${2:-}"
        ;;
    --list|list)
        list_all=1
        ;;
    *)
        selection="${1:-}"
        ;;
esac

shopt -s nullglob
gromacs_versions=()
for gmxrc in "$local_root"/gromacs/*/bin/GMXRC; do
    [[ -f "$gmxrc" && -f "${gmxrc}.bash" ]] || continue
    version="${gmxrc#$local_root/gromacs/}"
    version="${version%/bin/GMXRC}"
    [[ "$version" != */* ]] && gromacs_versions+=("$version")
done
if (( ${#gromacs_versions[@]} > 0 )); then
    sorted_versions="$(printf '%s\n' "${gromacs_versions[@]}" | LC_ALL=C sort -t. -k1,1n -k2,2n -k3,3n)"
    gromacs_versions=()
    while IFS= read -r version; do
        [[ -n "$version" ]] && gromacs_versions+=("$version")
    done <<< "$sorted_versions"
fi

plumed_environments=()
for plumed_patch in "$local_root"/plumed/*/bin/plumed-patch; do
    [[ -f "$plumed_patch" ]] || continue
    environment="${plumed_patch#$local_root/plumed/}"
    environment="${environment%/bin/plumed-patch}"
    [[ "$environment" != */* ]] && plumed_environments+=("$environment")
done
if (( ${#plumed_environments[@]} > 0 )); then
    sorted_environments="$(printf '%s\n' "${plumed_environments[@]}" | LC_ALL=C sort)"
    plumed_environments=()
    while IFS= read -r environment; do
        [[ -n "$environment" ]] && plumed_environments+=("$environment")
    done <<< "$sorted_environments"
fi

current_gromacs=""
if [[ -L "$bin_dir/GMXRC" ]]; then
    current_target="$(readlink "$bin_dir/GMXRC")"
    case "$current_target" in
        ../gromacs/*/bin/GMXRC)
            current_gromacs="${current_target#../gromacs/}"
            current_gromacs="${current_gromacs%/bin/GMXRC}"
            ;;
    esac
fi

current_plumed=""
if [[ -L "$bin_dir/plumed-patch" ]]; then
    current_target="$(readlink "$bin_dir/plumed-patch")"
    case "$current_target" in
        ../plumed/*/bin/plumed-patch)
            current_plumed="${current_target#../plumed/}"
            current_plumed="${current_plumed%/bin/plumed-patch}"
            ;;
    esac
fi

if (( list_all )); then
    print_items 'GROMACS versions' "$current_gromacs" "${gromacs_versions[@]-}"
    print_items 'PLUMED environments' "$current_plumed" "${plumed_environments[@]-}"
    exit 0
fi

case "$mode" in
    gromacs)
        if [[ "$selection" == "--help" || "$selection" == "-h" ]]; then
            usage
            print_items 'GROMACS versions' "$current_gromacs" "${gromacs_versions[@]-}"
            exit 0
        fi
        if [[ "$selection" == "--list" || "$selection" == "list" ]]; then
            print_items 'GROMACS versions' "$current_gromacs" "${gromacs_versions[@]-}"
            exit 0
        fi
        if (( ${#gromacs_versions[@]} == 0 )); then
            printf 'No installed GROMACS versions were found under %s.\n' "$local_root/gromacs" >&2
            exit 1
        fi
        choose_item 'GROMACS version' "$current_gromacs" "$selection" "${gromacs_versions[@]}"
        version="$selected_item"
        prefix="$local_root/gromacs/$version"
        for script in GMXRC GMXRC.bash; do
            if [[ ! -f "$prefix/bin/$script" ]]; then
                printf 'Missing %s; build and install GROMACS %s first.\n' "$prefix/bin/$script" "$version" >&2
                exit 1
            fi
        done
        mkdir -p "$bin_dir"
        ln -sfn "../gromacs/$version/bin/GMXRC" "$bin_dir/GMXRC"
        ln -sfn "../gromacs/$version/bin/GMXRC.bash" "$bin_dir/GMXRC.bash"
        printf '  %s -> %s\n' "$bin_dir/GMXRC" "../gromacs/$version/bin/GMXRC"
        printf '  %s -> %s\n' "$bin_dir/GMXRC.bash" "../gromacs/$version/bin/GMXRC.bash"
        ;;
    plumed)
        if [[ "$selection" == "--help" || "$selection" == "-h" ]]; then
            usage
            print_items 'PLUMED environments' "$current_plumed" "${plumed_environments[@]-}"
            exit 0
        fi
        if [[ "$selection" == "--list" || "$selection" == "list" ]]; then
            print_items 'PLUMED environments' "$current_plumed" "${plumed_environments[@]-}"
            exit 0
        fi
        if (( ${#plumed_environments[@]} == 0 )); then
            printf 'No installed PLUMED environments were found under %s.\n' "$local_root/plumed" >&2
            exit 1
        fi
        choose_item 'PLUMED environment' "$current_plumed" "$selection" "${plumed_environments[@]}"
        environment="$selected_item"
        prefix="$local_root/plumed/$environment"
        for tool in plumed plumed-config plumed-patch; do
            if [[ ! -f "$prefix/bin/$tool" ]]; then
                printf 'Missing %s; build PLUMED for environment %s first.\n' "$prefix/bin/$tool" "$environment" >&2
                exit 1
            fi
        done
        mkdir -p "$bin_dir"
        for tool in plumed plumed-config plumed-patch; do
            ln -sfn "../plumed/$environment/bin/$tool" "$bin_dir/$tool"
            printf '  %s -> %s\n' "$bin_dir/$tool" "../plumed/$environment/bin/$tool"
        done
        ;;
esac
