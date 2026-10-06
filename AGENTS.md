# Repository Guidelines

Use this file for durable, concise guidance for coding agents in this repository.

- Before changing code, read `README.md` and the nearest package/build manifest for the commands and constraints that apply.
- Add confirmed project-specific commands, conventions, and constraints here when they become durable.

## How laemp.sh is built

`laemp.sh` is one Bash script (about 4,500 lines, `set -euo pipefail`) that installs LAMP/LEMP plus Moodle on Ubuntu or Debian only; `detect_distro_and_codename` reads `/etc/os-release` and exits elsewhere. Find code by function name, not line number.

| Area | Functions |
| --- | --- |
| Logging and execution | `log`, `run_command`, `run_sensitive_command`, `tool_exists`, `download_file`, `is_container`, `service_manage` |
| Packages | `package_manager_ensure`, `package_ensure`, `repository_ensure` (ondrej PPAs on Ubuntu, packages.sury.org on Debian) |
| Credentials | `load_or_create_database_password`, `write_moodle_admin_credentials`, `publish_private_credentials` |
| Certificates | `acme_cert_request`, `self_signed_cert_request`, `mkcert_cert_request`, `get_cert_path`, `validate_certificates` |
| Web servers | `apache_ensure`, `apache_create_vhost`, `nginx_ensure`, `nginx_create_optimized_config`, `nginx_create_vhost` |
| PHP | `php_ensure`, `php_extensions_ensure`, `php_configure_for_moodle`, `php_fpm_create_pool` |
| Moodle | `moodle_validate_php_version`, `moodle_validate_database_version`, `moodle_download_extract`, `moodle_config_files`, `moodle_install_database`, `setup_moodle_cron`, `moodle_ensure` |
| Databases | `mariadb_ensure`, `postgres_ensure` (PGDG repository; PostgreSQL 16, or 17 for Moodle 5.3) |
| Extras | `memcached_ensure`, `prometheus_ensure` and its exporters |
| Entry point | `main` parses options and runs the `*_ENSURE` steps in order |

Conventions that matter when editing:

- Every state-changing command goes through `run_command --makes-changes`, which skips it under `-n` (dry run, `DRY_RUN_CHANGES`). New code that writes, installs, or downloads must do the same, and anything that reads its result must tolerate the dry-run case.
- `log` has error, info, verbose, and debug levels; each run also writes a timestamped file under `logs/`.
- Re-runs must be idempotent: check before creating, and never rotate an existing password. Database passwords live in `/var/lib/laemp/credentials/` and the admin login in `/var/lib/laemp/moodle-admin-credentials.env` (`LAEMP_STATE_DIR` overrides the root).
- Moodle version codes: `5024` is the tagged 5.2.4 package, `5030` is 5.3.0 (`moodle-5.3.tgz`), and three-digit codes such as `503` fetch the weekly `moodle-latest-NNN` build. Pinned releases are checksum-verified from `MOODLE_KNOWN_RELEASES`.
- `main` refuses incompatible PHP and database versions before provisioning starts (`moodle_validate_php_version`, `moodle_validate_database_version`).
- Monitoring (`-r`) runs Prometheus on 9090 with exporters on 9100 (node), 9113 (nginx), 9117 (Apache) and 9253 (PHP-FPM).
- `--skip-db-server` skips installing a database server, for runs against an existing one. In containers, `service_manage` uses `is_container` to start daemons directly instead of through systemd.
- Test platforms live under `platforms/` (docker, lima, slicervm); `tests/docker` and `tests/slicer` are shims that forward there.

## Codex workflow

- Keep this file short, concrete, and repo-specific. Capture layout, commands, conventions, constraints, and done criteria; move repeatable procedures to scoped skills/docs.
- For each task, state the goal, relevant context/files, constraints, and verification criteria. Plan complex or ambiguous work before editing.
- Keep one thread per coherent outcome. Read only relevant files; delegate bounded exploration/tests when useful, and use worktrees for parallel work.
- Verify changes with focused tests and applicable lint, formatting, type checks, builds, and diff review; report checks run or skipped.
- Prefer least-privilege permissions and dry-runs. Add MCP/tools only when they remove a real repeated loop.
- Use background or scheduled work for long-running or recurring tasks instead of continuous polling.
- After a repeated mistake or correction, update this file with the smallest actionable rule that would prevent it.

Reference: https://learn.chatgpt.com/guides/best-practices
