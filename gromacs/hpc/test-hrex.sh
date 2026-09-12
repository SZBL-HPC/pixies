#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-common.sh
source "$script_dir/test-common.sh"

require_runtime
require_mpi
gmx_bin="$(find_gmx)"

mdrun_help="$("$gmx_bin" mdrun -h 2>&1)"
if [[ "$mdrun_help" != *"-[no]hrex"* ]]; then
    printf 'The installed GROMACS binary does not provide -hrex: %s\n' "$gmx_bin" >&2
    exit 3
fi

test_dir="$hpc_test_root/hrex"
rm -rf "$test_dir"
mkdir -p "$test_dir/replica0" "$test_dir/replica1"
write_test_system "$test_dir" 'HPC GROMACS PLUMED HREX test' 2 1

for replica in 0 1; do
    cp "$test_dir"/md.mdp "$test_dir"/conf.gro "$test_dir"/topol.top \
        "$test_dir"/plumed.dat "$test_dir/replica${replica}/"
    (
        cd "$test_dir/replica${replica}"
        "$gmx_bin" grompp -f md.mdp -c conf.gro -p topol.top -o topol.tpr
    )
done

cd "$test_dir"
"$mpi_exec" -n 2 "$gmx_bin" mdrun \
    -multidir replica0 replica1 \
    -replex 1 \
    -nsteps 2 \
    -hrex \
    -dlb no \
    -plumed plumed.dat \
    -ntomp 1 \
    -pin off \
    -nb cpu \
    -pme cpu

test -s replica0/COLVAR
test -s replica1/COLVAR
printf 'GROMACS + PLUMED HREX test passed: %s\n' "$gmx_bin"
