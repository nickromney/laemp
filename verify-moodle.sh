#!/usr/bin/env bash

set -euo pipefail

BACKEND="${BACKEND:-auto}"
DATABASE="${DB_TYPE:-auto}"
PHP_RUNTIME="${PHP_RUNTIME:-auto}"
URL="${MOODLE_URL:-}"
CONFIG_PATH="${MOODLE_CONFIG_PATH:-}"
CONFIG_CHECK_COMMAND="${CONFIG_CHECK_COMMAND:-}"
WEB_CHECK_COMMAND="${WEB_CHECK_COMMAND:-}"
PHP_CHECK_COMMAND="${PHP_CHECK_COMMAND:-}"
DB_PING_COMMAND="${DB_PING_COMMAND:-}"
DB_QUERY_COMMAND="${DB_QUERY_COMMAND:-}"
DB_HOST="${DB_HOST:-}"
DB_NAME="${DB_NAME:-moodle}"
DB_USER="${DB_USER:-moodle}"
DB_PASSWORD="${DB_PASS:-${MOODLE_DB_PASSWORD:-}}"
DB_PASSWORD_FILE=""
DB_PREFIX="${DB_PREFIX:-mdl_}"
TABLE_MIN="${TABLE_MIN:-400}"
CONTENT_MATCH="${CONTENT_MATCH:-}"
USE_INSECURE=false
SKIP_CONFIG_CHECK=false
SKIP_WEB_CHECK=false
SKIP_PHP_CHECK=false
SKIP_DB_CHECK=false
SKIP_ASSET_CHECK=false
ASSET_SMOKE_PATH="${ASSET_SMOKE_PATH:-/login/index.php}"

function usage() {
  cat <<'EOF'
Verify a Moodle installation and exit non-zero on failure.

Usage:
  verify-moodle.sh [options]

Options:
  --backend TYPE            nginx, apache, frankenphp, none, or auto
  --database TYPE           mariadb, mysqli, mysql, pgsql, none, or auto
  --php-runtime TYPE        fpm, embedded, none, or auto
  --url URL                 Site URL to probe
  --config-path PATH        Moodle config.php path
  --config-check-command CMD
                            Shell command used instead of testing config.php locally
  --web-check-command CMD   Shell command used instead of local web process detection
  --php-check-command CMD   Shell command used instead of local PHP runtime detection
  --db-ping-command CMD     Shell command used instead of built-in DB ping
  --db-query-command CMD    Shell command that prints the Moodle table count
  --db-host HOST            Database host
  --db-name NAME            Database name (default: moodle)
  --db-user USER            Database user (default: moodle)
  --db-password PASSWORD    Database password
  --db-password-file PATH   Read database password from PATH
  --db-prefix PREFIX        Moodle table prefix (default: mdl_)
  --table-min COUNT         Minimum expected Moodle table count (default: 400)
  --content-match TEXT      Require TEXT to appear in the HTTP response body
  -k, --insecure            Use curl -k
  --skip-config-check       Skip config.php verification
  --skip-web-check          Skip web process verification
  --skip-php-check          Skip PHP runtime verification
  --skip-db-check           Skip database verification
  --skip-asset-check        Skip Moodle PHP asset route verification
  -h, --help                Show this help text

Environment:
  DB_TYPE, DB_HOST, DB_NAME, DB_USER, DB_PASS, MOODLE_URL, MOODLE_CONFIG_PATH,
  BACKEND, PHP_RUNTIME, DB_PING_COMMAND, DB_QUERY_COMMAND, CONTENT_MATCH
EOF
}

function info() {
  printf '[INFO] %s\n' "$1"
}

function ok() {
  printf '[OK] %s\n' "$1"
}

function fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

function run_shell_command() {
  local command="$1"
  bash -lc "${command}"
}

function trim() {
  awk '{$1=$1; print}'
}

function read_password_file() {
  if [[ -n "${DB_PASSWORD_FILE}" ]]; then
    [[ -f "${DB_PASSWORD_FILE}" ]] || fail "Database password file not found: ${DB_PASSWORD_FILE}"
    DB_PASSWORD="$(tr -d '\r\n' < "${DB_PASSWORD_FILE}")"
  fi
}

