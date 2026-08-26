#!/usr/bin/env bash

set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SOURCE_DIR="${ROOT_DIR}/percolator"
readonly BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build}"
readonly INSTALL_PREFIX="${CMAKE_INSTALL_PREFIX:-${ROOT_DIR}/release}"
readonly BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
readonly EIGEN_OVERRIDE_DIR="${BUILD_DIR}/_eigen-pixi"
readonly CONVERTER_BUILD_DIR="${CONVERTER_BUILD_DIR:-${BUILD_DIR}/converters}"
readonly CONVERTER_SOURCE_DIR="${CONVERTER_SOURCE_DIR:-${ROOT_DIR}/percolator-converters}"

usage() {
  cat <<'EOF'
Usage: build.sh [TARGET]

Build the project with CMake. TARGET defaults to all.

Targets:
  all         Build percolator and converters
  percolator  Build only the main percolator binaries
  converters  Build only msgf2pin, sqt2pin, and tandem2pin

Options:
  -h, --help  Show this help message

Environment variables:
  BUILD_DIR, CMAKE_INSTALL_PREFIX, CMAKE_BUILD_TYPE
  CONVERTER_BUILD_DIR, CONVERTER_SOURCE_DIR
  XSD_EXECUTABLE, XSD_INCLUDE_DIR, XSD_DIR
EOF
}

if [[ $# -gt 1 ]]; then
  printf 'Error: expected at most one target argument.\n\n' >&2
  usage >&2
  exit 2
fi

target="${1:-all}"
case "${target}" in
  -h|--help)
    usage
    exit 0
    ;;
  all|percolator|converters)
    ;;
  *)
    printf 'Error: unknown target: %s\n\n' "${target}" >&2
    usage >&2
    exit 2
    ;;
esac

readonly PIXI=(pixi run --manifest-path "${ROOT_DIR}/pixi.toml")
readonly DEPENDENCY_PREFIX="$("${PIXI[@]}" printenv CONDA_PREFIX)"

XSD_EXECUTABLE="${XSD_EXECUTABLE:-}"
XSD_INCLUDE_DIR="${XSD_INCLUDE_DIR:-}"
XSD_DIR="${XSD_DIR:-${XSDDIR:-}}"

build_percolator() {
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

  local -a cmake_args=(
    -S "${SOURCE_DIR}"
    -B "${BUILD_DIR}"
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"
    -DCMAKE_PREFIX_PATH="${DEPENDENCY_PREFIX}"
    -DBOOST_ROOT="${DEPENDENCY_PREFIX}"
    -DBoost_ROOT="${DEPENDENCY_PREFIX}"
    -DBoost_USE_STATIC_LIBS=OFF
    -DBoost_NO_SYSTEM_PATHS=ON
    -DFETCHCONTENT_SOURCE_DIR_EIGEN="${EIGEN_OVERRIDE_DIR}"
    -DGOOGLE_TEST=0
    -DNO_TESTS=ON
  )

  "${PIXI[@]}" cmake "${cmake_args[@]}"
  "${PIXI[@]}" cmake --build "${BUILD_DIR}" --parallel
  "${PIXI[@]}" cmake --install "${BUILD_DIR}" --prefix "${INSTALL_PREFIX}"
}

build_converters() {
  if [[ -z "${XSD_DIR}" ]] && command -v brew >/dev/null 2>&1; then
    XSD_DIR="$(brew --prefix xsd 2>/dev/null || true)"
  fi

  if [[ -z "${XSD_EXECUTABLE}" ]]; then
    for xsd_command in xsd xsdcxx; do
      if command -v "${xsd_command}" >/dev/null 2>&1; then
        XSD_EXECUTABLE="$(command -v "${xsd_command}")"
        break
      fi
    done
  fi

  if [[ -z "${XSD_EXECUTABLE}" && -n "${XSD_DIR}" ]]; then
    for xsd_candidate in "${XSD_DIR}/bin/xsd" "${XSD_DIR}/bin/xsdcxx"; do
      if [[ -x "${xsd_candidate}" ]]; then
        XSD_EXECUTABLE="${xsd_candidate}"
        break
      fi
    done
  fi

  if [[ -z "${XSD_INCLUDE_DIR}" && -n "${XSD_DIR}" && -d "${XSD_DIR}/include" ]]; then
    XSD_INCLUDE_DIR="${XSD_DIR}/include"
  fi

  if [[ -z "${XSD_EXECUTABLE}" ]]; then
    printf '%s\n' \
      'CodeSynthesis XSD was not found.' \
      'Install it (macOS: brew install xsd) or set XSD_EXECUTABLE and XSD_INCLUDE_DIR.' >&2
    exit 1
  fi

  if [[ ! -f "${CONVERTER_SOURCE_DIR}/CMakeLists.txt" ]]; then
    printf 'Converter source directory is missing: %s\n' "${CONVERTER_SOURCE_DIR}" >&2
    exit 1
  fi

  local -a converter_cmake_args=(
    -S "${CONVERTER_SOURCE_DIR}"
    -B "${CONVERTER_BUILD_DIR}"
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"
    -DCMAKE_PREFIX_PATH="${DEPENDENCY_PREFIX}"
    -DBOOST_ROOT="${DEPENDENCY_PREFIX}"
    -DBoost_ROOT="${DEPENDENCY_PREFIX}"
    -DBoost_USE_STATIC_LIBS=OFF
    -DBoost_NO_SYSTEM_PATHS=ON
    -DRPCDIR="${DEPENDENCY_PREFIX}"
    -DSERIALIZE=Boost
    -DXML_SUPPORT=ON
    -DXSD_EXECUTABLE="${XSD_EXECUTABLE}"
    -Dpercolator-in-namespace=http://per-colator.com/percolator_in/13
    -Dpercolator-out-namespace=http://per-colator.com/percolator_out/15
    -DmzIdentML-namespace=http://psidev.info/psi/pi/mzIdentML/1.1
    -Dgaml_tandem-namespace=http://www.bioml.com/gaml/
    -Dgaxml_tandem-namespace=http://www.bioml.com/gaml/
    -Dtandem-namespace=http://www.thegpm.org/TANDEM/2011.12.01.1
  )

  if [[ -n "${XSD_INCLUDE_DIR}" ]]; then
    converter_cmake_args+=(-DXSD_INCLUDE_DIR="${XSD_INCLUDE_DIR}")
  fi

  XSDDIR="${XSD_DIR}" \
  XERCESCROOT="${DEPENDENCY_PREFIX}" \
    "${PIXI[@]}" cmake "${converter_cmake_args[@]}"
  "${PIXI[@]}" cmake --build "${CONVERTER_BUILD_DIR}" --parallel \
    --target msgf2pin sqt2pin tandem2pin
  "${PIXI[@]}" cmake --install "${CONVERTER_BUILD_DIR}" --prefix "${INSTALL_PREFIX}"

  for converter_binary in msgf2pin sqt2pin tandem2pin; do
    if [[ ! -x "${INSTALL_PREFIX}/bin/${converter_binary}" ]]; then
      printf 'Converter binary was not installed: %s\n' "${INSTALL_PREFIX}/bin/${converter_binary}" >&2
      exit 1
    fi
  done
}

case "${target}" in
  all)
    build_percolator
    build_converters
    ;;
  percolator)
    build_percolator
    ;;
  converters)
    build_converters
    ;;
esac
