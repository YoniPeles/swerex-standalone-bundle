# swerex-standalone-bundle

Build a single, fully self-contained `swerex-remote` runtime that mounts
read-only into every SWE-bench Pro eval container — no `apt`, no PyPI, no
mirror, no outbound network at run time. One bundle covers all 11 repo bases
(731 instances).

## Why

The default scaffold tries to install `swerex-remote` inside each container at
startup via apt + pipx, then falls back to downloading a standalone CPython
and patching it. Both paths break on our on-prem nodes (dead Debian mirror,
no outbound internet, glibc skews).

The eval container's native toolchain (Go compiler, Node/pnpm, conda Python
3.9) is left untouched. The bundle only hosts the swerex control channel.

## Build process

`make build` runs the compile step inside a `manylinux2014` builder container:
it fetches the standalone CPython tarball, `pip install`s the pinned
`swe-rex` into it, walks every ELF in the tree with `ldd` to copy the
non-libc shared libraries it needs into `lib/`, and `patchelf`s an
`$ORIGIN`-relative RPATH onto each one (Strategy B additionally bundles the
dynamic loader + NSS plugins and rewrites the ELF interpreter). `make test`
then mounts the resulting bundle read-only into a deliberately hostile
`debian:oldstable` container with no usable Python of its own and runs
`import pydantic_core, ssl, sqlite3` plus `swerex-remote --help` — and, under
Strategy B, a real localhost bind/round-trip to flush NSS issues that only
surface at run time.

## Deployment

Ship the built `out/swerex-bundle.tar.gz` via bidul. Extract it and mount the
resulting directory into every eval container at a stable path, then point the
SWE-ReX scaffold at that in-container path as its `python-standalone-dir` so
the scaffold uses our bundled CPython + swe-rex instead of trying to download
and patch its own at start-up. The exact flag names live in the SWE-ReX
scaffold version we run — look them up there rather than copying defaults.

## Quickstart

```bash
# 0. Fill in the open items (see "Decisions to make" below), then:

# 1. Recon the 11 base images — picks Strategy A vs B for you.
IMAGES="jefzda/sweap-images:repo1 jefzda/sweap-images:repo2 ..." make recon

# 2. Build the bundle (Strategy A is the default).
SWEREX_VERSION=1.2.3 \
PYTHON_TARBALL_URL=https://mirror.internal/cpython-3.11.x+date-...-gnu-install_only.tar.gz \
  make build
# If recon said B:
#   make build STRATEGY=B

# 3. Prove isolation.
make test

# 4. Ship.
make package                                  # writes out/swerex-bundle.tar.gz
OCI_REGISTRY=registry.internal/swerex-bundle make package   # also push image
```

## Strategies

- **A (default)** — library-only isolation. The bundle's Python uses the
  *container's* glibc but its own copies of libffi, libssl, libsqlite3, etc.
  Simpler, smaller, no NSS footgun. Requires every base's glibc to be ≥ the
  builder's floor (manylinux2014 → 2.17).
- **B** — full glibc isolation. We bundle libc, the dynamic loader, and the
  NSS plugins, then `patchelf --set-interpreter` so the binary boots via our
  loader. Container glibc becomes irrelevant. Heavier and brings the NSS
  footgun (mitigated by bundling `libnss_files/libnss_dns/libresolv`).

`make recon` picks for you. If any base reports glibc < 2.17, switch to B.

## Decisions to make before first build

Three values are not committed in this repo — fill them in via env vars on the
`make build` command (or export them shell-wide):

1. **`SWEREX_VERSION`** — pin to the *exact* swe-rex version the SWE-bench Pro
   scaffold's SWE-agent submodule depends on. Read it from that submodule's
   lockfile/pyproject; do not take latest. A skew here surfaces at *connect
   time*, not build time, so it is load-bearing. (Risks #1 in `docs/risks.md`.)
2. **`PYTHON_TARBALL_URL`** — internal-mirror URL of the standalone CPython
   `…-x86_64-unknown-linux-gnu-install_only.tar.gz` tarball you already vendor.
   Use *gnu* (not musl) so compiled extensions like pydantic-core dlopen
   cleanly.
3. **`IMAGES`** — the 11 base image tags. Derive via the SWE-bench Pro
   `helper_code/image_uri.py` against one `instance_id` per repo.

## Repo layout

```
.
├── Makefile                       one-command UX
├── README.md                      (this file)
├── docs/
│   ├── 00-recon.md                why Phase 0 picks A vs B
│   ├── 03-distribute.md           OCI image vs rsync tradeoffs
│   ├── 04-wire-scaffold.md        flag-by-flag rationale
│   ├── 05-validate.md             smoke / per-language / full-fleet checklist
│   └── risks.md                   six risks + mitigations + rollback
├── scripts/
│   ├── phase0_recon.sh            survey bases, recommend strategy
│   ├── build_bundle.sh            host entrypoint for the builder container
│   ├── build_in_builder.sh        runs inside manylinux2014
│   ├── selftest.sh                isolation test on debian:oldstable
│   └── package_bundle.sh          tarball + optional OCI push
└── out/                           build output (gitignored)
```

## Rollback

Pure run-time config change: stop pointing the scaffold at the bundle's
`python-standalone-dir` and let it fall back to its previous bootstrap path.
The eval images are never modified — nothing to rebuild on the image side.
