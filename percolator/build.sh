#!/usr/bin/env bash

set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SOURCE_DIR="${ROOT_DIR}/percolator"
readonly BUILD_DIR="${ROOT_DIR}/build"
readonly INSTALL_PREFIX="${ROOT_DIR}/release"
readonly BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
readonly PIXI=(pixi run --manifest-path "${ROOT_DIR}/pixi.toml")
readonly DEPENDENCY_PREFIX="$("${PIXI[@]}" printenv CONDA_PREFIX)"

cmake_args=(
  -S "${SOURCE_DIR}"
  -B "${BUILD_DIR}"
  -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
  -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"
  -DCMAKE_PREFIX_PATH="${DEPENDENCY_PREFIX}"
  -DBOOST_ROOT="${DEPENDENCY_PREFIX}"
  -DBoost_ROOT="${DEPENDENCY_PREFIX}"
  -DBoost_NO_SYSTEM_PATHS=ON
  -DGOOGLE_TEST=0
  -DNO_TESTS=ON
)

"${PIXI[@]}" cmake "${cmake_args[@]}"
"${PIXI[@]}" cmake --build "${BUILD_DIR}" --parallel
"${PIXI[@]}" cmake --install "${BUILD_DIR}" --prefix "${INSTALL_PREFIX}"
