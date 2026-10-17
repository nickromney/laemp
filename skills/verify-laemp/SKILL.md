---
name: verify-laemp
description: Verify the laemp installer CLI safely and check an already-running Moodle site over HTTP, PHP asset routes, and its database.
---

# Verify laemp

This skill checks the laemp installer's documented dry-run command and, when a real Moodle target is configured, runs the existing `verify-moodle.sh` HTTP, PHP asset, and database checks against that site. It does not provision a Moodle stack. The installer itself supports Ubuntu and Debian, so `doctor` refuses other hosts before the dry-run command can run.

## Configure a live Moodle target

Set `LAEMP_VERIFY_URL` to the existing site's URL and `LAEMP_VERIFY_CONFIG_PATH` to its readable `config.php`. The verifier reads database settings from that file. Optional settings are `LAEMP_VERIFY_BACKEND`, `LAEMP_VERIFY_DATABASE`, `LAEMP_VERIFY_PHP_RUNTIME`, and `LAEMP_VERIFY_TABLE_MIN` (default 400). Never put database passwords in command arguments; `verify-moodle.sh` reads the password from `config.php`.

## Commands

From the repository root:

```sh
make verify-dry-run
make verify-test
make verify
```

The full cycle first checks for an Ubuntu or Debian host, `curl`, a configured Moodle URL, and a readable Moodle config. It then runs the existing non-mutating installer command `./laemp.sh -n -v -p 8.4 -w nginx -d mariadb -m 5024 -S`, followed by `verify-moodle.sh` against the configured live site. The installer dry run checks the CLI plan; only the Moodle verifier checks a live service. A source-level or fixture-only pass does not establish live Moodle behavior.

## Evidence and cleanup

Run state defaults to `$TMPDIR/verify-laemp/<run-id>` and evidence to `$TMPDIR/verify-laemp-evidence/<run-id>`. Override them with `VERIFY_BASE_DIR`, `VERIFY_EVIDENCE_ROOT`, and `VERIFY_RUN_ID`. Evidence contains the host preflight, installer dry-run output, Moodle verifier output, and the source revision. Cleanup removes only this run's state and keeps evidence. It does not stop containers or services because this skill does not start them.

If `make verify` fails on macOS, the retained `doctor.log` records that the installer requires Ubuntu or Debian. That refusal occurs before the installer dry run, even when `curl` and other host tools are available.
