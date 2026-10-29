#!/usr/bin/env bats
# Bats isolates each @test in a subshell, and each test runs sourced functions.
# shellcheck disable=SC2030,SC2031

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  export PHP_FIXTURE_BIN="$TEST_TMPDIR/bin"
  mkdir -p "$PHP_FIXTURE_BIN"
  awk '/^# Script evaluation starts here$/ { exit } { print }' ./laemp.sh > "$TEST_TMPDIR/functions.sh"
  # shellcheck disable=SC1091
  source "$TEST_TMPDIR/functions.sh"
  export PATH="$PHP_FIXTURE_BIN:$PATH"
  export LOG_LEVEL=info
  export log_to_file=false
  export DISTRO=Debian
  export CODENAME=trixie
  export PHP_VERSION_MAJOR_MINOR=8.4
  export PHP_ALONGSIDE=true
  export SKIP_PACKAGE_INSTALLS=false
  export DRY_RUN_CHANGES=false
  export MOCK_PACKAGE_VERSION=8.4.27-1
  export MOCK_CLI_VERSION=8.4.27
  export MOCK_FPM_VERSION=8.4.27
  export MOCK_OWNERSHIP_MISMATCH=false

  cat > "$PHP_FIXTURE_BIN/php8.4" <<'EOF'
#!/usr/bin/env bash
printf 'PHP %s (cli) (fixture)\n' "$MOCK_CLI_VERSION"
EOF
  cat > "$PHP_FIXTURE_BIN/php-fpm8.4" <<'EOF'
#!/usr/bin/env bash
printf 'PHP %s (fpm-fcgi) (fixture)\n' "$MOCK_FPM_VERSION"
EOF
  chmod +x "$PHP_FIXTURE_BIN/php8.4" "$PHP_FIXTURE_BIN/php-fpm8.4"

  # shellcheck disable=SC2329
  dpkg-query() {
    local action="$1" package="${2:-}" path binary branch owner
    case "$action" in
      -W)
        case "${!#}" in
          *-fpm) printf 'installed %s\n' "${MOCK_FPM_PACKAGE_VERSION:-$MOCK_PACKAGE_VERSION}" ;;
          *) printf 'installed %s\n' "$MOCK_PACKAGE_VERSION" ;;
        esac
        ;;
      -S)
        path="$package"
        binary="$(basename "$path")"
        if [[ "$binary" == php-fpm* ]]; then
          branch="${binary#php-fpm}"
          owner="php${branch}-fpm"
        else
          branch="${binary#php}"
          [[ "$branch" == "$binary" ]] && branch="$PHP_VERSION_MAJOR_MINOR"
          owner="php${branch}-cli"
        fi
        [[ "$MOCK_OWNERSHIP_MISMATCH" == true ]] && owner=wrong-package
        printf '%s: %s\n' "$owner" "$path"
        ;;
      --control-show)
        package="$2"
        case "$package" in
          php*-fpm) binary="php-fpm${package#php}"; binary="${binary%-fpm}" ;;
          *) binary="php${package#php}"; binary="${binary%-cli}" ;;
        esac
        path="$(readlink -f -- "$(command -v "$binary")")"
        printf '%s %s\n' "${MOCK_RECORDED_CHECKSUM:-$(md5sum -- "$path" | awk '{print $1}')}" "${path#/}"
        ;;
      *)
        return 2
        ;;
    esac
  }
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "PHP 8.4 CLI and FPM pass when both selected executables are patched and package-owned" {
  run php_security_verify_fpm
  [ "$status" -eq 0 ]
  [[ "$output" == *"Verified php8.4 PHP 8.4.27 security floor"* ]]
  [[ "$output" == *"Verified php-fpm8.4 PHP 8.4.27 security floor"* ]]
}

@test "PHP 8.4 CLI below the fixed patch floor is rejected" {
  MOCK_CLI_VERSION=8.4.26
  run php_security_verify_binary php8.4
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected patched PHP 8.4"* ]]
}

@test "PHP FPM must match the selected CLI version" {
  MOCK_FPM_VERSION=8.4.28
  MOCK_FPM_PACKAGE_VERSION=8.4.28-1
  run php_security_verify_fpm
  [ "$status" -eq 1 ]
  [[ "$output" == *"PHP CLI 8.4.27 and FPM 8.4.28 do not match"* ]]
}

@test "selected runtime must match its installed package version" {
  MOCK_PACKAGE_VERSION=8.4.26-1
  run php_security_verify_fpm
  [ "$status" -ne 0 ]
  MOCK_PACKAGE_VERSION=8.4.27~rc1-1
  run php_security_verify_fpm
  [ "$status" -ne 0 ]
  MOCK_PACKAGE_VERSION=1:8.4.27-1~deb13u1
  run php_security_verify_fpm
  [ "$status" -eq 0 ]
}

@test "selected PHP executable is rejected when a different package claims ownership" {
  MOCK_OWNERSHIP_MISMATCH=true
  run php_security_verify_binary php8.4
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not owned by php8.4-cli"* ]]
}

@test "selected PHP executable must match the recorded package checksum" {
  MOCK_RECORDED_CHECKSUM=ffffffffffffffffffffffffffffffff
  run php_security_verify_binary php8.4
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match"* ]]
}

@test "Ubuntu 24.04's PHP 8.3 backport passes only with the exact patched package and executable checksum" {
  export DISTRO=Ubuntu
  export CODENAME=noble
  export PHP_VERSION_MAJOR_MINOR=8.3
  MOCK_PACKAGE_VERSION=8.3.6-0ubuntu0.24.04.13
  MOCK_CLI_VERSION=8.3.6
  mv "$PHP_FIXTURE_BIN/php8.4" "$PHP_FIXTURE_BIN/php8.3"

  run php_security_verify_backport php8.3 8.3.6
  [ "$status" -eq 0 ]
}

@test "Ubuntu PHP 8.3 backport is rejected when the package revision is below USN-8948" {
  export DISTRO=Ubuntu
  export CODENAME=noble
  export PHP_VERSION_MAJOR_MINOR=8.3
  MOCK_PACKAGE_VERSION=8.3.6-0ubuntu0.24.04.12
  MOCK_CLI_VERSION=8.3.6
  mv "$PHP_FIXTURE_BIN/php8.4" "$PHP_FIXTURE_BIN/php8.3"

  run php_security_verify_backport php8.3 8.3.6
  [ "$status" -eq 1 ]
}

@test "Ubuntu 24.04's patched PHP 8.3 FPM backport is accepted by its package checksum" {
  export DISTRO=Ubuntu
  export CODENAME=noble
  export PHP_VERSION_MAJOR_MINOR=8.3
  MOCK_PACKAGE_VERSION=8.3.6-0ubuntu0.24.04.13
  MOCK_FPM_VERSION=8.3.6
  mv "$PHP_FIXTURE_BIN/php-fpm8.4" "$PHP_FIXTURE_BIN/php-fpm8.3"

  run php_security_verify_backport php-fpm8.3 8.3.6
  [ "$status" -eq 0 ]
}

@test "php_ensure refuses success from an already-installed vulnerable default CLI" {
  export PHP_ALONGSIDE=false
  MOCK_CLI_VERSION=8.4.26
  cp "$PHP_FIXTURE_BIN/php8.4" "$PHP_FIXTURE_BIN/php"
  tool_exists() { return 0; }
  package_ensure() { echo "unexpected package install" >&2; return 99; }

  run php_ensure
  [ "$status" -eq 1 ]
  [[ "$output" != *"unexpected package install"* ]]
}
