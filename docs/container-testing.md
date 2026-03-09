# Container Testing

Container testing exists to make `laemp.sh` broadly runnable by contributors who do not have Slicer or do not want a full VM workflow.

It is intentionally not the same thing as VM-faithful testing:

- Containers are the right place to test package bootstrap logic, stock image behavior, prereqs images, and external-database flows.
- Lima VMs are the right place for a lightweight local Ubuntu VM path on macOS.
- Slicer VMs are the right place to test real `systemd`, service enablement, package post-install behavior, guest trust stores, and "real Ubuntu host" assumptions.

## Current Container Paths

### Stock images

Use the stock Dockerfiles when you want to know whether `laemp.sh` can bootstrap a minimal Debian or Ubuntu base image.

```bash
docker build -f docker/Dockerfile.ubuntu -t laemp-ubuntu:24.04 .
docker build -f docker/Dockerfile.debian -t laemp-debian:13 .
```

Then run the integration suite:

```bash
CONTAINER_RUNTIME=docker bats tests/bats/test_integration.bats
```

For Podman:

```bash
CONTAINER_RUNTIME=podman bats tests/bats/test_integration.bats
```

### Prereqs images

Use the prereqs Dockerfiles when you want fast last-mile iteration and already accept that package installation is out of scope for that run.

```bash
docker build -f docker/Dockerfile.prereqs.ubuntu -t laemp-prereqs-ubuntu .
docker build -f docker/Dockerfile.prereqs.debian -t laemp-prereqs-debian .
```

Container paths use the host's native architecture by default. Set `DOCKER_PLATFORM` or `CONTAINER_PLATFORM` explicitly only when you intentionally want cross-arch coverage.

Typical last-mile run:

```bash
docker run -it --rm laemp-prereqs-ubuntu
sudo ./laemp.sh -c -w nginx -d mariadb -m 5013 -S
```

### Compose

`compose.yml` is currently useful for:

- the Debian systemd container path with its PostgreSQL sidecar by default
- the opt-in Server Side Up comparison profile with MariaDB

It is not currently a full Ubuntu compose matrix. Treat it as a targeted harness, not the main stock-image path.

## Suggested Docker Workstream

The next Docker pass should mirror what already works on Slicer and classify each combo as one of:

- works in containers without qualification
- works in containers only with a container-specific harness
- VM-only because the feature depends on real host behavior

Start with these:

1. `php 8.4 + nginx + mariadb + moodle 5013 + self-signed`
2. `php 8.4 + apache + mariadb + moodle 5013 + self-signed`
3. `php 8.4 + nginx + pgsql + moodle 5013 + self-signed`
4. the prereqs-image variant of the same three
5. memcached on top of the nginx baseline
6. Prometheus on top of the nginx baseline

## What Containers Are Bad At Here

Expect friction around:

- `systemd`
- service enablement semantics
- package post-install hooks
- ACME flows
- host/guest trust propagation for `mkcert`

That is normal. The goal is not to force Docker to behave exactly like a VM. The goal is to make the container path honest and useful.

## Suggested Verification for Docker Runs

For each successful container combo, check:

- install exit code
- expected services or processes present
- Moodle `config.php` created
- database schema created
- HTTPS responds on the expected port
- Playwright smoke passes against the running target where practical

For each unsupported combo, prefer a clean early failure over partial install state.
