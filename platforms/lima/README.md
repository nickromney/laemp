# Lima Platform

`platforms/lima` adds a third local validation strand for `laemp.sh`, parallel to Docker and Slicer.

Use it when you want:

- a local Ubuntu VM that is simpler than Slicer
- a platform-owned Lima workflow patterned after `publiccloudexperiments`
- loopback-only host access on `moodle.lima.test.127.0.0.1.sslip.io`

Typical commands:

```bash
make -C platforms/lima baseline
make -C platforms/lima matrix
make -C platforms/lima status
make -C platforms/lima reset
```

Notes:

- The VM template is Ubuntu 24.04 with Lima `user-v2` networking and no mounts.
- Host exposure is pinned to `127.0.0.1` and restricted to ports `80` and `443`.
- Docker and Lima both want `127.0.0.1:80/443`, so run one local strand at a time.
