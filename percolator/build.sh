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
readonly CONVERTER_BUILD_DIR="${CONVERTER_BUILD_DIR:-${BUILD_DIR}/converters}"
readonly CONVERTER_SOURCE_DIR="${BUILD_DIR}/_converter-source"
readonly CONVERTER_SOURCE_REVISION="${CONVERTER_SOURCE_REVISION:-44ad230175c4cbe9d9d7ecb64202e9fd26181103}"

XSD_EXECUTABLE="${XSD_EXECUTABLE:-}"
XSD_INCLUDE_DIR="${XSD_INCLUDE_DIR:-}"
XSD_DIR="${XSD_DIR:-${XSDDIR:-}}"

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

if ! git -C "${SOURCE_DIR}" cat-file -e "${CONVERTER_SOURCE_REVISION}^{commit}" 2>/dev/null; then
  git -C "${SOURCE_DIR}" fetch --no-tags origin "${CONVERTER_SOURCE_REVISION}"
fi

if [[ -d "${CONVERTER_SOURCE_DIR}" ]]; then
  "${PIXI[@]}" cmake -E remove_directory "${CONVERTER_SOURCE_DIR}"
fi
"${PIXI[@]}" cmake -E make_directory "${CONVERTER_SOURCE_DIR}"

# The current upstream tree removed the converters. Overlay their last complete
# source tree onto a temporary copy so the checkout itself remains unchanged.
git -C "${SOURCE_DIR}" archive --format=tar HEAD \
  | tar -xf - -C "${CONVERTER_SOURCE_DIR}"
git -C "${SOURCE_DIR}" archive --format=tar "${CONVERTER_SOURCE_REVISION}" \
  cmake/FindXsd.cmake \
  cmake/FindXercesC.cmake \
  src/converters \
  src/Enzyme.cpp \
  src/Enzyme.h \
  src/Globals.cpp \
  src/Globals.h.cmake \
  src/Logger.cpp \
  src/Logger.h \
  src/MassHandler.cpp \
  src/MassHandler.h \
  src/MyException.cpp \
  src/MyException.h \
  src/Option.cpp \
  src/Option.h \
  src/parser.cxx \
  src/parser.hxx \
  src/serializer.cxx \
  src/serializer.hxx \
  src/TmpDir.cpp \
  src/TmpDir.h \
  src/xml \
  | tar -xf - -C "${CONVERTER_SOURCE_DIR}"

# The historical MSToolkit code uses std::random_shuffle, removed in C++17.
compat_source="${CONVERTER_SOURCE_DIR}/src/converters/MSToolkit/crawutils.cpp"
compat_source_tmp="${compat_source}.tmp"
"${PIXI[@]}" gawk '
  BEGIN { replaced = 0 }
  /^[[:space:]]*#include <algorithm>[[:space:]]*$/ {
    print
    print "#include <random>"
    next
  }
  /std::random_shuffle\( v\.begin\(\), v\.end\(\) \);/ {
    print "          std::shuffle(v.begin(), v.end(), std::mt19937(std::random_device{}()));"
    replaced = 1
    next
  }
  { print }
  END { if (!replaced) exit 1 }
' "${compat_source}" > "${compat_source_tmp}"
mv "${compat_source_tmp}" "${compat_source}"

converter_cmake_args=(
  -S "${CONVERTER_SOURCE_DIR}/src/converters"
  -B "${CONVERTER_BUILD_DIR}"
  -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
  -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"
  -DCMAKE_PREFIX_PATH="${DEPENDENCY_PREFIX}"
  -DBOOST_ROOT="${DEPENDENCY_PREFIX}"
  -DBoost_ROOT="${DEPENDENCY_PREFIX}"
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
