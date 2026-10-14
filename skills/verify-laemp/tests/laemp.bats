#!/usr/bin/env bats

setup() {
  SKILL_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$SKILL_DIR/scripts/control.sh"
  BASH32="${VERIFY_TEST_BASH:-/bin/bash}"
  export VERIFY_BASE_DIR="$BATS_TEST_TMPDIR/base"
  export VERIFY_EVIDENCE_ROOT="$BATS_TEST_TMPDIR/evidence"
  export VERIFY_RUN_ID="laemp-refusal"
  export LAEMP_VERIFY_URL="https://moodle.invalid"
  export LAEMP_VERIFY_CONFIG_PATH="$BATS_TEST_TMPDIR/config.php"
  printf '%s\n' '<?php' >"$LAEMP_VERIFY_CONFIG_PATH"
}

@test "unsupported host doctor refuses before installer dry run even when curl is available" {
  if [ "$(uname -s)" = Linux ]; then
    skip "this host may be supported; the macOS rollout runner is the refusal case"
  fi
  command -v curl >/dev/null 2>&1 || skip "curl is not installed; refusal order cannot be demonstrated"

  run "$BASH32" "$SCRIPT" --execute launch

  [ "$status" -ne 0 ]
  [[ "$output" == *"supports Ubuntu and Debian Linux"* ]]
  [ -f "$VERIFY_EVIDENCE_ROOT/$VERIFY_RUN_ID/doctor.log" ]
  [ ! -e "$VERIFY_BASE_DIR/$VERIFY_RUN_ID/state" ]
  [ ! -e "$VERIFY_EVIDENCE_ROOT/$VERIFY_RUN_ID/installer-dry-run.log" ]
}

@test "doctor cannot pass before this run records launch readiness" {
  run "$BASH32" "$SCRIPT" --execute doctor

  [ "$status" -ne 0 ]
  [[ "$output" == *"no laemp launch recorded for run"* ]]
  [ ! -e "$VERIFY_BASE_DIR/$VERIFY_RUN_ID/state/launch-ready" ]
}
