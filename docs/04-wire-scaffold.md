# Phase 4 — Wire into the SWE-ReX scaffold

The YAML in `config/deployment.yaml.snippet` is the whole change. Each line
does one job; this doc is the cheat sheet.

## Flag-by-flag

| Flag                         | Effect                                                                                     |
|------------------------------|--------------------------------------------------------------------------------------------|
| `pull: never`                | Never contacts a registry. Required on on-prem — images must be local.                     |
| `install_pipx: false`        | Kills the apt + pipx bootstrap path (the dead Debian mirror).                              |
| `python_standalone_dir: null`| Kills the build-time standalone-Python download/patch path; the bundle replaces it.        |
| `-v /opt/swerex-bundle:/opt/swerex:ro` | Mounts the prebuilt bundle read-only inside the eval container.                  |
| `-e PATH=/opt/swerex/python/bin:…`     | Prepends the bundle's bin to PATH so the bare `swerex-remote` on the LEFT of `swerex-remote \|\| (pipx …)` resolves to ours and succeeds. |

## Why PATH must be absolute

If you wrote `PATH=/opt/swerex/python/bin:$PATH`, the `$PATH` would expand on
the *host* before docker passed it to the container. The container then gets
the host's PATH — wrong. Spell it out fully:

```
PATH=/opt/swerex/python/bin:/usr/local/bin:/usr/bin:/bin
```

## Why no LD_LIBRARY_PATH

The binary has its libs RPATH'd in via `$ORIGIN/../../lib`. With Strategy B
the dynamic loader is also bundled (via `--set-interpreter`). Both eliminate
the need for `LD_LIBRARY_PATH`. Setting it would actually be risky — it can
leak the bundle's libs into the container's *other* processes (the repo's
native test toolchain) and break them.

## Why no `--network none`

The host's RemoteRuntime client still connects to the in-container server
over its published TCP port. "Isolated" here means *no dependency on
container userspace; no outbound internet needed* — not "no networking."
Nothing in this bundle path makes outbound calls, so egress is already
unnecessary without blocking the inbound port.

## Alternative: patch `docker.py` instead

If you already maintain a patch to the scaffold's `docker.py`, the cleanest
form is to have it emit the absolute path `/opt/swerex/python/bin/swerex-remote`
rather than rely on PATH. Either works; the PATH approach is config-only.
