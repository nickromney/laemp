#!/usr/bin/env bash
# shellcheck disable=SC2034 # VK_* settings are read by the sourced verify-lib.sh
set -euo pipefail

VK_SCRIPT="$0"
VK_APP="laemp"
VK_DESCRIPTION="Verification harness for the laemp Moodle installer and an existing Moodle target."
VK_DEFAULT_BASE_DIR="${TMPDIR:-/tmp}/verify-laemp"
VK_DEFAULT_EVIDENCE_ROOT="${TMPDIR:-/tmp}/verify-laemp-evidence"
# shellcheck source=verify-lib.sh disable=SC1091
. "$(cd "$(dirname "$0")" && pwd)/verify-lib.sh"

LAEMP_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
VERIFY_URL="${LAEMP_VERIFY_URL:-}"
VERIFY_CONFIG="${LAEMP_VERIFY_CONFIG_PATH:-}"
VERIFY_BACKEND="${LAEMP_VERIFY_BACKEND:-auto}"
VERIFY_DATABASE="${LAEMP_VERIFY_DATABASE:-auto}"
VERIFY_PHP_RUNTIME="${LAEMP_VERIFY_PHP_RUNTIME:-auto}"
VERIFY_TABLE_MIN="${LAEMP_VERIFY_TABLE_MIN:-400}"

vk_commands_help() {
  cat <<'HELP'
  launch                 preflight the host, then run the installer dry run
  doctor                 require a supported host and a configured existing Moodle target
  cleanup                remove this run's state; evidence is kept
HELP
}

vk_sample_commands() { printf '%s\n' verify launch doctor cleanup; }
vk_paths() {
  STATE="$VK_BASE_DIR/$VK_RUN_ID/state"
  EVIDENCE="$VK_EVIDENCE_ROOT/$VK_RUN_ID"
}

vk_plan() {
  case "$1" in
    verify)
      vk_plan_line "preflight Ubuntu/Debian and configured Moodle target before installer dry run; verify HTTP, PHP assets and database; preserve evidence at $EVIDENCE"
      ;;
    launch)
      vk_plan_line "preflight first, then run ./laemp.sh -n -v -p 8.4 -w nginx -d mariadb -m 5024 -S; no packages or services are installed"
      ;;
    doctor)
      vk_plan_line "require Linux Ubuntu/Debian, curl, an existing Moodle config.php, and LAEMP_VERIFY_URL; read-only"
      ;;
    cleanup)
      vk_plan_line "remove $STATE; keep $EVIDENCE"
      ;;
    *) vk_unknown_command ;;
  esac
}

cmd_preflight() {
  local os_name=""
  local distro_id=""
  local url_authority=""

  os_name="$(uname -s)"
  if [ "$os_name" != Linux ]; then
    vk_fail "laemp.sh supports Ubuntu and Debian Linux; this host is $os_name"
    return 1
  fi

  if [ -r /etc/os-release ]; then
    # shellcheck source=/dev/null # system-provided metadata is only read on Linux hosts
    distro_id="$(. /etc/os-release && printf '%s' "${ID:-}")"
  fi
  case "$distro_id" in
    ubuntu|debian) ;;
    *)
      vk_fail "laemp.sh supports Ubuntu and Debian; detected ${distro_id:-unknown}"
      return 1
      ;;
  esac

  command -v curl >/dev/null 2>&1 || { vk_fail "curl is required for the Moodle HTTP checks"; return 1; }
  [ -n "$VERIFY_URL" ] || { vk_fail "set LAEMP_VERIFY_URL to an existing Moodle site before verification"; return 1; }
  case "$VERIFY_URL" in
    http://*|https://*) ;;
    *) vk_fail "LAEMP_VERIFY_URL must use http or https"; return 1 ;;
  esac
  url_authority="${VERIFY_URL#*://}"
  url_authority="${url_authority%%/*}"
  case "$url_authority" in
    *@*) vk_fail "LAEMP_VERIFY_URL must not contain user credentials"; return 1 ;;
  esac
  case "$VERIFY_URL" in
    *\?*|*\#*) vk_fail "LAEMP_VERIFY_URL must not contain a query or fragment"; return 1 ;;
  esac
  if [ -z "$VERIFY_CONFIG" ] || [ ! -f "$VERIFY_CONFIG" ]; then
    vk_fail "set LAEMP_VERIFY_CONFIG_PATH to the existing Moodle config.php"; return 1;
  fi

  vk_say "OK host=$distro_id Moodle target is configured"
}

cmd_doctor() {
  if [ ! -f "$STATE/launch-ready" ]; then
    vk_fail "no laemp launch recorded for run $VK_RUN_ID; launch first"
    return 1
  fi
  cmd_preflight
}

cmd_launch() {
  local dry_run_log

  # verify-kit calls launch before doctor. Keep the app untouched until doctor passes.
  mkdir -p "$EVIDENCE"
  if ! cmd_preflight >"$EVIDENCE/doctor.log" 2>&1; then
    cat "$EVIDENCE/doctor.log"
    return 1
  fi
  cat "$EVIDENCE/doctor.log"
  mkdir -p "$STATE"
  vk_mark_current
  vk_record_revision "$EVIDENCE/revision.txt"

  dry_run_log="$EVIDENCE/installer-dry-run.log"
  if ! "$LAEMP_ROOT/laemp.sh" -n -v -p 8.4 -w nginx -d mariadb -m 5024 -S >"$dry_run_log" 2>&1; then
    vk_fail "laemp installer dry run failed; see $dry_run_log"
    return 1
  fi
  vk_expect_contains "$dry_run_log" "DRY_RUN_CHANGES: true"
  printf 'installer dry run completed\n' >"$STATE/launch-ready"
  vk_say "laemp installer dry run completed; no installation changes were made"
}

vk_verify_recipes() {
  local verifier_log="$EVIDENCE/moodle-verifier.log"
  local args=(
    --backend "$VERIFY_BACKEND"
    --database "$VERIFY_DATABASE"
    --php-runtime "$VERIFY_PHP_RUNTIME"
    --url "$VERIFY_URL"
    --config-path "$VERIFY_CONFIG"
    --table-min "$VERIFY_TABLE_MIN"
  )

  "$LAEMP_ROOT/verify-moodle.sh" "${args[@]}" >"$verifier_log" 2>&1 || {
    vk_fail "Moodle live checks failed; see $verifier_log"
    return 1
  }
  vk_expect_contains "$verifier_log" "HTTP probe returned"
  vk_expect_contains "$verifier_log" "JavaScript asset returned"
  vk_expect_contains "$verifier_log" "RequireJS asset returned"
  vk_expect_contains "$verifier_log" "Moodle database contains"
}

cmd_cleanup() {
  if [ -n "${STATE:-}" ]; then
    rm -rf "${STATE:?}"
    rmdir "$VK_BASE_DIR/$VK_RUN_ID" 2>/dev/null || true
  fi
  vk_clear_current
  if [ -n "${EVIDENCE:-}" ] && [ -d "$EVIDENCE" ]; then
    vk_say "removed run state; evidence kept at $EVIDENCE"
  fi
}

vk_dispatch() {
  local cmd="$1"
  shift
  case "$cmd" in
    launch) cmd_launch ;;
    doctor) cmd_doctor ;;
    cleanup) cmd_cleanup ;;
    *) vk_unknown_command ;;
  esac
}

vk_main "$@"
