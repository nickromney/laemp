#!/usr/bin/env bash
# Run the proven fresh-VM Lima baseline for laemp.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

exec "${SCRIPT_DIR}/run-matrix.sh" \
  --php 8.4 \
  --web nginx \
  --moodle 5022 \
  "$@"
