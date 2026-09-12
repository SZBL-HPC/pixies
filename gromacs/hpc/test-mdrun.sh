#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s [cpu|gpu]\n' "$(basename "$0")"
}

if (( $# > 1 )); then
    usage >&2
    exit 2
fi

mode="${1:-cpu}"
case "$mode" in
    cpu|gpu) ;;
    *) usage >&2; exit 2 ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-common.sh
source "$script_dir/test-common.sh"

require_runtime
require_mpi
gmx_bin="$(find_gmx)"

run_args=(-nb cpu -pme cpu)
if [[ "$mode" == gpu ]]; then
    if [[ "$(basename "$gmx_bin")" != gmx_mpi ]]; then
        printf 'GPU mode requires the CUDA gmx_mpi binary; found %s.\n' "$gmx_bin" >&2
        exit 1
    fi
    command -v nvidia-smi >/dev/null 2>&1 || {
        printf 'GPU mode requires nvidia-smi.\n' >&2
        exit 1
    }
    nvidia-smi --query-gpu=name --format=csv,noheader
    run_args=(-nb gpu -pme gpu -gpu_id "${GMX_GPU_ID:-0}")
fi

test_dir="$hpc_test_root/mdrun-$mode"
rm -rf "$test_dir"
write_test_system "$test_dir" "HPC GROMACS PLUMED ${mode} test" 10

cd "$test_dir"
"$gmx_bin" grompp -f md.mdp -c conf.gro -p topol.top -o topol.tpr
"$mpi_exec" -n "${MPI_NP:-2}" "$gmx_bin" mdrun \
    -s topol.tpr \
    -deffnm run \
    -plumed plumed.dat \
    -ntomp 1 \
    -pin off \
    -dlb no \
    "${run_args[@]}"
test -s COLVAR

printf 'GROMACS + PLUMED MPI %s test passed: %s\n' "$mode" "$gmx_bin"
