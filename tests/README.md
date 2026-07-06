# Testing Guide

This repo uses both containers and VMs because they answer different questions.

- Containers are the widely available path. Use them for fast bootstrap and last-mile checks.
- Lima VMs are a lighter local VM path on macOS, using loopback-only host exposure.
- Slicer VMs are the VM-faithful path. Use them for real Ubuntu behavior, `systemd`, exporter wiring, guest trust stores, and browser smoke against a live guest.

## Test Tiers

### 1. Smoke tests

Fast host-side validation.

```bash
bats tests/bats/test_smoke.bats
```

Covers script shape, syntax, help output, and basic static checks.

### 2. CLI parsing tests

Host-side BATS tests that exercise dry-run parsing and option combinations.

```bash
bats tests/bats/test_laemp.bats
```

### 3. Docker baseline

The first Docker path to reach for is the Slicer-proven baseline: Debian stock image, PHP 8.4, nginx, MariaDB, Moodle 5.2.1/stable502, self-signed TLS.

```bash
make docker-baseline
make docker-matrix
```

This runner builds the stock Debian image if needed, starts an isolated container, executes `laemp.sh`, and writes logs plus verification artifacts to `/tmp`.
Published Docker ports bind to `127.0.0.1` by default through `LAEMP_DOCKER_BIND_HOST`.

### 4. Container integration tests

For broader stock-image coverage, use the BATS integration suite.

```bash
docker build -f docker/Dockerfile.ubuntu -t laemp-ubuntu:24.04 .
docker build -f docker/Dockerfile.debian -t laemp-debian:13 .
CONTAINER_RUNTIME=docker bats tests/bats/test_integration.bats
```

If you use Podman instead:

```bash
podman build -f docker/Dockerfile.ubuntu -t laemp-ubuntu:24.04 .
podman build -f docker/Dockerfile.debian -t laemp-debian:13 .
CONTAINER_RUNTIME=podman bats tests/bats/test_integration.bats
```

Container paths use the host's native architecture by default. Set `CONTAINER_PLATFORM` explicitly only when you intentionally want cross-arch coverage.

### 5. Browser tests against a running target

The Playwright suite assumes Moodle is already up.

```bash
npm install
npx playwright install chromium

# Then point Playwright at a running site
MOODLE_URL=https://moodle.docker.test.127.0.0.1.sslip.io \
MOODLE_HTTP_URL=http://moodle.docker.test.127.0.0.1.sslip.io \
npm test
```

Set credentials through environment variables or `.env.test.local`. Fresh installs now write a stable credentials file at `/var/lib/laemp/moodle-admin-credentials.env`, so you do not need to scrape logs. The Docker and Slicer matrix harnesses default to `admin` / `AdminPass123!` unless you override `MOODLE_ADMIN_PASSWORD`. `laemp.sh` accepts both `MOODLE_ADMIN_USERNAME` and the `frankenphp-moodle` style alias `MOODLE_ADMIN_USER`.

```bash
MOODLE_ADMIN_USERNAME=admin
MOODLE_ADMIN_PASSWORD=...
MOODLE_ADMIN_EMAIL=demo@moodle.docker.test
MOODLE_URL=https://moodle.docker.test.127.0.0.1.sslip.io
MOODLE_HTTP_URL=http://moodle.docker.test.127.0.0.1.sslip.io
```

Examples:

```bash
docker compose exec -T moodle-test-debian cat /var/lib/laemp/moodle-admin-credentials.env
slicer vm exec sbox-1 --url "$HOME/slicer-mac/slicer.sock" --uid 1000 -- 'sudo cat /var/lib/laemp/moodle-admin-credentials.env'
limactl shell laemp-moodle-php8-4-nginx-moodle5021-mariadb sudo cat /var/lib/laemp/moodle-admin-credentials.env
```

### 6. Lima matrix plus Playwright smoke

Provision a fresh Lima VM per combo, run `laemp.sh`, then run Playwright smoke against `moodle.lima.test.127.0.0.1.sslip.io`.

```bash
npm install
npx playwright install chromium

platforms/lima/run-matrix.sh
platforms/lima/run-matrix.sh --php 8.4 --web nginx --moodle 50211
```

The repo also exposes:

```bash
make lima
make lima-matrix
```

### 7. Slicer matrix plus Playwright smoke

Provision a fresh VM per combo, run `laemp.sh`, then run Playwright smoke against the live guest.

```bash
npm install
npx playwright install chromium

platforms/slicervm/run-matrix.sh
platforms/slicervm/run-matrix.sh --php 8.4 --web nginx --moodle 50211
platforms/slicervm/run-matrix.sh --php 8.4 --web nginx --moodle 50211 --database pgsql --extra-flag -M
```

The repo also exposes:

```bash
make slicer
make slicer-matrix
```

## Compose Notes

`compose.yml` is useful for the current Debian systemd container and its PostgreSQL sidecar by default. The MariaDB-backed Server Side Up comparison path is opt-in through the `serversideup` profile.

Today it is not a full stock Ubuntu matrix. If you want broad Docker coverage, use:

- `tests/bats/test_integration.bats` for stock-image runs
- the prereqs Dockerfiles for last-mile container runs
- `compose.yml` where you specifically want the Debian systemd + PostgreSQL flow, or the opt-in Server Side Up profile

## What Each Path Proves

- `tests/bats/test_smoke.bats`: script integrity and obvious regressions
- `tests/bats/test_laemp.bats`: CLI surface and dry-run behavior
- `platforms/docker/run-baseline.sh`: one honest end-to-end container bootstrap
- `platforms/lima/run-matrix.sh`: one honest VM-backed local Lima matrix
- `tests/bats/test_integration.bats`: container bootstrap behavior on stock images
- Playwright: user-facing Moodle behavior against a running target
- `platforms/slicervm/run-matrix.sh`: real Ubuntu provisioning behavior on Slicer

## Troubleshooting

### Container tests fail early

```bash
docker ps -a
docker rm -f $(docker ps -a --filter name=laemp-test -q)
```

For Podman:

```bash
podman ps -a
podman rm -f $(podman ps -a --filter name=laemp-test -q)
```

### Playwright cannot connect

Check the exact URL being tested.

```bash
echo "$MOODLE_URL"
curl -k "$MOODLE_URL"
```

For test harness runs, prefer the split host pattern:

- Docker HTTP: `http://moodle.docker.test.127.0.0.1.sslip.io`
- Docker HTTPS: `https://moodle.docker.test.127.0.0.1.sslip.io`
- Lima HTTPS: `https://moodle.lima.test.127.0.0.1.sslip.io`
- Slicer: `https://moodle.slicer.test.<vm-ip>.sslip.io`
- Current `slicer-1` example: `https://moodle.slicer.test.192.168.64.2.sslip.io`

When you need a non-loopback Docker bind, keep it explicit rather than wildcard:

- Local default: `LAEMP_DOCKER_BIND_HOST=127.0.0.1`
- Slicer-style explicit bind: `LAEMP_DOCKER_BIND_HOST=192.168.64.3`

### Slicer tests fail

Use the system daemon under `~/slicer-mac` and inspect the per-run artifacts emitted by `platforms/slicervm/run-matrix.sh`.

If a run dies during Moodle download or extraction with output like `gzip: stdin: not in gzip format` or `tar: Child returned status 1`, treat it as a transient bad archive fetch first, not automatically as a broken Moodle URL. `laemp.sh` now retries downloads and validates `.tgz` / `.tar.gz` payloads with `gzip -t` before reuse or extraction because this happened in a real `stable405` Slicer run.
