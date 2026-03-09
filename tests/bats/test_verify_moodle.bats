#!/usr/bin/env bats

setup() {
  export VERIFY_SCRIPT="./verify-moodle.sh"
  export TEST_TMPDIR="$(mktemp -d "/tmp/moodle-verify-test-XXXX")"
  export TEST_PORT="$((18000 + (RANDOM % 1000)))"
  export SERVER_PID=""

  cat > "${TEST_TMPDIR}/config.php" <<EOF
<?php
$CFG = new stdClass();
$CFG->dbtype = 'mariadb';
$CFG->dbhost = 'db.internal';
$CFG->dbname = 'moodle';
$CFG->dbuser = 'moodle';
$CFG->dbpass = 'moodlepass';
$CFG->wwwroot = 'http://127.0.0.1:${TEST_PORT}';
EOF
  printf 'Log in to the site\n' > "${TEST_TMPDIR}/index.html"
}

teardown() {
  if [[ -n "${SERVER_PID}" ]]; then
    kill "${SERVER_PID}" >/dev/null 2>&1 || true
    wait "${SERVER_PID}" >/dev/null 2>&1 || true
  fi
  rm -rf "${TEST_TMPDIR}"
}

@test "verify-moodle.sh shows help" {
  run "${VERIFY_SCRIPT}" --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Verify a Moodle installation"* ]]
  [[ "${output}" == *"--db-query-command"* ]]
}

@test "verify-moodle.sh has valid bash syntax" {
  run bash -n "${VERIFY_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "verify-moodle.sh can verify a synthetic install with custom database commands" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 is required for the local HTTP fixture"
  fi

  python3 -m http.server "${TEST_PORT}" --directory "${TEST_TMPDIR}" >"${TEST_TMPDIR}/http.log" 2>&1 &
  SERVER_PID=$!
  sleep 1

  run "${VERIFY_SCRIPT}" \
    --backend none \
    --database mariadb \
    --skip-web-check \
    --skip-php-check \
    --url "http://127.0.0.1:${TEST_PORT}" \
    --config-path "${TEST_TMPDIR}/config.php" \
    --content-match "Log in to the site" \
    --db-ping-command "true" \
    --db-query-command "printf 489"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"HTTP probe returned 200"* ]]
  [[ "${output}" == *"Moodle database contains 489 tables"* ]]
}
