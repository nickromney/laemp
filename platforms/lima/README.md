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


To run only the PHP 8.4 and nginx baseline case:

```bash
platforms/lima/run-matrix.sh --php 8.4 --web nginx --moodle 502
```

The matrix filters match weekly build codes. PHP 8.3 supports `405`, `500`,
and `502` in this matrix. PHP 8.4 supports `500` and `502`. The
`502` filter selects the weekly Moodle 5.2 build.

Notes:

- The VM template is Ubuntu 24.04 with Lima `user-v2` networking and no mounts.
- Host exposure is pinned to `127.0.0.1` and restricted to ports `80` and `443`.
- Docker baselines publish high loopback ports (`18180`/`18543`) instead of `80`/`443`, so Lima and Docker can run on the same machine.
