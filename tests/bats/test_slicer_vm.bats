#!/usr/bin/env bats

setup() {
  command -v jq >/dev/null || skip 'jq is required'
  source "$BATS_TEST_DIRNAME/../../platforms/slicervm/lib.sh"
}

@test "Slicer finds the requested VM address independently of display columns" {
  slicer() {
    [[ "$*" == *--json* ]] || return 1
    printf '%s\n' '[{"hostname":"sbox-2","name":"other","ip":"192.168.64.4"},{"hostname":"sbox-1","ip":"192.168.64.3"}]'
  }
  run slicer_vm_ip sbox-1
  [ "$status" -eq 0 ]
  [ "$output" = 192.168.64.3 ]
}

@test "Slicer rejects a VM with no assigned address" {
  slicer() { printf '%s\n' '[{"hostname":"sbox-1","ip":"-"}]'; }
  run slicer_vm_ip sbox-1
  [ "$status" -ne 0 ]
  [[ "$output" == *'could not find an IPv4 address'* ]]
}

@test "Slicer reads the private credential file as root without splitting values" {
  eval "$(sed -n '/^function read_admin_credentials_from_vm() {/,/^}/p' "$BATS_TEST_DIRNAME/../../platforms/slicervm/run-matrix.sh")"
  ADMIN_CREDENTIALS_FILE="$BATS_TEST_TMPDIR/credentials.env"
  printf "%s\n" "MOODLE_ADMIN_USERNAME=fixture" "MOODLE_ADMIN_PASSWORD='test password'" > "$ADMIN_CREDENTIALS_FILE"
  slicer() {
    [[ "$*" == *'--uid 0 -- '* ]] || return 1
    bash -c "${!#}"
  }
  run read_admin_credentials_from_vm sbox-1
  [ "$status" -eq 0 ]
  [ "$output" = $'fixture\ttest password' ]
}
