#!/usr/bin/env bats

setup() {
  eval "$(sed -n '/^function verify_external_access() {/,/^}/p; /^function verify_stack_in_vm() {/,/^}/p' "$BATS_TEST_DIRNAME/../../platforms/lima/run-matrix.sh")"
  SITE_HOST=fixture.test
  DB_TYPE=mariadb
  lima_shell_bash() { return 0; }
  lima_shell_root_bash() {
    case "$2" in
      *'select count('* ) printf '489\n' ;;
      /tmp/verify-moodle.sh*) [[ "$2" == *'--config-path /var/www/html/fixture.test/config.php' ]] ;;
    esac
  }
  curl() {
    if [[ "$1" == -sSI ]]; then
      printf 'HTTP/1.1 301 Moved Permanently\nLocation: https://fixture.test/\n'
    else
      printf 'HTTP/1.1 200 OK\n'
    fi
  }
}

@test "Lima verifies the installed site's Moodle configuration" {
  verify_stack_in_vm fixture nginx "$BATS_TEST_TMPDIR"
  [ "$(cat "$BATS_TEST_TMPDIR/table_count.txt")" = 489 ]
}

@test "Lima rejects a wrong HTTP redirect even when the database is populated" {
  curl() { printf 'HTTP/1.1 301 Moved Permanently\nLocation: https://wrong.test/\n'; }
  if verify_stack_in_vm fixture nginx "$BATS_TEST_TMPDIR"; then
    false
  fi
}
