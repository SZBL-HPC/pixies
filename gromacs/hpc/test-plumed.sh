#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-common.sh
source "$script_dir/test-common.sh"

require_runtime
require_mpi
plumed_version="$(plumed info --version)"
plumed --is-installed
"$mpi_exec" -n 1 plumed --has-mpi

printf 'PLUMED runtime test passed: %s\n' "$plumed_version"
