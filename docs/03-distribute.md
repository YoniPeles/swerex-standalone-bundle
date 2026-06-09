# Phase 3 — Distribute

Two ways to get `out/swerex/` onto every worker node. Pick by topology.

## Option A: tarball + rsync (default)

```bash
make package                # produces out/swerex-bundle.tar.gz
# on each worker (config-mgmt orchestrated):
rsync swerex-bundle.tar.gz worker:/tmp/
ssh worker 'sudo tar -C /opt -xzf /tmp/swerex-bundle.tar.gz && \
            sudo mv /opt/swerex /opt/swerex-bundle'
```

- Simplest if your nodes are already under Ansible/Salt/Chef.
- No registry dependency.
- `package_bundle.sh` pre-normalizes perms to 0555/0444 (with 0555 on `bin/`
  and `*.so`), so the extracted tree is already read-only-friendly.

## Option B: OCI image

```bash
OCI_REGISTRY=registry.internal/swerex-bundle make package
```

Produces a `FROM scratch` image containing just `/swerex/...`. Pull on each
worker and either:

- `docker create` it and `cp` the contents to a host path, or
- mount it directly via `--volumes-from <named-container>` per eval container.

Cleaner in clusters with a registry already in the data path; one extra
indirection if you don't have one.

## Read-only is non-negotiable

Mount must be `:ro`. swe-rex writes uploaded tool bundles into the *container*
fs (`/tmp` etc.), never into its install dir, so this is safe and prevents an
accidental write from a misbehaving instance from poisoning the shared bundle.

## Updates

Bundles are immutable — to ship a new swe-rex version, rebuild and ship a new
bundle directory (e.g. `/opt/swerex-bundle-<date>/`), flip the mount path in
the scaffold config, then garbage-collect old directories after the run.
