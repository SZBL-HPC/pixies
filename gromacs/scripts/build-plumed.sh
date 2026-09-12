#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s PLUMED_PREFIX PIXI_ENVIRONMENT [SOURCE_DIR]\n' "$(basename "$0")"
}

if (( $# < 2 || $# > 3 )); then
    usage >&2
    exit 2
fi

plumed_prefix=$1
environment=$2
source_dir=${3:-$PWD}

configure_args=(
    "--prefix=$plumed_prefix"
    --enable-rpath
    --enable-zlib
    --enable-gsl
    --enable-fftw
)

if [[ -n "${PLUMEDCONF:-}" ]]; then
    read -r -a plumedconf_args <<< "$PLUMEDCONF"
    configure_args+=("${plumedconf_args[@]}")
fi

make_args=()
if [[ "$environment" == "mpi5" || "$environment" == "mpis" ]]; then
    configure_args+=(--enable-mpi)
    export CC=mpicc
    export CXX=mpicxx

    if [[ "$(uname -s)" == "Darwin" ]]; then
        sdkroot="${PLUMED_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
        cxx_include="$sdkroot/usr/include/c++/v1"
        mpi_cc="/Library/Developer/CommandLineTools/usr/bin/clang"
        mpi_cxx="/Library/Developer/CommandLineTools/usr/bin/clang++"

        if [[ ! -d "$sdkroot" || ! -d "$cxx_include" ]]; then
            printf 'Apple SDK or libc++ headers not found: %s\n' "$sdkroot" >&2
            exit 1
        fi

        export MPICH_CC="$mpi_cc"
        export MPICH_CXX="$mpi_cxx"
        export OMPI_CC="$mpi_cc"
        export OMPI_CXX="$mpi_cxx"
        export CFLAGS="${CFLAGS:-} -isysroot $sdkroot"
        export CXXFLAGS="${CXXFLAGS:-} -stdlib=libc++ -isysroot $sdkroot -isystem $cxx_include"
        export LDFLAGS="${LDFLAGS:-} -isysroot $sdkroot -L$CONDA_PREFIX/lib -Wl,-rpath,$CONDA_PREFIX/lib"
        make_args+=("LDSHARED=mpicxx -isysroot $sdkroot -dynamiclib -Wl,-headerpad_max_install_names")
    fi
fi

cd "$source_dir"
./configure "${configure_args[@]}"
if (( ${#make_args[@]} > 0 )); then
    make -C src install LDFLAGS="${LDFLAGS:-}" "${make_args[@]}"
else
    make -C src install LDFLAGS="${LDFLAGS:-}"
fi
