#!/usr/bin/env bash

hpc_test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
hpc_test_root="${HPC_TEST_ROOT:-${hpc_test_dir}/.test}"

require_runtime() {
    : "${CONDA_PREFIX:?Run this test from pixi shell.}"

    command -v plumed >/dev/null 2>&1 || {
        printf 'PLUMED was not found in PATH. Run pixi shell first.\n' >&2
        return 1
    }
    export LD_LIBRARY_PATH="${CONDA_PREFIX}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    if [[ -z "${PLUMED_KERNEL:-}" ]]; then
        PLUMED_KERNEL="${CONDA_PREFIX}/lib/libplumedKernel.so"
        export PLUMED_KERNEL
    fi
    if [[ ! -r "$PLUMED_KERNEL" ]]; then
        printf 'PLUMED kernel was not found: %s\n' "$PLUMED_KERNEL" >&2
        return 1
    fi
    if [[ "${GMX_FORCE_GPU_AWARE_MPI:-}" != "1" ]]; then
        printf 'GMX_FORCE_GPU_AWARE_MPI=1 is required; run pixi shell first.\n' >&2
        return 1
    fi
}

find_gmx() {
    local candidate
    for candidate in gmx_mpi gmx_mpi_d gmx_mpi_ocl; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done
    printf 'No supported gmx_mpi binary was found in PATH.\n' >&2
    return 1
}

require_mpi() {
    mpi_exec="${MPIEXEC:-mpiexec}"
    if ! command -v "$mpi_exec" >/dev/null 2>&1; then
        printf 'MPI launcher was not found: %s\n' "$mpi_exec" >&2
        return 1
    fi
}

write_test_system() {
    local directory="$1"
    local title="$2"
    local nsteps="$3"
    local thermostat="${4:-0}"

    mkdir -p "$directory"
    {
        printf '%s\n' \
            'integrator = md' \
            'dt = 0.001' \
            "nsteps = ${nsteps}" \
            'nstlist = 1' \
            'cutoff-scheme = Verlet' \
            'coulombtype = Cut-off' \
            'rcoulomb = 0.5' \
            'vdwtype = Cut-off' \
            'rvdw = 0.5' \
            'pbc = xyz' \
            'constraints = none' \
            'nstenergy = 1' \
            'nstlog = 1' \
            'nstxout-compressed = 0'
        if (( thermostat )); then
            printf '%s\n' \
                'tcoupl = V-rescale' \
                'tc-grps = System' \
                'tau-t = 0.1' \
                'ref-t = 300' \
                'gen-vel = yes' \
                'gen-temp = 300' \
                'gen-seed = -1'
        fi
    } > "$directory/md.mdp"

    {
        printf '%s\n' "$title" '2'
        printf '%5d%-5s%5s%5d%8.3f%8.3f%8.3f\n' \
            1 TEST D1 1 0.0 0.0 0.0 \
            1 TEST D2 2 0.2 0.0 0.0
        printf '%10.5f%10.5f%10.5f\n' 2.0 2.0 2.0
    } > "$directory/conf.gro"

    printf '%s\n' \
        '; Minimal two-particle topology for the HPC runtime test.' \
        '[ defaults ]' \
        '1 2 yes 0.5 0.8333' \
        '' \
        '[ atomtypes ]' \
        'DUM 1.000 0.000 A 0.100 0.100' \
        '' \
        '[ moleculetype ]' \
        'HPC_TEST 3' \
        '' \
        '[ atoms ]' \
        '1 DUM 1 TEST D1 1 0.0 1.0' \
        '2 DUM 1 TEST D2 1 0.0 1.0' \
        '' \
        '[ bonds ]' \
        '1 2 1 0.200 1000' \
        '' \
        '[ system ]' \
        "$title" \
        '' \
        '[ molecules ]' \
        'HPC_TEST 1' \
        > "$directory/topol.top"

    printf '%s\n' \
        'd: DISTANCE ATOMS=1,2' \
        'PRINT ARG=d FILE=COLVAR STRIDE=1' \
        > "$directory/plumed.dat"
}
