#!/usr/bin/env bats

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  # Exercise the actual acceptance function with synthetic container responses.
  eval "$(sed -n '/^function verify_case() {/,/^}$/p' platforms/docker/run-matrix.sh)"
  SITE_HOST=fixture.test
  format_url() { printf '%s://%s:%s' "$1" "$2" "$3"; }
  docker_exec_root_shell() {
    case "$2" in
      *'select count('* ) printf '489\n' ;;
      *curl*) printf 'HTTP/1.1 200 OK\n' ;;
    esac
  }
  tls_preflight_check_url() { return 0; }
  curl() {
    if [[ "$1" == -sSI ]]; then
      printf 'HTTP/1.1 301 Moved Permanently\nLocation: https://fixture.test:18543/\n'
    else
      printf 'HTTP/1.1 200 OK\n'
    fi
  }
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "Docker verification rejects failed TLS even when database tables exist" {
  tls_preflight_check_url() { return 1; }
  if verify_case fixture nginx mariadb 18180 18543 "$TEST_TMPDIR"; then
    echo 'verification accepted failed TLS' >&2
    return 1
  fi
}

@test "Docker verification rejects redirect to the wrong published port" {
  curl() { printf 'HTTP/1.1 301 Moved Permanently\nLocation: https://fixture.test/\n'; }
  if verify_case fixture nginx mariadb 18180 18543 "$TEST_TMPDIR"; then
    echo 'verification accepted wrong redirect' >&2
    return 1
  fi
}

@test "Docker verification accepts successful service HTTP TLS and database probes" {
  verify_case fixture nginx mariadb 18180 18543 "$TEST_TMPDIR"
  [ "$(cat "$TEST_TMPDIR/table_count.txt")" = 489 ]
}
