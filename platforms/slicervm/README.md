# SlicerVM Platform

`platforms/slicervm` owns the Slicer-backed VM validation path for `laemp.sh`.

Use it when you want:

- a real Linux guest with `systemd`
- package lifecycle validation that is closer to a VPS
- Playwright smoke against `moodle.slicer.test.<vm-ip>.sslip.io`

Typical commands:

```bash
make -C platforms/slicervm baseline
make -C platforms/slicervm matrix
```


To run only the PHP 8.4 and nginx baseline case:

```bash
platforms/slicervm/run-matrix.sh --php 8.4 --web nginx --moodle 502
```

The matrix filters match weekly build codes. PHP 8.3 supports `405`, `500`,
and `502` in this matrix. PHP 8.4 supports `500` and `502`. The
`502` filter selects the weekly Moodle 5.2 build.

Notes:

- The harness uses the system daemon under `~/slicer-mac`.
- A 4 GiB guest was enough for the green PHP 8.4 + nginx + MariaDB Moodle baseline. Heavier combinations, such as monitoring plus Playwright, may need more headroom.
- The canonical runners now live here; `tests/slicer/*` remain as compatibility shims.
- Slicer and Docker share the same `laemp.sh` install contract but intentionally use different browser hostnames.
