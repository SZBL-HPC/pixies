#!/usr/bin/env bash
# activate_mpi.sh

mpi_module_dirs=(
    /lustre/software/Modules/base_software
    /lustre/software/Modules/compilers
)

unset -f module 2>/dev/null || true
if [[ -x /usr/bin/modulecmd ]]; then
    module() { eval "$(/usr/bin/modulecmd bash "$@")"; }
elif [[ -r /usr/share/Modules/init/bash ]]; then
    source /usr/share/Modules/init/bash || true
    export -n -f module 2>/dev/null || true
fi

module_system_available=1
if ! type module >/dev/null 2>&1; then
    module_system_available=0
else
    for module_dir in "${mpi_module_dirs[@]}"; do
        if [[ ! -d "$module_dir" ]]; then
            module_system_available=0
            break
        fi
    done
fi

if [[ "$module_system_available" == "1" ]]; then
    if ! module use "${mpi_module_dirs[@]}" >/dev/null 2>&1; then
        module_system_available=0
    fi
fi

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    exit "$((1 - module_system_available))"
fi

if [[ "$module_system_available" != "1" ]]; then
    echo "Qbics MPI: Slurm module environment is unavailable; skipping cluster MPI module activation." >&2
    if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
        return 0
    fi
    exit 0
fi

module unload openmpi/openmpi-4.1.1-slurm || true
module unload openmpi/4.1.8 || true
module unload openmpi/4.1.8-gcc12.2.0 || true
module unload ucx/1.19.0 || true
module unload openmpi/5.0.8-gcc14.2.0 || true

mpi_module="openmpi/5.0.8-gcc14.2.0"
module load gcc/14.2.0

module load "$mpi_module"
module list || true

mpi_root="${QBICS_MPI_ROOT:-/lustre/software/openmpi/5.0.8-gcc14.2.0}"

if [[ -n "$mpi_root" && -d "$mpi_root/local/bin" && -d "$mpi_root/local/lib" ]]; then
    echo "Qbics MPI: prepending direct OpenMPI paths from $mpi_root." >&2
    export PATH="$mpi_root/local/bin:/lustre/software/ucx/1.19.0/bin:$PATH"
    export LD_LIBRARY_PATH="$mpi_root/local/lib:/lustre/software/ucx/1.19.0/lib:${LD_LIBRARY_PATH:-}"
    export PKG_CONFIG_PATH="$mpi_root/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
fi

copy_host_bfd_libs() {
    if [[ "${QBICS_COPY_HOST_LIBBFD:-1}" == "0" ]]; then
        return 0
    fi
    if [[ "$(uname -s 2>/dev/null)" != "Linux" ]]; then
        return 0
    fi

    local env_root="${CONDA_PREFIX:-${PREFIX:-}}"
    if [[ -z "$env_root" || ! -d "$env_root/lib" ]]; then
        return 0
    fi

    local names=(
        libbfd-2.27-27.base.el7.so
        libbfd.so
        libbfd.a
        libiberty.a
    )
    local name src candidate copied=0
    for name in "${names[@]}"; do
        src=""
        for candidate in "/lib64/$name" "/usr/lib64/$name"; do
            if [[ -r "$candidate" ]]; then
                src="$candidate"
                break
            fi
        done
        if [[ -z "$src" ]]; then
            if [[ "$name" == "libbfd-2.27-27.base.el7.so" ]]; then
                echo "Qbics MPI: host $name not found; OpenMPI UCX may need it at runtime." >&2
            fi
            continue
        fi

        local dst="$env_root/local/lib/$name"
        if [[ -e "$dst" ]]; then
            continue
        fi
        if cp -L "$src" "$dst" 2>/dev/null; then
            copied=1
        else
            echo "Qbics MPI: could not copy $name into $env_root/lib; check env permissions." >&2
        fi
    done
    if [[ "$copied" == "1" ]]; then
        echo "Qbics MPI: copied host libbfd/libiberty files into $env_root/lib for OpenMPI UCX."
    fi
}

copy_host_bfd_libs

export OMPI_CC="${OMPI_CC:-/lustre/software/gcc/gcc-14.2.0/bin/gcc}"
export OMPI_CXX="${OMPI_CXX:-/lustre/software/gcc/gcc-14.2.0/bin/g++}"
export OMPI_FC="${OMPI_FC:-/lustre/software/gcc/gcc-14.2.0/bin/gfortran}"
