#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=platforms/docker/lib.sh
source "${SCRIPT_DIR}/../../platforms/docker/lib.sh"
