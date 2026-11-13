#!/usr/bin/env bats

setup() {
  eval "$(sed -n '/^function acme_cert_request() {/,/^}$/p' laemp.sh)"
  log() { :; }
  tool_exists() { return 0; }
  package_ensure() { return 1; }
  run_command() { printf '%s\n' "$@"; }
}

@test "ACME request includes every SAN as a separate domain" {
  run acme_cert_request --domain example.com --email admin@example.com --san 'www.example.com,sub.example.com' --challenge http
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' --makes-changes certbot --apache -d example.com --expand --cert-name example.com -d www.example.com -d sub.example.com -m admin@example.com --agree-tos --non-interactive --preferred-challenges http --server https://acme-staging-v02.api.letsencrypt.org/directory)" ]
}

@test "ACME request without SAN requests only the primary domain" {
  run acme_cert_request --domain example.com --email admin@example.com
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' --makes-changes certbot --apache -d example.com -m admin@example.com --agree-tos --non-interactive --preferred-challenges dns --server https://acme-staging-v02.api.letsencrypt.org/directory)" ]
}
