# laemp

`laemp.sh` installs LAMP or LEMP plus Moodle on Ubuntu and Debian. The script targets real Linux hosts, so this repo keeps two complementary test paths:

- Slicer VMs for VM-faithful validation with `systemd`, real package lifecycle, and real service startup.
- Docker or Podman containers for broadly available bootstrap and last-mile testing.

Repo-managed testing uses distinct browser hosts so Docker and Slicer runs do not collide:

- Docker test HTTP URL: `http://moodle.docker.test.127.0.0.1.sslip.io`
- Docker test HTTPS URL: `https://moodle.docker.test.127.0.0.1.sslip.io`
- Slicer test host: `moodle.slicer.test.<vm-ip>.sslip.io`
- Example current Slicer host: `moodle.slicer.test.192.168.64.2.sslip.io`

Docker-published test ports bind to `127.0.0.1` by default, not `0.0.0.0`. If you intentionally want a non-loopback bind, set `LAEMP_DOCKER_BIND_HOST` to one explicit address such as a Slicer VM IP.

`laemp.sh` itself still keeps its generic defaults so normal VPS installs can supply a real deployable domain.

## Quick Start

```bash
# Show help
./laemp.sh -h

# Dry run
./laemp.sh -n -v -p 8.4 -w nginx -d mariadb -m 5013 -S

# Full local install on Ubuntu/Debian
sudo ./laemp.sh -c -p 8.4 -w nginx -d mariadb -m 5013 -S

# Full local install with an explicit admin password
sudo MOODLE_ADMIN_PASSWORD='AdminPass123!' ./laemp.sh -c -p 8.4 -w nginx -d mariadb -m 5013 -S

# Full local install with PostgreSQL, memcached, and monitoring
sudo ./laemp.sh -c -p 8.4 -w nginx -d pgsql -m 5013 -S -M -r

# Locally trusted certificate inside the guest
sudo ./laemp.sh -c -p 8.4 -w nginx -d mariadb -m 5013 --mkcert
```

Successful installs write admin credentials to `/var/lib/laemp/moodle-admin-credentials.env`. Set `MOODLE_ADMIN_PASSWORD` up front if you want a fixed password instead of a generated one. `laemp.sh` also accepts `MOODLE_ADMIN_USER` as an alias for the admin username, matching `frankenphp-moodle`.

## Test Strategy

### 1. Fast host-side checks

```bash
bats tests/bats/test_smoke.bats
bats tests/bats/test_laemp.bats
```

These cover syntax, help text, dry-run behavior, and CLI parsing.

### 2. Container testing for broad accessibility

Use Docker or Podman when you want something most contributors can run quickly.

```bash
# Fastest end-to-end Docker check
make docker-baseline

# Explicit non-loopback bind when you intentionally want one
LAEMP_DOCKER_BIND_HOST=192.168.64.3 LAEMP_DOCKER_HTTP_PORT=18080 LAEMP_DOCKER_HTTPS_PORT=18443 make docker-baseline

# Broader stock-image integration coverage
docker build -f docker/Dockerfile.ubuntu -t laemp-ubuntu:24.04 .
docker build -f docker/Dockerfile.debian -t laemp-debian:13 .
CONTAINER_RUNTIME=docker bats tests/bats/test_integration.bats
```

The prereqs images are for last-mile configuration testing:

```bash
docker build -f docker/Dockerfile.prereqs.ubuntu -t laemp-prereqs-ubuntu .
docker build -f docker/Dockerfile.prereqs.debian -t laemp-prereqs-debian .
```

Docker paths use the host's native architecture by default. If you intentionally want cross-arch coverage, set `DOCKER_PLATFORM` or `CONTAINER_PLATFORM` explicitly.

### 3. Slicer for VM-faithful validation

Use Slicer when you need VM-faithful validation against a real Ubuntu-like guest.

```bash
# One proven fresh-VM baseline
make slicer

# One supported combo with Playwright smoke
tests/slicer/run-matrix.sh --php 8.4 --web nginx --moodle 5013

# Full supported Slicer matrix
make slicer-matrix
```

The Slicer harness uses the system daemon at `~/slicer-mac`, not repo-local runtime state.
The Docker and Slicer test harnesses default to `admin` / `AdminPass123!` unless you override `MOODLE_ADMIN_PASSWORD`.
`laemp.sh` now hardens remote archive downloads as well: `curl`/`wget` retry, and `.tgz`/`.tar.gz` payloads must pass `gzip -t` before they are reused or extracted. This came from a real Slicer failure where a Moodle 4.5 archive request returned a tiny non-gzip payload and previously failed later under `tar`.

## Docker vs Slicer

They are not substitutes for one another.

- Docker or Podman is the accessible path. It is the right place to test bootstrap logic, stock images, prereqs images, and external-database container flows.
- Slicer is the VM-faithful path. It is the right place to test `systemd`, package post-install behavior, in-guest `mkcert`, Prometheus exporters, and end-to-end Ubuntu behavior.

Current repo state reflects that split:

- `tests/slicer/run-matrix.sh` is the canonical VM matrix runner.
- `tests/docker/run-baseline.sh` is the canonical container baseline runner.
- `tests/bats/test_integration.bats` is the canonical stock-image container runner.
- `compose.yml` defaults to the Debian systemd container plus PostgreSQL only. The MariaDB-backed Server Side Up comparison path is opt-in via the `serversideup` profile.

## Documentation

- [`tests/README.md`](tests/README.md): test entry points and what each tier proves.
- [`docs/container-testing.md`](docs/container-testing.md): container-first testing workflow and constraints.
- [`docs/dockerfile-prereqs.md`](docs/dockerfile-prereqs.md): stock vs prereqs image model.
- [`docs/roadmap.md`](docs/roadmap.md): active follow-up work.
