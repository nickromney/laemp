#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  awk '/^# Script evaluation starts here$/ { exit } { print }' ./laemp.sh > "$TEST_TMPDIR/functions.sh"
  # shellcheck disable=SC1091
  source "$TEST_TMPDIR/functions.sh"
  log_to_file=false
  USE_SUDO=false
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "APT repositories for PHP Apache and PostgreSQL use distinct files" {
  package_manager=apt
  run_command() {
    [[ "$1" == --makes-changes ]] || return 1
    shift
    printf '%s\n' "$*" >> "$TEST_TMPDIR/commands"
  }
  repository_ensure 'deb https://packages.sury.org/php/ trixie main' \
    'deb https://packages.sury.org/apache2/ trixie main' \
    'deb [arch=arm64 signed-by=/etc/apt/keyrings/postgresql.asc] http://apt.postgresql.org/pub/repos/apt trixie-pgdg main'
  grep -q '/packages-sury-org-php.list' "$TEST_TMPDIR/commands"
  grep -q '/packages-sury-org-apache2.list' "$TEST_TMPDIR/commands"
  grep -q '/apt-postgresql-org-pub-repos-apt.list' "$TEST_TMPDIR/commands"
  ! grep -q '/deb.list' "$TEST_TMPDIR/commands"
}

@test "failed downloader cannot publish a nonempty partial file" {
  tool_exists() { [[ "$1" == wget ]]; }
  wget() { printf partial > "$5"; return 1; }
  sleep() { :; }
  printf original > "$TEST_TMPDIR/key.asc"
  run download_file https://example.test/key.asc "$TEST_TMPDIR/key.asc"
  [ "$status" -ne 0 ]
  [ "$(cat "$TEST_TMPDIR/key.asc")" = original ]
  [ ! -e "$TEST_TMPDIR/key.asc.tmp" ]
}

@test "successful downloader publishes the completed file" {
  tool_exists() { [[ "$1" == curl ]]; }
  curl() { printf complete > "${9}"; }
  download_file https://example.test/key.asc "$TEST_TMPDIR/key.asc"
  [ "$(cat "$TEST_TMPDIR/key.asc")" = complete ]
}

@test "dry-run download succeeds without invoking a downloader or touching files" {
  DRY_RUN_CHANGES=true
  tool_exists() { return 99; }
  printf existing > "$TEST_TMPDIR/key.asc.tmp"
  download_file https://example.test/key.asc "$TEST_TMPDIR/key.asc"
  [ "$(cat "$TEST_TMPDIR/key.asc.tmp")" = existing ]
  [ ! -e "$TEST_TMPDIR/key.asc" ]
}

@test "download publication failure remains a failure inside a conditional" {
  tool_exists() { [[ "$1" == wget ]]; }
  wget() { printf complete > "$5"; }
  mv() { return 1; }
  if download_file https://example.test/key.asc "$TEST_TMPDIR/key.asc"; then
    echo 'download reported success after failed rename' >&2
    return 1
  fi
  [ ! -e "$TEST_TMPDIR/key.asc" ]
}

@test "nginx redirect uses public Moodle port while listening on the container port" {
  nginx_verify() { :; }
  get_fastcgi_pass() { printf 'unix:/run/php/fixture.sock'; }
  write_file() { cat > "$TEST_TMPDIR/vhost"; }
  run_command() { :; }
  LAEMP_HTTP_PORT=80
  LAEMP_HTTPS_PORT=443
  nginxHttpPort=80
  nginxPort=443
  moodlePort=:18543
  declare -A fixture_config=(
    [site_name]=fixture.test [document_root]=/var/www/fixture
    [admin_email]=admin@fixture.test [ssl_cert_file]=/tmp/cert [ssl_key_file]=/tmp/key
  )
  nginx_create_vhost fixture_config
  grep -Fq 'listen 443 ssl;' "$TEST_TMPDIR/vhost"
  grep -Fq 'return 301 https://$host:18543$request_uri;' "$TEST_TMPDIR/vhost"
  grep -Fq 'fastcgi_param SERVER_PORT 18543;' "$TEST_TMPDIR/vhost"
}

@test "Apache redirect includes the published HTTPS port without changing its listener" {
  apache_verify() { :; }
  write_file() { cat > "$TEST_TMPDIR/vhost"; }
  run_command() { :; }
  moodlePort=:18543
  declare -A fixture_config=(
    [site_name]=fixture.test [document_root]=/var/www/fixture
    [admin_email]=admin@fixture.test [ssl_cert_file]=/tmp/cert [ssl_key_file]=/tmp/key
    [include_file]=''
  )
  apache_create_vhost fixture_config
  grep -Fxq '<VirtualHost *:443>' "$TEST_TMPDIR/vhost"
  grep -Fq 'Redirect permanent / https://fixture.test:18543/' "$TEST_TMPDIR/vhost"
}

@test "PPA registration retries a failed Launchpad request" {
  package_manager=apt
  attempts=0
  add-apt-repository() { :; }
  sleep() { :; }
  run_command() {
    case "$2" in
      add-apt-repository)
        attempts=$((attempts + 1))
        [[ "$attempts" -ge 2 ]]
        ;;
      apt-get) [[ "$attempts" -eq 2 ]] ;;
      *) return 1 ;;
    esac
  }
  repository_ensure ppa:ondrej/php
  [ "$attempts" -eq 2 ]
}
