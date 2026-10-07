# laemp: agent operating model

Adopted 6 October 2026 from local source and command inspection.
Maintained host Moodle installer with Docker, Lima and Slicer verification.

## Read by intent

Start with the local agent guide and build manifest. For domain or behavior
changes, follow the owners below, then the relevant contract/test. These
documents retain product detail and historical evidence:

- [docs/README.md](README.md)
- [README.md](../README.md)
- [tests/README.md](../tests/README.md)
- [platforms/docker/README.md](../platforms/docker/README.md)
- [platforms/lima/README.md](../platforms/lima/README.md)

## System ownership

| Owner | Responsibility |
| --- | --- |
| [laemp.sh](../laemp.sh) | Host convergence script. |
| [docker](../docker) | Platform-owned validation adapters. |
| [platforms/lima](../platforms/lima) | Platform-owned validation adapters. |
| [platforms/slicervm](../platforms/slicervm) | Platform-owned validation adapters. |
| [scripts](../scripts) | Platform-owned validation adapters. |
| [tests](../tests) | Platform-owned validation adapters. |
| [verify-moodle.sh](../verify-moodle.sh) | Acceptance surface and current roadmap. |
| [docs/roadmap.md](../docs/roadmap.md) | Acceptance surface and current roadmap. |

Intent selects the owning policy; that policy produces decisions or artifacts;
adapters perform effects; verification establishes the result. Change the
owner once and keep alternate surfaces on that same contract.

## Invariants

- Loopback-bound test platforms are not deployable public site identities.
- Credential output path is sensitive and must not be copied into reports.

## Existing action interfaces

These are inspected command surfaces, not a report that they ran. Read current
help and recipes for arguments, dependencies and lifecycle hooks before use.
Examples containing placeholder paths or bracketed options are grammar.

| Command | Effects and evidence |
| --- | --- |
| `./laemp.sh -h` | Discover installer options. |
| `./laemp.sh -n -v -p 8.4 -w nginx -d mariadb -m 5024 -S` | Preview desired installer tuple. |
| `make hooks` | Installs local hooks; local mutation. |

## Observe, verify and retain

Establish source revision, dirty state and relevant input identity before
choosing an action. Keep intended settings, cached artifacts and observed
runtime state distinct. An existing artifact is not a freshness or readiness
claim. Use the smallest deterministic fixture at the changed seam first;
expand to process, browser, device or deployment checks only when that
claim needs them. Record unavailable evidence explicitly.

Retain the command/configuration, source and input identity, result, limitation
and next discriminating check. Reuse evidence only while its relevant inputs
remain applicable. Promote a reproducible failure to a regression fixture,
a design decision to its owning document, and a repeated operator correction
to one concise guide rule. Keep private observations in private artifacts.

## Implemented plan for this pass

- [x] Map current source ownership and existing interfaces.
- [x] Make command effects and evidence limits discoverable.
- [x] Route agent work here and retain detailed product plans at their owners.

Acceptance: owner paths and document links resolve; current instructions
match inspected source; catalog hashes bind this context to the reviewed
bytes. This is documentation/control navigation acceptance. Product runtime
checks retain their own scope and are not certified by this pass.

## Project decisions

Keep laemp.sh as the product and choose exactly one validation strand for the behavior under change: stub CLI checks, Docker bootstrap, Lima local VM or Slicer systemd lifecycle. Distinct platform hostnames and loopback bindings prevent cross-run confusion. Record source revision, PHP/database/Moodle tuple, guest OS, runtime identity and verifier outcome. Preview output is intent only; container success is not VM-faithful service acceptance. Preserve /var/lib/laemp/moodle-admin-credentials.env as private host state and report only whether credential handoff was successful. Accrete confirmed installer regressions into the narrowest existing test suite before repeating full provisioning.
