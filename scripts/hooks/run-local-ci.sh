#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/hooks/lib.sh
source "${SCRIPT_DIR}/lib.sh"

hook_usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Runs the repo local CI gate used by the pre-push hook.
EOF
}

hook_parse_execute_flag "$@"

if [[ "${#HOOK_ARGS[@]}" -gt 0 ]]; then
  hook_fail "unexpected arguments: ${HOOK_ARGS[*]}"
  hook_usage >&2
  exit 1
fi

if hook_skip_requested; then
  hook_fail "skip_requested: verification did not execute"
  exit 1
fi

if [[ "${LAEMP_LOCAL_CI_IN_PROGRESS:-}" == "1" ]]; then
  hook_fail "recursive_gate: verification did not execute"
  exit 1
fi

cd "${HOOKS_REPO_ROOT}"

cat <<'EOF'
laemp pre-push local CI gate

Running:
  uv run --locked make lint

Full acceptance requires every configured check.
Explicit skip and recursive execution requests refuse verification.
EOF

export LAEMP_LOCAL_CI_IN_PROGRESS=1

if ! uv run --locked make lint; then
  hook_fail "pre-push gate failed: uv run --locked make lint"
  exit 1
fi

hook_ok "pre-push gate passed: uv run --locked make lint"
