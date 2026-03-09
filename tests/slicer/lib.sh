#!/usr/bin/env bash

set -euo pipefail

SLICER_URL="${SLICER_URL:-$HOME/slicer-mac/slicer.sock}"
SLICER_HOSTGROUP="${SLICER_HOSTGROUP:-sbox}"
SLICER_VM_UID="${SLICER_VM_UID:-1000}"

function slicer_require() {
  if ! command -v slicer >/dev/null 2>&1; then
    echo "Error: slicer CLI is not installed or not in PATH." >&2
    exit 1
  fi

  if ! slicer vm list --url "${SLICER_URL}" >/dev/null 2>&1; then
    echo "Error: cannot reach Slicer daemon at ${SLICER_URL}." >&2
    echo "Set SLICER_URL if your daemon is not on the default socket." >&2
    exit 1
  fi
}

function slicer_require_tools() {
  local tool
  for tool in "$@"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "Error: required tool '${tool}' is not installed." >&2
      exit 1
    fi
  done
}

function slicer_create_vm() {
  local workflow="$1"
  local output
  output=$(slicer vm add "${SLICER_HOSTGROUP}" --url "${SLICER_URL}" \
    --tag "workflow=${workflow}" \
    --tag "owner=laemp")
  printf '%s\n' "${output}" >&2
  awk '/Hostname:/ {print $2; exit}' <<<"${output}"
}

function slicer_wait_vm() {
  local vm_name="$1"
  local timeout="${2:-5m}"
  slicer vm ready "${vm_name}" --url "${SLICER_URL}" --timeout "${timeout}" >/dev/null
}

function slicer_delete_vm() {
  local vm_name="$1"
  slicer vm delete "${vm_name}" --url "${SLICER_URL}" >/dev/null
}

function slicer_wait_no_vm() {
  local vm_name="$1"
  local max_attempts="${2:-30}"
  local attempt

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if ! slicer vm list --url "${SLICER_URL}" | awk 'NR > 2 && $1 != "" { print $1 }' | grep -Fxq "${vm_name}"; then
      return 0
    fi
    sleep 1
  done

  echo "Warning: VM ${vm_name} still appears in slicer vm list after ${max_attempts}s." >&2
  return 1
}

function slicer_restart_daemon() {
  local max_attempts="${1:-30}"
  local attempt

  if ! command -v slicer-mac >/dev/null 2>&1; then
    return 0
  fi

  slicer-mac service stop daemon >/dev/null || true
  slicer-mac service start daemon >/dev/null

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if slicer vm list --url "${SLICER_URL}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "Error: Slicer daemon did not come back after restart." >&2
  return 1
}

function slicer_vm_ip() {
  local vm_name="$1"
  slicer vm list --url "${SLICER_URL}" | awk -v vm="${vm_name}" '$1==vm {print $2; exit}'
}

function slicer_vm_cp() {
  slicer vm cp --url "${SLICER_URL}" "$@"
}

function slicer_vm_exec() {
  local vm_name="$1"
  shift
  slicer vm exec "${vm_name}" --url "${SLICER_URL}" --uid "${SLICER_VM_UID}" "$@"
}

function slicer_vm_exec_retry() {
  local vm_name="$1"
  shift
  for _ in 1 2 3 4 5; do
    if slicer vm exec "${vm_name}" --url "${SLICER_URL}" --uid "${SLICER_VM_UID}" "$@"; then
      return 0
    fi
    sleep 2
  done

  return 1
}

function slicer_vm_exec_root_retry() {
  local vm_name="$1"
  shift
  for _ in 1 2 3 4 5; do
    if slicer vm exec "${vm_name}" --url "${SLICER_URL}" "$@"; then
      return 0
    fi
    sleep 2
  done

  return 1
}

function slicer_vm_exec_root() {
  local vm_name="$1"
  shift
  slicer vm exec "${vm_name}" --url "${SLICER_URL}" "$@"
}

function slicer_latest_vm() {
  slicer vm list --url "${SLICER_URL}" | awk 'NR>2 && $1!="" {print $1; exit}'
}

function slicer_slugify() {
  tr '[:upper:]' '[:lower:]' <<<"$1" | tr -cs '[:alnum:]' '-'
}
