#!/usr/bin/env bash

mpi_module_dirs=(
    /lustre/software/Modules/base_software
    /lustre/software/Modules/compilers
)

if ! type module >/dev/null 2>&1; then
    modulecmd_path="$(command -v modulecmd 2>/dev/null || true)"
    if [[ -n "$modulecmd_path" ]]; then
        module() { eval "$("$modulecmd_path" bash "$@")"; }
    elif [[ -r /usr/share/Modules/init/bash ]]; then
        source /usr/share/Modules/init/bash || true
    fi
fi

if ! type module >/dev/null 2>&1; then
    printf '%s\n' "Qbics MPI: module system is unavailable; skipping cluster MPI activation." >&2
    if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
        exit 0
    fi
    return 0
fi

if ! module use "${mpi_module_dirs[@]}" >/dev/null 2>&1; then
    printf '%s\n' "Qbics MPI: cluster module paths are unavailable; skipping MPI activation." >&2
    if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
        exit 0
    fi
    return 0
fi

module unload openmpi/5.0.8-gcc14.2.0 2>/dev/null || true
module unload ucx/1.19.0 2>/dev/null || true
module load gcc/14.2.0
module load openmpi/5.0.8-gcc14.2.0
module list || true

mpi_root="${QBICS_MPI_ROOT:-/lustre/software/openmpi/5.0.8-gcc14.2.0}"
if [[ -d "$mpi_root/local/bin" && -d "$mpi_root/local/lib" ]]; then
    export PATH="$mpi_root/local/bin:/lustre/software/ucx/1.19.0/bin:${PATH}"
    export LD_LIBRARY_PATH="$mpi_root/local/lib:/lustre/software/ucx/1.19.0/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export PKG_CONFIG_PATH="$mpi_root/local/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
fi

export OMPI_CC="${OMPI_CC:-/lustre/software/gcc/gcc-14.2.0/bin/gcc}"
export OMPI_CXX="${OMPI_CXX:-/lustre/software/gcc/gcc-14.2.0/bin/g++}"
export OMPI_FC="${OMPI_FC:-/lustre/software/gcc/gcc-14.2.0/bin/gfortran}"
