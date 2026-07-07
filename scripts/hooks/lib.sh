#!/usr/bin/env bash
set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034 # Sourced hook scripts consume this shared root.
HOOKS_REPO_ROOT="$(cd "${HOOKS_DIR}/../.." && pwd)"

hook_skip_requested() {
  [[ "${LAEMP_SKIP_HOOKS:-}" == "1" ]]
}

hook_print_skip_and_exit() {
  echo "WARN LAEMP_SKIP_HOOKS=1; skipping ${0##*/}"
  exit 0
}

hook_ok() {
  echo "OK   $*"
}

hook_warn() {
  echo "WARN $*"
}

hook_fail() {
  echo "FAIL $*" >&2
}

hook_parse_execute_flag() {
  case "${1:-}" in
    --execute)
      shift
      ;;
    --dry-run)
      shift
      hook_warn "dry run: would run ${0##*/} $*"
      exit 0
      ;;
    -h|--help)
      hook_usage
      exit 0
      ;;
    *)
      hook_fail "missing --execute"
      hook_usage >&2
      exit 1
      ;;
  esac

  # shellcheck disable=SC2034 # Sourced hook scripts consume this parsed argv.
  HOOK_ARGS=("$@")
}
