#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=platforms/lima/lib.sh
source "${SCRIPT_DIR}/lib.sh"

SUPPORTED_COMBOS=(
  "8.3|apache|405"
  "8.3|apache|500"
  "8.3|apache|502"
  "8.3|nginx|405"
  "8.3|nginx|500"
  "8.3|nginx|502"
  "8.4|apache|500"
  "8.4|apache|502"
  "8.4|nginx|500"
  "8.4|nginx|502"
)

DB_TYPE="mariadb"
CERT_MODE="self-signed"
RESULTS_DIR=""
KEEP_FAILED_VM=false
PLAYWRIGHT_SPEC="tests/e2e/vm-smoke.spec.ts"
PLAYWRIGHT_PROJECT="chromium"
PHP_FILTER=""
WEB_FILTER=""
MOODLE_FILTER=""
SITE_DOMAIN="moodle.lima.test"
SITE_HOST="moodle.lima.test.127.0.0.1.sslip.io"
INSTALL_TIMEOUT_SECONDS="${INSTALL_TIMEOUT_SECONDS:-1800}"
ADMIN_USERNAME="${MOODLE_ADMIN_USERNAME:-${MOODLE_ADMIN_USER:-admin}}"
ADMIN_PASSWORD="${MOODLE_ADMIN_PASSWORD:-AdminPass123!}"
ADMIN_EMAIL="demo@moodle.lima.test"
ADMIN_CREDENTIALS_FILE="${MOODLE_ADMIN_CREDENTIALS_FILE:-/var/lib/laemp/moodle-admin-credentials.env}"
declare -a EXTRA_FLAGS=()

function usage() {
  cat <<'EOF'
Run the supported LAEMP Lima matrix with Playwright smoke checks.

Usage:
  platforms/lima/run-matrix.sh [options]

Options:
  --php VERSION             Filter to one PHP version (8.3 or 8.4)
  --web SERVER              Filter to one web server (apache or nginx)
  --moodle VERSION          Filter to one Moodle version (405, 500, 5022)
  --database TYPE           Database type to install (default: mariadb)
  --cert MODE               Certificate mode: self-signed or mkcert (default: self-signed)
  --extra-flag FLAG         Extra laemp.sh flag to pass through (repeatable)
  --keep-failed-vm          Do not delete the Lima instance after a failed run
  --results-dir DIR         Write logs and TSV summary to DIR
  --project NAME            Playwright project to run (default: chromium)
  -h, --help                Show this help text

Examples:
  platforms/lima/run-matrix.sh
  platforms/lima/run-matrix.sh --php 8.4 --web nginx --moodle 5022
  platforms/lima/run-matrix.sh --php 8.4 --web nginx --moodle 5022 --database pgsql --extra-flag -M
EOF
}

function require_playwright() {
  lima_require_tools awk curl date mktemp node npm npx
  if [[ ! -x "${PROJECT_ROOT}/node_modules/.bin/playwright" ]]; then
    echo "Error: Playwright dependencies are not installed." >&2
    echo "Run 'npm install' in ${PROJECT_ROOT} first." >&2
    exit 1
  fi
}

