# Stock vs Prereqs Dockerfiles

This repo keeps two container image styles because they test different parts of `laemp.sh`.

## Stock images

Files:

- `docker/Dockerfile.ubuntu`
- `docker/Dockerfile.debian`

Purpose:

- full bootstrap testing
- repository setup
- package installation
- service wiring on a minimal base image

Typical use:

```bash
docker build -f docker/Dockerfile.ubuntu -t laemp-ubuntu:24.04 .
docker build -f docker/Dockerfile.debian -t laemp-debian:13 .
CONTAINER_RUNTIME=docker bats tests/bats/test_integration.bats
```

Use stock images to verify that `laemp.sh` can build a machine from near-zero.

## Prereqs images

Files:

- `docker/Dockerfile.prereqs.ubuntu`
- `docker/Dockerfile.prereqs.debian`

Purpose:

- last-mile configuration testing
- faster iteration on web, PHP, Moodle, and config generation logic
- situations where package bootstrap is already known or intentionally out of scope

Typical use:

```bash
docker build -f docker/Dockerfile.prereqs.ubuntu -t laemp-prereqs-ubuntu .
docker run -it --rm laemp-prereqs-ubuntu
sudo ./laemp.sh -c -w nginx -d mariadb -m 5013 -S
```

Use prereqs images to verify that the remaining configuration logic still works once the packages already exist.

## Why Keep Both

- Stock images catch bootstrap regressions that prereqs images hide.
- Prereqs images shorten the edit-test loop for configuration work.
- Slicer still remains the VM-faithful path for real Ubuntu behavior.

The right long-term test model is:

1. quick CLI checks on the host
2. stock container tests for accessible bootstrap coverage
3. prereqs container tests for fast last-mile coverage
4. Slicer for VM-faithful release confidence
