#!/usr/bin/env bash

set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SOURCE_DIR="${ROOT_DIR}/percolator"
readonly BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build}"
readonly INSTALL_PREFIX="${CMAKE_INSTALL_PREFIX:-${ROOT_DIR}/release}"
readonly BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
readonly PIXI=(pixi run --manifest-path "${ROOT_DIR}/pixi.toml")
readonly DEPENDENCY_PREFIX="$("${PIXI[@]}" printenv CONDA_PREFIX)"
readonly EIGEN_OVERRIDE_DIR="${BUILD_DIR}/_eigen-pixi"

if [[ ! -d "${DEPENDENCY_PREFIX}/include/eigen3" ]]; then
  printf 'Pixi Eigen headers not found: %s\n' "${DEPENDENCY_PREFIX}/include/eigen3" >&2
  exit 1
fi

if [[ -d "${EIGEN_OVERRIDE_DIR}" ]]; then
  "${PIXI[@]}" cmake -E remove_directory "${EIGEN_OVERRIDE_DIR}"
fi

"${PIXI[@]}" cmake -E make_directory "${EIGEN_OVERRIDE_DIR}"
"${PIXI[@]}" cmake -E copy_directory \
  "${DEPENDENCY_PREFIX}/include/eigen3" \
  "${EIGEN_OVERRIDE_DIR}"
"${PIXI[@]}" cmake -E copy_if_different \
  "${ROOT_DIR}/cmake/eigen-pixi-override/CMakeLists.txt" \
  "${EIGEN_OVERRIDE_DIR}/CMakeLists.txt"

cmake_args=(
  -S "${SOURCE_DIR}"
  -B "${BUILD_DIR}"
  -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
  -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"
  -DCMAKE_PREFIX_PATH="${DEPENDENCY_PREFIX}"
  -DBOOST_ROOT="${DEPENDENCY_PREFIX}"
  -DBoost_ROOT="${DEPENDENCY_PREFIX}"
  -DBoost_NO_SYSTEM_PATHS=ON
  -DFETCHCONTENT_SOURCE_DIR_EIGEN="${EIGEN_OVERRIDE_DIR}"
  -DGOOGLE_TEST=0
  -DNO_TESTS=ON
)

"${PIXI[@]}" cmake "${cmake_args[@]}"
"${PIXI[@]}" cmake --build "${BUILD_DIR}" --parallel
"${PIXI[@]}" cmake --install "${BUILD_DIR}" --prefix "${INSTALL_PREFIX}"
