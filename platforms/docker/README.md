# Docker Platform

`platforms/docker` owns the container-backed validation path for `laemp.sh`.

Use it when you want:

- the fast compose path against `moodle.docker.test.127.0.0.1.sslip.io`
- the baseline honest end-to-end container bootstrap
- the supported Docker matrix

Typical commands:

```bash
make -C platforms/docker compose-up
make -C platforms/docker baseline
make -C platforms/docker matrix
```

Notes:

- Published ports bind to `127.0.0.1` by default, not `0.0.0.0`.
- The compose path is intentionally the fast external-PostgreSQL path, not the in-container database-install path.
- The canonical runners now live here; `tests/docker/*` remain as compatibility shims.