function build_laemp_args() {
  local php_version="$1"
  local web_server="$2"
  local moodle_version="$3"
  local args=(-c -p "${php_version}" -w "${web_server}" -d "${DB_TYPE}" -m "${moodle_version}")

  case "${CERT_MODE}" in
    self-signed)
      args+=(-S)
      ;;
    mkcert)
      args+=(--mkcert)
      ;;
    *)
      echo "Error: unsupported certificate mode '${CERT_MODE}'." >&2
      exit 1
      ;;
  esac

  if [[ ${#EXTRA_FLAGS[@]} -gt 0 ]]; then
    args+=("${EXTRA_FLAGS[@]}")
  fi

  printf '%s\n' "${args[@]}"
}

function combo_matches_filters() {
  local php_version="$1"
  local web_server="$2"
  local moodle_version="$3"

  [[ -z "${PHP_FILTER}" || "${PHP_FILTER}" == "${php_version}" ]] || return 1
  [[ -z "${WEB_FILTER}" || "${WEB_FILTER}" == "${web_server}" ]] || return 1
  [[ -z "${MOODLE_FILTER}" || "${MOODLE_FILTER}" == "${moodle_version}" ]] || return 1
}

function read_admin_credentials_from_vm() {
  local instance_name="$1"
  local credentials_file_q
  printf -v credentials_file_q '%q' "${ADMIN_CREDENTIALS_FILE}"
  lima_shell_root_bash "${instance_name}" "test -f ${credentials_file_q}"
  lima_shell_root_bash "${instance_name}" "set -a; . ${credentials_file_q}; set +a; printf '%s\t%s\n' \"\${MOODLE_ADMIN_USERNAME:-}\" \"\${MOODLE_ADMIN_PASSWORD:-}\""
}

function extract_admin_password() {
  local install_log="$1"
  awk -F': ' '/Admin password:/ {print $NF; exit}' "${install_log}"
}

function verify_external_access() {
  local combo_dir="$1"

  curl -ksSfI "https://${SITE_HOST}" | head -n 1 >"${combo_dir}/http_head_external.txt"
  curl -sSI "http://${SITE_HOST}" >"${combo_dir}/http_redirect_external.txt"
  grep -q "^HTTP/.* 301" "${combo_dir}/http_redirect_external.txt"
  grep -qi "^location: https://${SITE_HOST}/" "${combo_dir}/http_redirect_external.txt"
}

function verify_stack_in_vm() {
  local instance_name="$1"
  local web_server="$2"
  local combo_dir="$3"
  local table_count=""
  local web_service="${web_server}"

  if [[ "${web_server}" == "apache" ]]; then
    web_service="apache2"
  fi

  lima_shell_root_bash "${instance_name}" "test -f /var/www/html/${SITE_HOST}/config.php"
  lima_shell_bash "${instance_name}" "curl -ksSfI https://127.0.0.1 | head -n 1" >"${combo_dir}/http_head_internal.txt"
  verify_external_access "${combo_dir}"

  lima_shell_root_bash "${instance_name}" "systemctl is-active ${web_service}" >"${combo_dir}/web_service.txt"
  lima_shell_root_bash "${instance_name}" "systemctl is-active cron" >"${combo_dir}/cron_service.txt"

  if [[ "${DB_TYPE}" == "pgsql" ]]; then
    lima_shell_root_bash "${instance_name}" "systemctl is-active postgresql" >"${combo_dir}/db_service.txt"
    table_count=$(lima_shell_root_bash "${instance_name}" "sudo -u postgres psql -d moodle -Atc \"select count(*) from information_schema.tables where table_schema = 'public' and table_name like 'mdl_%';\"")
  else
    lima_shell_root_bash "${instance_name}" "systemctl is-active mariadb" >"${combo_dir}/db_service.txt"
    table_count=$(lima_shell_root_bash "${instance_name}" "mysql -Nse \"select count(*) from information_schema.tables where table_schema = 'moodle' and table_name like 'mdl_%';\"")
  fi

  if [[ -z "${table_count}" || "${table_count}" -lt 400 ]]; then
    echo "Error: Moodle table count check failed for ${instance_name} (${table_count:-missing})." >&2
    return 1
  fi

  lima_shell_root_bash "${instance_name}" "/tmp/verify-moodle.sh -k" >"${combo_dir}/verify-moodle.txt"
  printf '%s\n' "${table_count}" >"${combo_dir}/table_count.txt"
}

function run_playwright_smoke() {
  local combo_dir="$1"
  local admin_username="$2"
  local admin_password="$3"

  (
    cd "${PROJECT_ROOT}"
    MOODLE_URL="https://${SITE_HOST}" \
    MOODLE_HTTP_URL="http://${SITE_HOST}" \
    MOODLE_ADMIN_USERNAME="${admin_username}" \
    MOODLE_ADMIN_PASSWORD="${admin_password}" \
    MOODLE_ADMIN_EMAIL="${ADMIN_EMAIL}" \
    MOODLE_SITE_NAME="${SITE_HOST}" \
    npx playwright test "${PLAYWRIGHT_SPEC}" \
      --project "${PLAYWRIGHT_PROJECT}" \
      --reporter=list \
      --workers 1 \
      --output "${combo_dir}/playwright-output"
  ) 2>&1 | tee "${combo_dir}/playwright.log"
}

function cleanup_instance() {
  local instance_name="$1"
  local run_status="$2"

  if [[ -z "${instance_name}" ]]; then
    return 0
  fi

  if [[ "${run_status}" != "PASS" && "${KEEP_FAILED_VM}" == "true" ]]; then
    echo "Keeping failed Lima instance ${instance_name} for inspection." >&2
    return 0
  fi

  lima_delete_instance "${instance_name}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --php)
      PHP_FILTER="${2:?missing value for --php}"
      shift 2
      ;;
    --web)
      WEB_FILTER="${2:?missing value for --web}"
      shift 2
      ;;
    --moodle)
      MOODLE_FILTER="${2:?missing value for --moodle}"
      shift 2
      ;;
    --database)
      DB_TYPE="${2:?missing value for --database}"
      shift 2
      ;;
    --cert)
      CERT_MODE="${2:?missing value for --cert}"
      shift 2
      ;;
    --extra-flag)
      EXTRA_FLAGS+=("${2:?missing value for --extra-flag}")
      shift 2
      ;;
    --keep-failed-vm)
      KEEP_FAILED_VM=true
      shift
      ;;
    --results-dir)
      RESULTS_DIR="${2:?missing value for --results-dir}"
      shift 2
      ;;
    --project)
      PLAYWRIGHT_PROJECT="${2:?missing value for --project}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option '$1'." >&2
      usage >&2
      exit 1
      ;;
  esac
