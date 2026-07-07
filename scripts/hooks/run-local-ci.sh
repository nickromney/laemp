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
  hook_print_skip_and_exit
fi

if [[ "${LAEMP_LOCAL_CI_IN_PROGRESS:-}" == "1" ]]; then
  hook_warn "LAEMP_LOCAL_CI_IN_PROGRESS=1; skipping run-local-ci.sh to avoid recursive local CI"
  exit 0
fi

cd "${HOOKS_REPO_ROOT}"

cat <<'EOF'
laemp pre-push local CI gate

Running:
  make lint

Skip only when you have a reason:
  LEFTHOOK=0 git push
  LAEMP_SKIP_HOOKS=1 git push
  git push --no-verify
EOF

export LAEMP_LOCAL_CI_IN_PROGRESS=1

if ! make lint; then
  hook_fail "pre-push gate failed: make lint"
  exit 1
fi

hook_ok "pre-push gate passed: make lint"