function detect_config_path() {
  local candidate=""

  if [[ -n "${CONFIG_PATH}" ]]; then
    printf '%s\n' "${CONFIG_PATH}"
    return 0
  fi

  for candidate in \
    /app/public/config.php \
    /var/www/html/config.php; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  candidate="$(find /var/www/html /srv/www /app -maxdepth 4 -name config.php 2>/dev/null | head -n 1 || true)"
  if [[ -n "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
  fi
}

function config_value() {
  local key="$1"
  local path="$2"

  sed -n "s/^[[:space:]]*\\\$CFG->${key}[[:space:]]*=[[:space:]]*'\\([^']*\\)'.*/\\1/p" "${path}" | head -n 1
}

function normalize_database_type() {
  case "$1" in
    mysql|mysqli|mariadb)
      printf '%s\n' "mariadb"
      ;;
    pgsql|postgres|postgresql)
      printf '%s\n' "pgsql"
      ;;
    none|auto|"")
      printf '%s\n' "$1"
      ;;
    *)
      fail "Unsupported database type: $1"
      ;;
  esac
}

function backend_pattern() {
  case "$1" in
    nginx)
      printf '%s\n' '(^|/)(nginx)(:|$)|nginx: master process'
      ;;
    apache)
      printf '%s\n' 'apache2|httpd'
      ;;
    frankenphp)
      printf '%s\n' 'frankenphp|caddy'
      ;;
    *)
      return 1
      ;;
  esac
}

function check_local_process() {
  local pattern="$1"
  pgrep -f "${pattern}" >/dev/null 2>&1
}

function resolve_backend() {
  if [[ "${BACKEND}" != "auto" ]]; then
    printf '%s\n' "${BACKEND}"
    return 0
  fi

  if check_local_process "$(backend_pattern nginx)"; then
    printf '%s\n' "nginx"
    return 0
  fi

  if check_local_process "$(backend_pattern apache)"; then
    printf '%s\n' "apache"
    return 0
  fi

  if check_local_process "$(backend_pattern frankenphp)"; then
    printf '%s\n' "frankenphp"
    return 0
  fi

  printf '%s\n' "none"
}

function resolve_php_runtime() {
  if [[ "${PHP_RUNTIME}" != "auto" ]]; then
    printf '%s\n' "${PHP_RUNTIME}"
    return 0
  fi

  if check_local_process 'php-fpm|php-fpm[0-9.]+'; then
    printf '%s\n' "fpm"
    return 0
  fi

  printf '%s\n' "none"
}

function resolve_url() {
  if [[ -n "${URL}" ]]; then
    printf '%s\n' "${URL}"
    return 0
  fi

  if [[ -n "${CONFIG_PATH}" && -f "${CONFIG_PATH}" ]]; then
    URL="$(config_value "wwwroot" "${CONFIG_PATH}" || true)"
    if [[ -n "${URL}" ]]; then
      printf '%s\n' "${URL}"
      return 0
    fi
  fi

  if curl -ksS -o /dev/null -I https://localhost >/dev/null 2>&1; then
    USE_INSECURE=true
    printf '%s\n' "https://localhost"
    return 0
  fi

  printf '%s\n' "http://localhost"
}

function maybe_fill_database_settings_from_config() {
  [[ -n "${CONFIG_PATH}" && -f "${CONFIG_PATH}" ]] || return 0

  if [[ "${DATABASE}" == "auto" ]]; then
    local config_dbtype=""
    config_dbtype="$(config_value "dbtype" "${CONFIG_PATH}" || true)"
    if [[ -n "${config_dbtype}" ]]; then
      DATABASE="$(normalize_database_type "${config_dbtype}")"
    fi
  fi

  [[ -n "${DB_HOST}" ]] || DB_HOST="$(config_value "dbhost" "${CONFIG_PATH}" || true)"
  [[ -n "${DB_NAME}" ]] || DB_NAME="$(config_value "dbname" "${CONFIG_PATH}" || true)"
  [[ -n "${DB_USER}" ]] || DB_USER="$(config_value "dbuser" "${CONFIG_PATH}" || true)"
  [[ -n "${DB_PASSWORD}" ]] || DB_PASSWORD="$(config_value "dbpass" "${CONFIG_PATH}" || true)"
}

function require_integer() {
  [[ "$1" =~ ^[0-9]+$ ]] || fail "Expected an integer, got: $1"
}

function http_status() {
  local curl_args=(-sS -o /dev/null -w '%{http_code}' -L)
  [[ "${USE_INSECURE}" == "true" ]] && curl_args+=(-k)
  curl "${curl_args[@]}" "${URL}"
}

function http_body_contains() {
  local curl_args=(-fsSL)
  [[ "${USE_INSECURE}" == "true" ]] && curl_args+=(-k)
  curl "${curl_args[@]}" "${URL}" | grep -q --fixed-strings "${CONTENT_MATCH}"
}

function http_get() {
  local target_url="$1"
  local curl_args=(-fsSL)
  [[ "${USE_INSECURE}" == "true" ]] && curl_args+=(-k)
  curl "${curl_args[@]}" "${target_url}"
}

