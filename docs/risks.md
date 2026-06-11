# Risks & mitigations

Six risks. Ordered by likelihood × blast-radius.

## 1. swe-rex client/server version mismatch (highest)

The bundled `swerex-remote` server must be protocol-compatible with the
swe-rex client the host scaffold runs. Pin the bundle to the *exact* version
the SWE-bench Pro scaffold's SWE-agent submodule depends on. Read it from
that submodule's lockfile / `pyproject.toml`; do not take "latest" from PyPI.

A skew here fails at *connect* time (with cryptic protocol errors), not at
build time, so it is easy to miss until you're staring at hundreds of failed
runs.

**Mitigation:** the swe-rex pin lives in the `./swe-rex` submodule
(`YoniPeles/SWE-ReX`). Move it deliberately with `git -C swe-rex checkout
<ref> && git commit`; the submodule SHA in `git log` is the audit trail.
Include the SHA (or describe output) in the bundle's directory name on
workers (e.g. `/opt/swerex-bundle-<sha>/`) so it's visible at runtime.

## 2. NSS footgun (Strategy B only)

A bundled glibc can crash when it `dlopen`s the container's mismatched
`libnss_*` during `getaddrinfo` / localhost binding. The crash looks like a
random segfault on the first network syscall.

**Mitigation:** `build_in_builder.sh` already bundles `libnss_files.so.2`,
`libnss_dns.so.2`, and `libresolv.so.2` for Strategy B. The selftest then
boots the server, binds 127.0.0.1, and round-trips — if NSS is broken, the
selftest catches it on the build host.

If you still see NSS flakiness in the fleet, prefer Strategy A — give up the
full glibc isolation rather than ship Strategy B with patched NSS.

## 3. Kernel floor (the true 1%)

Bundled glibc imposes a minimum host kernel version (recent glibc wants
≥3.2-era). All containers share the host kernel, so it's a single
`uname -r` check, surfaced in `out/recon.json` as the `kernel` field.

**Mitigation:** if the host kernel undershoots the bundled glibc's floor,
either build the bundle on an even older base (manylinux2010 → glibc 2.12)
or raise the host kernel. Don't ship without checking.

## 4. Read-only mount + writes

Could swe-rex try to write into its install dir? If so, `:ro` would break
runs.

**Mitigation:** confirmed by code path — swe-rex writes uploaded tool
bundles into the *container* filesystem (e.g. `/tmp`), not into its install
dir. Keep `:ro` to guarantee isolation; the selftest validates a real boot.

## 5. Architecture

Dataset images are x86_64. Building on an arm64 host without `--platform
linux/amd64` produces an arm64 bundle that won't run.

**Mitigation:** `build_bundle.sh` and `selftest.sh` both pass
`--platform linux/amd64` to docker. On arm hosts you'll need qemu-user
emulation registered (most modern Docker installs do this automatically).

## 6. Relative RPATH depth wrong

Symptom: `ldd` shows "not found" for bundled libs after a build.
**Mitigation:** `build_in_builder.sh` uses single-quoted `$ORIGIN`-relative
RPATHs at the right depths (`../../lib` for `python/bin/python3`,
`../../../lib` for extension `.so`s under `python/lib/python3.X/...`).
Verify with `readelf -d <file> | grep -E 'RPATH|RUNPATH'`. If you upgrade
the standalone CPython tarball and its internal layout changes, recheck the
depth.

---

## Rollback

Pure config change. In the SWE-ReX scaffold config:

1. Remove the `docker_args` block from `env.deployment`.
2. Restore previous values of `python_standalone_dir` and `install_pipx`.
3. Restart whatever long-lived processes hold the config.

The eval images are never modified, so there is nothing to rebuild or undo
on the image side. The bundle directory on workers can be deleted at leisure.
