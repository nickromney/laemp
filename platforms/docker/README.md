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
- Compose and the Docker baseline probe those host ports first and move if they are already taken.
- `compose-up` waits for HTTPS and refuses to print a URL whose leaf certificate is expired or within an hour of expiry. Use the printed URL, including the port when it is not `443`. Kind or another process on `127.0.0.1:443` will answer the no-port URL.
- The compose path is intentionally the fast external-PostgreSQL path, not the in-container database-install path.
- The canonical runners now live here; `tests/docker/*` remain as compatibility shims.
