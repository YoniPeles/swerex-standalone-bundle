# Phase 5 — Validate across the fleet

Three rings. Stop at the first failure; don't promote bad bundles forward.

## Ring 1 — Smoke (11 containers)

For each of the 11 base tags, mount the bundle and confirm the runtime boots
and a trivial command round-trips:

```bash
for tag in $IMAGES; do
  echo "== $tag"
  docker run --rm \
    -v /opt/swerex-bundle:/opt/swerex:ro \
    -e PATH=/opt/swerex/python/bin:/usr/local/bin:/usr/bin:/bin \
    "$tag" \
    sh -c 'command -v swerex-remote && swerex-remote --help >/dev/null && echo OK'
done
```

Then drive one full scaffold-initiated RemoteRuntime command round-trip
against each base (the scaffold's existing smoke harness should cover this).

## Ring 2 — End-to-end per language family

Pick ~3 instances from each family and confirm `.pred` patches generate:

- **Python**: ansible / openlibrary / qutebrowser
- **Go**: flipt / teleport / vuls / navidrome
- **JS**: webclients / element-web / NodeBB / tutanota

This catches regressions where the bundled Python interferes with the
container's native toolchain (it shouldn't — the bundle is only on PATH for
the swerex process, not for tests).

## Ring 3 — Full 731

Run the full scaffold. The single most important signal in the startup logs:

```
Ensuring deployment ... swerex-remote ...
```

Must show the bare `swerex-remote …` succeeding with *no pipx fallback line
after it*. Grep for `pipx` in the run log; the count should be zero.

## What "good" looks like

- 100% of containers boot `swerex-remote` from the bundle path.
- Zero `pipx` invocations across the run.
- Zero outbound network attempts from the eval containers (if you monitor
  egress, this is the cleanest signal that the isolation is complete).
- Repo test pass-rates match the pre-bundle baseline within noise.
