#!/usr/bin/env bash
set -euxo pipefail

: "${PREFIX:?PREFIX is required}"
: "${SRC_DIR:?SRC_DIR is required}"
: "${BUILD_PREFIX:?BUILD_PREFIX is required}"
: "${GROMACS_MPI:?GROMACS_MPI is required}"
: "${GROMACS_VARIANT:?GROMACS_VARIANT is required}"

test "${GROMACS_MPI}" = openmpi
test "${target_platform}" = linux-64

export CC="${PREFIX}/bin/mpicc"
export CXX="${PREFIX}/bin/mpicxx"
export CPPFLAGS="-I${PREFIX}/include ${CPPFLAGS:-}"
export LDFLAGS="-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib -Wl,-rpath-link,${PREFIX}/lib ${LDFLAGS:-}"
export STATIC_LIBS="-Wl,-rpath-link,${PREFIX}/lib ${STATIC_LIBS:-}"

plumed_src="${SRC_DIR}/plumed"
gromacs_src="${SRC_DIR}/gromacs"

cd "${plumed_src}"
./configure \
    --prefix="${PREFIX}" \
    --enable-mpi \
    --enable-rpath \
    --enable-zlib \
    --enable-gsl \
    --enable-fftw \
    --disable-python \
    --disable-pycv \
    --disable-libsearch \
    --disable-static-patch \
    --disable-static-archive
make -C src -j"${CPU_COUNT}" install

cd "${gromacs_src}"
"${PREFIX}/bin/plumed-patch" -e "gromacs-${PKG_VERSION}" -p

gromacs_build="${BUILD_DIR}/gromacs-${GROMACS_VARIANT}"
cmake_args=(
    -S "${gromacs_src}"
    -B "${gromacs_build}"
    -G "${CMAKE_GENERATOR}"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_PREFIX_PATH="${PREFIX}"
    -DCMAKE_INSTALL_PREFIX="${PREFIX}"
    -DCMAKE_INSTALL_LIBDIR=lib
    -DBUILD_SHARED_LIBS=ON
    -DSHARED_LIBS_DEFAULT=ON
    -DGMX_PREFER_STATIC_LIBS=OFF
    -DGMX_BUILD_OWN_FFTW=OFF
    -DGMX_DEFAULT_SUFFIX=OFF
    -DGMX_MPI=ON
    -DGMX_THREAD_MPI=OFF
    -DGMX_USE_PLUMED=ON
    -DGMX_HWLOC=ON
    -DGMX_INSTALL_LEGACY_API=ON
    -DCMAKE_C_COMPILER="${CC}"
    -DCMAKE_CXX_COMPILER="${CXX}"
    -DGMX_BINARY_SUFFIX=_mpi
    -DGMX_LIBS_SUFFIX=_mpi
)

case "${GROMACS_VARIANT}" in
    cuda)
        cuda_target="${BUILD_PREFIX}/targets/x86_64-linux"
        export PATH="${cuda_target}/bin:${cuda_target}/nvvm/bin:${BUILD_PREFIX}/nvvm/bin:${PATH}"
        cmake_args+=(
            -DGMX_GPU=CUDA
            -DCMAKE_CUDA_COMPILER="${BUILD_PREFIX}/bin/nvcc"
            -DCMAKE_CXX_FLAGS="-I${PREFIX}/include"
        )
        ;;
    d)
        cmake_args+=(
            -DGMX_DOUBLE=ON
            -DGMX_GPU=OFF
            -DGMX_BINARY_SUFFIX=_mpi_d
            -DGMX_LIBS_SUFFIX=_mpi_d
        )
        ;;
    ocl)
        cmake_args+=(
            -DGMX_DOUBLE=OFF
            -DGMX_GPU=OpenCL
            -DOpenCL_INCLUDE_DIR="${PREFIX}/include"
            -DOpenCL_LIBRARY="${PREFIX}/lib/libOpenCL.so"
            -DGMX_BINARY_SUFFIX=_mpi_ocl
            -DGMX_LIBS_SUFFIX=_mpi_ocl
        )
        ;;
    *)
        printf 'Unknown GROMACS variant: %s\n' "${GROMACS_VARIANT}" >&2
        exit 2
        ;;
esac

cmake "${cmake_args[@]}"
cmake --build "${gromacs_build}" --parallel "${CPU_COUNT}"
cmake --install "${gromacs_build}"

test -x "${PREFIX}/bin/plumed"
test -x "${PREFIX}/bin/plumed-patch"
case "${GROMACS_VARIANT}" in
    d) test -x "${PREFIX}/bin/gmx_mpi_d" ;;
    ocl) test -x "${PREFIX}/bin/gmx_mpi_ocl" ;;
    cuda) test -x "${PREFIX}/bin/gmx_mpi" ;;
esac