function http_status_for() {
  local target_url="$1"
  local curl_args=(-sS -o /dev/null -w '%{http_code}' -L)
  [[ "${USE_INSECURE}" == "true" ]] && curl_args+=(-k)
  curl "${curl_args[@]}" "${target_url}"
}

function url_origin() {
  printf '%s\n' "${1}" | sed -E 's#^(https?://[^/]+).*$#\1#'
}

function join_url() {
  local base="$1"
  local path="$2"

  if [[ "${path}" =~ ^https?:// ]]; then
    printf '%s\n' "${path}"
  elif [[ "${path}" == /* ]]; then
    printf '%s%s\n' "${base%/}" "${path}"
  else
    printf '%s/%s\n' "${base%/}" "${path}"
  fi
}

function resolve_asset_url() {
  local origin="$1"
  local candidate="$2"

  [[ -n "${candidate}" ]] || return 0
  join_url "${origin}" "${candidate}"
}

function first_match() {
  local pattern="$1"
  grep -Eo "${pattern}" | head -n 1 || true
}

function check_asset_route() {
  local label="$1"
  local asset_url="$2"
  local status_code

  [[ -n "${asset_url}" ]] || fail "Could not find ${label} asset URL to verify"

  status_code="$(http_status_for "${asset_url}" || true)"
  [[ "${status_code}" =~ ^[23][0-9][0-9]$ ]] || fail "${label} asset returned unexpected status ${status_code:-missing}: ${asset_url}"
  ok "${label} asset returned ${status_code}"
}

function check_php_asset_routes() {
  local origin
  local smoke_url
  local page_html
  local stylesheet_url
  local stylesheet_body
  local js_asset_match
  local require_asset_match
  local stylesheet_match
  local font_asset_match
  local js_asset_url
  local require_asset_url
  local font_asset_url

  origin="$(url_origin "${URL}")"
  smoke_url="$(join_url "${origin}" "${ASSET_SMOKE_PATH}")"
  page_html="$(http_get "${smoke_url}")" || fail "Failed to fetch asset smoke page: ${smoke_url}"

  js_asset_match="$(printf '%s' "${page_html}" | first_match '(https?://[^"[:space:]]+/lib/javascript\.php/[^"[:space:]]+|/lib/javascript\.php/[^"[:space:]]+)')"
  require_asset_match="$(printf '%s' "${page_html}" | first_match '(https?://[^"[:space:]]+/lib/requirejs\.php/[^"[:space:]]+|/lib/requirejs\.php/[^"[:space:]]+)')"
  stylesheet_match="$(printf '%s' "${page_html}" | first_match '(https?://[^"[:space:]]+/theme/styles\.php/[^"[:space:]]+|/theme/styles\.php/[^"[:space:]]+)')"
  js_asset_url="$(resolve_asset_url "${origin}" "${js_asset_match}")"
  require_asset_url="$(resolve_asset_url "${origin}" "${require_asset_match}")"
  stylesheet_url="$(resolve_asset_url "${origin}" "${stylesheet_match}")"

  check_asset_route "JavaScript" "${js_asset_url}"
  check_asset_route "RequireJS" "${require_asset_url}"

  if [[ -n "${stylesheet_url}" ]]; then
    stylesheet_body="$(http_get "${stylesheet_url}")" || fail "Failed to fetch stylesheet asset URL: ${stylesheet_url}"
    font_asset_match="$(printf '%s' "${stylesheet_body}" | first_match '(https?://[^)"'\''[:space:]]+/theme/font\.php/[^)"'\''[:space:]]+|/theme/font\.php/[^)"'\''[:space:]]+)')"
    font_asset_url="$(resolve_asset_url "${origin}" "${font_asset_match}")"
    if [[ -n "${font_asset_url}" ]]; then
      check_asset_route "Theme font" "${font_asset_url}"
    else
      info "Skipping theme font asset check because no theme/font.php URL was found"
    fi
  else
    info "Skipping theme font asset check because no theme stylesheet URL was found"
  fi
}

function default_db_ping_command() {
  case "${DATABASE}" in
    mariadb)
      local client="mysqladmin"
      command -v mysqladmin >/dev/null 2>&1 || client="mariadb-admin"
      command -v "${client}" >/dev/null 2>&1 || fail "Neither mysqladmin nor mariadb-admin is available"
      if [[ -n "${DB_PASSWORD}" ]]; then
        printf 'MYSQL_PWD=%q %q ping -h %q -u %q --silent' "${DB_PASSWORD}" "${client}" "${DB_HOST:-localhost}" "${DB_USER}"
      else
        printf '%q ping -h %q -u %q --silent' "${client}" "${DB_HOST:-localhost}" "${DB_USER}"
      fi
      ;;
    pgsql)
      command -v psql >/dev/null 2>&1 || fail "psql is not available"
      if [[ -n "${DB_PASSWORD}" ]]; then
        printf 'PGPASSWORD=%q psql -h %q -U %q -d %q -Atc %q' \
          "${DB_PASSWORD}" "${DB_HOST:-localhost}" "${DB_USER}" "${DB_NAME}" "SELECT 1;"
      else
        printf 'psql -h %q -U %q -d %q -Atc %q' "${DB_HOST:-localhost}" "${DB_USER}" "${DB_NAME}" "SELECT 1;"
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

function default_db_query_command() {
  case "${DATABASE}" in
    mariadb)
      local client="mysql"
      command -v mysql >/dev/null 2>&1 || client="mariadb"
      command -v "${client}" >/dev/null 2>&1 || fail "Neither mysql nor mariadb is available"
      if [[ -n "${DB_PASSWORD}" ]]; then
        printf 'MYSQL_PWD=%q %q -h %q -u %q -Nse %q' \
          "${DB_PASSWORD}" "${client}" "${DB_HOST:-localhost}" "${DB_USER}" \
          "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '${DB_NAME}' AND table_name LIKE '${DB_PREFIX}%';"
      else
        printf '%q -h %q -u %q -Nse %q' \
          "${client}" "${DB_HOST:-localhost}" "${DB_USER}" \
          "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '${DB_NAME}' AND table_name LIKE '${DB_PREFIX}%';"
      fi
      ;;
    pgsql)
      command -v psql >/dev/null 2>&1 || fail "psql is not available"
      if [[ -n "${DB_PASSWORD}" ]]; then
        printf 'PGPASSWORD=%q psql -h %q -U %q -d %q -Atc %q' \
          "${DB_PASSWORD}" "${DB_HOST:-localhost}" "${DB_USER}" "${DB_NAME}" \
          "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name LIKE '${DB_PREFIX}%';"
      else
        printf 'psql -h %q -U %q -d %q -Atc %q' \
          "${DB_HOST:-localhost}" "${DB_USER}" "${DB_NAME}" \
          "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name LIKE '${DB_PREFIX}%';"
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend)
      BACKEND="${2:?missing value for --backend}"
      shift 2
      ;;
    --database)
      DATABASE="${2:?missing value for --database}"
      shift 2
      ;;
    --php-runtime)
      PHP_RUNTIME="${2:?missing value for --php-runtime}"
      shift 2
      ;;
    --url)
      URL="${2:?missing value for --url}"
      shift 2
      ;;
    --config-path)
      CONFIG_PATH="${2:?missing value for --config-path}"
      shift 2
      ;;
    --config-check-command)
      CONFIG_CHECK_COMMAND="${2:?missing value for --config-check-command}"
      shift 2
      ;;
    --web-check-command)
      WEB_CHECK_COMMAND="${2:?missing value for --web-check-command}"
      shift 2
      ;;
    --php-check-command)
      PHP_CHECK_COMMAND="${2:?missing value for --php-check-command}"
      shift 2
      ;;
    --db-ping-command)
      DB_PING_COMMAND="${2:?missing value for --db-ping-command}"
      shift 2
      ;;
    --db-query-command)
      DB_QUERY_COMMAND="${2:?missing value for --db-query-command}"
      shift 2
      ;;
    --db-host)
      DB_HOST="${2:?missing value for --db-host}"
      shift 2
      ;;
    --db-name)
      DB_NAME="${2:?missing value for --db-name}"
      shift 2
      ;;
    --db-user)
      DB_USER="${2:?missing value for --db-user}"
      shift 2
      ;;
    --db-password)
      DB_PASSWORD="${2:?missing value for --db-password}"
      shift 2
      ;;
    --db-password-file)
      DB_PASSWORD_FILE="${2:?missing value for --db-password-file}"
      shift 2
      ;;
    --db-prefix)
      DB_PREFIX="${2:?missing value for --db-prefix}"
      shift 2
      ;;
    --table-min)
      TABLE_MIN="${2:?missing value for --table-min}"
      shift 2
      ;;
    --content-match)
      CONTENT_MATCH="${2:?missing value for --content-match}"
      shift 2
      ;;
    -k|--insecure)
      USE_INSECURE=true
      shift
      ;;
    --skip-config-check)
      SKIP_CONFIG_CHECK=true
      shift
      ;;
    --skip-web-check)
      SKIP_WEB_CHECK=true
      shift
      ;;
    --skip-php-check)
      SKIP_PHP_CHECK=true
      shift
      ;;
    --skip-db-check)
      SKIP_DB_CHECK=true
      shift
      ;;
    --skip-asset-check)
      SKIP_ASSET_CHECK=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

require_integer "${TABLE_MIN}"
read_password_file
CONFIG_PATH="$(detect_config_path || true)"
maybe_fill_database_settings_from_config
DATABASE="$(normalize_database_type "${DATABASE}")"
URL="$(resolve_url)"
BACKEND="$(resolve_backend)"
PHP_RUNTIME="$(resolve_php_runtime)"

info "URL: ${URL}"
info "Backend: ${BACKEND}"
info "PHP runtime: ${PHP_RUNTIME}"
if [[ -n "${CONFIG_PATH}" ]]; then
  info "Config path: ${CONFIG_PATH}"
fi
if [[ "${DATABASE}" != "none" && "${DATABASE}" != "auto" ]]; then
  info "Database: ${DATABASE}"
fi

if [[ "${SKIP_CONFIG_CHECK}" != "true" ]]; then
  if [[ -n "${CONFIG_CHECK_COMMAND}" ]]; then
    run_shell_command "${CONFIG_CHECK_COMMAND}" >/dev/null 2>&1 || fail "Custom config check failed"
    ok "Config check command succeeded"
  elif [[ -n "${CONFIG_PATH}" && -f "${CONFIG_PATH}" ]]; then
    ok "Config file exists at ${CONFIG_PATH}"
  else
    fail "Could not find config.php"
  fi
fi

if [[ "${SKIP_WEB_CHECK}" != "true" ]]; then
  if [[ -n "${WEB_CHECK_COMMAND}" ]]; then
    run_shell_command "${WEB_CHECK_COMMAND}" >/dev/null 2>&1 || fail "Custom web check failed"
    ok "Custom web check succeeded"
  elif [[ "${BACKEND}" == "none" ]]; then
    info "Skipping web process check because no backend was detected"
  else
    check_local_process "$(backend_pattern "${BACKEND}")" || fail "Expected ${BACKEND} process is not running"
    ok "Detected ${BACKEND} process"
  fi
fi

if [[ "${SKIP_PHP_CHECK}" != "true" ]]; then
  if [[ -n "${PHP_CHECK_COMMAND}" ]]; then
    run_shell_command "${PHP_CHECK_COMMAND}" >/dev/null 2>&1 || fail "Custom PHP check failed"
    ok "Custom PHP runtime check succeeded"
  elif [[ "${PHP_RUNTIME}" == "fpm" ]]; then
    check_local_process 'php-fpm|php-fpm[0-9.]+' || fail "Expected PHP-FPM process is not running"
    ok "Detected PHP-FPM process"
  else
    info "Skipping PHP runtime process check"
  fi
fi

http_code="$(http_status || true)"
[[ "${http_code}" =~ ^[23][0-9][0-9]$ ]] || fail "Unexpected HTTP status from ${URL}: ${http_code:-missing}"
ok "HTTP probe returned ${http_code}"

if [[ -n "${CONTENT_MATCH}" ]]; then
  http_body_contains || fail "Response body did not contain expected text: ${CONTENT_MATCH}"
  ok "Response body contains expected text"
fi

if [[ "${SKIP_ASSET_CHECK}" != "true" ]]; then
  check_php_asset_routes
fi

if [[ "${SKIP_DB_CHECK}" != "true" ]]; then
  if [[ -z "${DB_PING_COMMAND}" ]]; then
    DB_PING_COMMAND="$(default_db_ping_command || true)"
  fi
  if [[ -z "${DB_QUERY_COMMAND}" ]]; then
    DB_QUERY_COMMAND="$(default_db_query_command || true)"
  fi

  [[ -n "${DB_PING_COMMAND}" ]] || fail "No database ping command is available"
  [[ -n "${DB_QUERY_COMMAND}" ]] || fail "No database query command is available"

  run_shell_command "${DB_PING_COMMAND}" >/dev/null 2>&1 || fail "Database connectivity check failed"
  ok "Database connectivity check passed"

  table_count="$(run_shell_command "${DB_QUERY_COMMAND}" 2>/dev/null | tail -n 1 | trim || true)"
  require_integer "${table_count}"
  (( table_count >= TABLE_MIN )) || fail "Expected at least ${TABLE_MIN} Moodle tables, found ${table_count}"
  ok "Moodle database contains ${table_count} tables"
fi

ok "Moodle verification completed successfully"
