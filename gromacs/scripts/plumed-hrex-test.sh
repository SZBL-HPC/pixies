#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s [GROMACS_VERSION] [PIXI_ENVIRONMENT]\n' "$(basename "$0")"
}

if (( $# > 2 )); then
    usage >&2
    exit 2
fi

version="${1:-2023.5}"
environment="${2:-${PIXI_ENVIRONMENT_NAME:-mpi5}}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"

case "$environment" in
    default)
        gmx_suffix=""
        ;;
    mpi5)
        gmx_suffix="_mpi"
        ;;
    mpis)
        if [[ "$(uname -s)" == "Darwin" ]]; then
            gmx_suffix="_ompi"
        else
            gmx_suffix="_mpi"
        fi
        ;;
    *)
        printf 'Unsupported Pixi environment: %s\n' "$environment" >&2
        exit 2
        ;;
esac

gmx_bin="$project_root/local/gromacs/$version/bin/gmx$gmx_suffix"
plumed_prefix="$project_root/local/plumed/$environment"
pixi_env_prefix="$project_root/.pixi/envs/$environment"
mpiexec_bin="$pixi_env_prefix/bin/mpiexec"
test_dir="$project_root/.pixi/plumed-hrex/$environment/$version"

if [[ ! -x "$gmx_bin" ]]; then
    printf 'GROMACS binary not found or not executable: %s\n' "$gmx_bin" >&2
    exit 1
fi

if [[ ! -x "$mpiexec_bin" ]]; then
    printf 'MPI launcher not found or not executable: %s\n' "$mpiexec_bin" >&2
    exit 1
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
    plumed_kernel="$plumed_prefix/lib/libplumedKernel.dylib"
    export FI_PROVIDER="${FI_PROVIDER:-tcp}"
    export DYLD_LIBRARY_PATH="$pixi_env_prefix/lib:$plumed_prefix/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
else
    plumed_kernel="$plumed_prefix/lib/libplumedKernel.so"
    export LD_LIBRARY_PATH="$pixi_env_prefix/lib:$plumed_prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

if [[ ! -f "$plumed_kernel" ]]; then
    printf 'PLUMED kernel not found: %s\n' "$plumed_kernel" >&2
    exit 1
fi

export PLUMED_KERNEL="$plumed_kernel"

mdrun_help="$("$gmx_bin" mdrun -h 2>&1)"
if [[ "$mdrun_help" != *"-[no]hrex"* ]]; then
    printf 'GROMACS %s does not provide -hrex in mdrun; skipping HREX test.\n' "$version" >&2
    exit 3
fi

nrep=2
rm -rf "$test_dir"
mkdir -p "$test_dir"
for replica in 0 1; do
    mkdir -p "$test_dir/replica${replica}"
done

printf '%s\n' \
    'integrator = md' \
    'dt = 0.001' \
    'nsteps = 2' \
    'nstlist = 1' \
    'cutoff-scheme = Verlet' \
    'coulombtype = Cut-off' \
    'rcoulomb = 0.5' \
    'vdwtype = Cut-off' \
    'rvdw = 0.5' \
    'pbc = xyz' \
    'constraints = none' \
    'tcoupl = V-rescale' \
    'tc-grps = System' \
    'tau-t = 0.1' \
    'ref-t = 300' \
    'gen-vel = yes' \
    'gen-temp = 300' \
    'gen-seed = -1' \
    'nstenergy = 1' \
    'nstlog = 1' \
    'nstxout-compressed = 0' \
    > "$test_dir/md.mdp"

printf '%s\n' \
    'PLUMED GROMACS HREX smoke test' \
    '2' \
    > "$test_dir/conf.gro"
printf '%5d%-5s%5s%5d%8.3f%8.3f%8.3f\n' \
    1 TEST D1 1 0.0 0.0 0.0 \
    1 TEST D2 2 0.2 0.0 0.0 \
    >> "$test_dir/conf.gro"
printf '%10.5f%10.5f%10.5f\n' 2.0 2.0 2.0 >> "$test_dir/conf.gro"

printf '%s\n' \
    '; Minimal two-particle topology for the PLUMED HREX smoke test.' \
    '[ defaults ]' \
    '1 2 yes 0.5 0.8333' \
    '' \
    '[ atomtypes ]' \
    'DUM 1.000 0.000 A 0.100 0.100' \
    '' \
    '[ moleculetype ]' \
    'PLUMEDTEST 3' \
    '' \
    '[ atoms ]' \
    '1 DUM 1 TEST D1 1 0.0 1.0' \
    '2 DUM 1 TEST D2 1 0.0 1.0' \
    '' \
    '[ bonds ]' \
    '1 2 1 0.200 1000' \
    '' \
    '[ system ]' \
    'PLUMED GROMACS HREX smoke test' \
    '' \
    '[ molecules ]' \
    'PLUMEDTEST 1' \
    > "$test_dir/topol.top"

printf '%s\n' \
    'd: DISTANCE ATOMS=1,2' \
    'PRINT ARG=d FILE=COLVAR STRIDE=1' \
    > "$test_dir/plumed.dat"

cd "$test_dir"
for replica in 0 1; do
    cp md.mdp conf.gro topol.top plumed.dat "replica${replica}/"
    (
        cd "replica${replica}"
        "$gmx_bin" grompp \
            -f md.mdp \
            -c conf.gro \
            -p topol.top \
            -o topol.tpr
    )
done

"$mpiexec_bin" -n "$nrep" "$gmx_bin" mdrun \
    -multidir replica0 replica1 \
    -replex 1 \
    -nsteps 2 \
    -hrex \
    -dlb no \
    -plumed plumed.dat \
    -ntomp 1 \
    -pin off

for replica in 0 1; do
    test -s "replica${replica}/COLVAR"
done

printf 'PLUMED GROMACS HREX smoke test passed: %s (%s, %d replicas)\n' \
    "$version" "$environment" "$nrep"
