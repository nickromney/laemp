#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=platforms/slicervm/lib.sh
source "${SCRIPT_DIR}/../../platforms/slicervm/lib.sh"
