#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LIMA_CMD="${LIMA_CMD:-limactl}"
LIMA_TEMPLATE="${LIMA_TEMPLATE:-${SCRIPT_DIR}/config/lima-moodle.yaml}"
LIMA_INSTANCE_PREFIX="${LIMA_INSTANCE_PREFIX:-laemp-moodle}"

function lima_require() {
  if ! command -v "${LIMA_CMD}" >/dev/null 2>&1; then
    echo "Error: ${LIMA_CMD} is not installed or not in PATH." >&2
    exit 1
  fi
}

function lima_require_tools() {
  local tool
  for tool in "$@"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "Error: required tool '${tool}' is not installed." >&2
      exit 1
    fi
  done
}

function lima_slugify() {
  local slug
  slug=$(tr '[:upper:]' '[:lower:]' <<<"$1" | tr -cs '[:alnum:]' '-')
  slug="${slug#-}"
  slug="${slug%-}"
  printf '%s\n' "${slug}"
}

function lima_instance_exists() {
  local instance_name="$1"
  "${LIMA_CMD}" list -q 2>/dev/null | grep -Fxq "${instance_name}"
}

function lima_delete_instance() {
  local instance_name="$1"

  if ! lima_instance_exists "${instance_name}"; then
    return 0
  fi

  "${LIMA_CMD}" delete -f -y "${instance_name}" >/dev/null
}

function lima_wait_ready() {
  local instance_name="$1"
  local max_attempts="${2:-60}"
  local attempt

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if "${LIMA_CMD}" shell "${instance_name}" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "Error: Lima instance ${instance_name} did not become ready." >&2
  return 1
}

function lima_start_instance() {
  local instance_name="$1"

  lima_delete_instance "${instance_name}"
  "${LIMA_CMD}" start -y --name="${instance_name}" "${LIMA_TEMPLATE}"
  lima_wait_ready "${instance_name}"
}

function lima_shell() {
  local instance_name="$1"
  shift
  "${LIMA_CMD}" shell "${instance_name}" "$@"
}

function lima_shell_bash() {
  local instance_name="$1"
  local shell_command="$2"
  "${LIMA_CMD}" shell "${instance_name}" bash -lc "${shell_command}"
}

function lima_shell_root_bash() {
  local instance_name="$1"
  local shell_command="$2"
  "${LIMA_CMD}" shell "${instance_name}" bash -lc "$(printf 'sudo -n bash -lc %q' "${shell_command}")"
}

function lima_copy() {
  "${LIMA_CMD}" copy "$@"
}