done

lima_require
require_playwright

if [[ -z "${RESULTS_DIR}" ]]; then
  RESULTS_DIR="$(mktemp -d "/tmp/laemp-lima-matrix-$(date +%Y%m%d-%H%M%S)-XXXX")"
else
  mkdir -p "${RESULTS_DIR}"
fi

RESULTS_TSV="${RESULTS_DIR}/results.tsv"
printf 'label\tstatus\tinstance\turl\tphp\tweb\tmoodle\tdatabase\tcert\tadmin_email\ttable_count\tartifacts\n' >"${RESULTS_TSV}"

matched=0
failures=0
declare -a LAEMP_ARGS=()
active_instance=""

function cleanup_active_instance_on_exit() {
  if [[ -n "${active_instance}" ]]; then
    cleanup_instance "${active_instance}" "FAIL"
  fi
}

trap cleanup_active_instance_on_exit EXIT

for combo in "${SUPPORTED_COMBOS[@]}"; do
  IFS='|' read -r php_version web_server moodle_version <<<"${combo}"

  if ! combo_matches_filters "${php_version}" "${web_server}" "${moodle_version}"; then
    continue
  fi

  matched=1
  label="php${php_version}-${web_server}-moodle${moodle_version}-${DB_TYPE}"
  combo_dir="${RESULTS_DIR}/${label}"
  mkdir -p "${combo_dir}"
  start_log="${combo_dir}/lima-start.log"
  install_log="${combo_dir}/install.log"
  run_status="FAIL"
  instance_name="${LIMA_INSTANCE_PREFIX}-$(lima_slugify "${label}")"
  admin_username="${ADMIN_USERNAME}"
  admin_password="${ADMIN_PASSWORD}"

  echo "=== ${label} ==="
  if ! lima_start_instance "${instance_name}" >"${start_log}" 2>&1; then
    failures=$((failures + 1))
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${label}" "${run_status}" "${instance_name}" "https://${SITE_HOST}" "${php_version}" "${web_server}" "${moodle_version}" "${DB_TYPE}" "${CERT_MODE}" "${ADMIN_EMAIL}" "" "${combo_dir}" >>"${RESULTS_TSV}"
    continue
  fi
  active_instance="${instance_name}"

  lima_copy "${PROJECT_ROOT}/laemp.sh" "${instance_name}:/tmp/laemp.sh" >/dev/null
  lima_copy "${PROJECT_ROOT}/verify-moodle.sh" "${instance_name}:/tmp/verify-moodle.sh" >/dev/null
  lima_shell_root_bash "${instance_name}" "chmod 0755 /tmp/laemp.sh /tmp/verify-moodle.sh"

  LAEMP_ARGS=()
  while IFS= read -r arg; do
    LAEMP_ARGS+=("${arg}")
  done < <(build_laemp_args "${php_version}" "${web_server}" "${moodle_version}")

  install_cmd=$(
    printf 'export DEBIAN_FRONTEND=noninteractive MOODLE_SITE_DOMAIN=%q MOODLE_SITE_HOST=%q MOODLE_ADMIN_USERNAME=%q MOODLE_ADMIN_EMAIL=%q; ' \
      "${SITE_DOMAIN}" "${SITE_HOST}" "${ADMIN_USERNAME}" "${ADMIN_EMAIL}"
  )
  if [[ -n "${ADMIN_PASSWORD}" ]]; then
    install_cmd+=$(printf 'export MOODLE_ADMIN_PASSWORD=%q; ' "${ADMIN_PASSWORD}")
  fi
  install_cmd+=$(printf 'timeout %q /tmp/laemp.sh' "${INSTALL_TIMEOUT_SECONDS}")
  for arg in "${LAEMP_ARGS[@]}"; do
    install_cmd+=" $(printf '%q' "${arg}")"
  done

  if lima_shell_root_bash "${instance_name}" "${install_cmd}" 2>&1 | tee "${install_log}"; then
    credentials_line="$(read_admin_credentials_from_vm "${instance_name}" 2>/dev/null || true)"
    if [[ -n "${credentials_line}" ]]; then
      IFS=$'\t' read -r admin_username admin_password <<<"${credentials_line}"
    fi
    if [[ -z "${admin_password}" ]]; then
      admin_password="$(extract_admin_password "${install_log}" || true)"
    fi
    if [[ -z "${admin_password}" ]]; then
      echo "Error: could not extract admin password from ${install_log}." >&2
      failures=$((failures + 1))
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${label}" "FAIL" "${instance_name}" "https://${SITE_HOST}" "${php_version}" "${web_server}" "${moodle_version}" "${DB_TYPE}" "${CERT_MODE}" "${ADMIN_EMAIL}" "" "${combo_dir}" >>"${RESULTS_TSV}"
      cleanup_instance "${instance_name}" "${run_status}"
      active_instance=""
      continue
    fi

    if verify_stack_in_vm "${instance_name}" "${web_server}" "${combo_dir}" && \
      run_playwright_smoke "${combo_dir}" "${admin_username}" "${admin_password}"; then
      table_count="$(cat "${combo_dir}/table_count.txt")"
      run_status="PASS"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${label}" "${run_status}" "${instance_name}" "https://${SITE_HOST}" "${php_version}" "${web_server}" "${moodle_version}" "${DB_TYPE}" "${CERT_MODE}" "${ADMIN_EMAIL}" "${table_count}" "${combo_dir}" >>"${RESULTS_TSV}"
    else
      failures=$((failures + 1))
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${label}" "FAIL" "${instance_name}" "https://${SITE_HOST}" "${php_version}" "${web_server}" "${moodle_version}" "${DB_TYPE}" "${CERT_MODE}" "${ADMIN_EMAIL}" "" "${combo_dir}" >>"${RESULTS_TSV}"
    fi
  else
    failures=$((failures + 1))
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${label}" "${run_status}" "${instance_name}" "https://${SITE_HOST}" "${php_version}" "${web_server}" "${moodle_version}" "${DB_TYPE}" "${CERT_MODE}" "${ADMIN_EMAIL}" "" "${combo_dir}" >>"${RESULTS_TSV}"
  fi

  cleanup_instance "${instance_name}" "${run_status}"
  active_instance=""
done

trap - EXIT

if [[ "${matched}" -eq 0 ]]; then
  echo "Error: no supported combos matched the supplied filters." >&2
  exit 1
fi

echo "Results written to ${RESULTS_TSV}"

if [[ "${failures}" -gt 0 ]]; then
  exit 1
fi
