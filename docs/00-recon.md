# Phase 0 — Recon

Decide Strategy A vs B by measuring, not guessing. The dataset
(`sweap_eval_full_v2.jsonl`) confirms 731 instances across 11 repos / one
build-environment lineage per repo, so the survey is 11 docker pulls, not 731.

## What we measure

For each of the 11 base images:

| Field         | How                                            | Why                                                                                       |
|---------------|------------------------------------------------|-------------------------------------------------------------------------------------------|
| glibc version | `ldd --version \| head -1`                     | Picks A vs B. Strategy A only works if every base ≥ the builder's floor (2.17).           |
| distro pretty | `grep PRETTY /etc/os-release`                  | How many distinct bases the 11 collapse to; sanity check.                                  |
| host kernel   | `uname -r` (once, on the host)                  | Bundled glibc imposes a kernel floor. All containers share this one kernel — single check. |

## Running

```bash
IMAGES="jefzda/sweap-images:repo1 jefzda/sweap-images:repo2 ..." make recon
```

Output goes to `out/recon.json`:

```json
{
  "kernel": "6.x.y-generic",
  "floor": "2.17",
  "worst_glibc": "2.31",
  "recommended_strategy": "A",
  "bases": [
    { "image": "jefzda/sweap-images:repo1", "glibc": "2.31", "distro": "Debian GNU/Linux 11 (bullseye)" },
    ...
  ]
}
```

The script exits non-zero if any base's glibc is below the floor — that's the
clear signal to switch to Strategy B (`make build STRATEGY=B`).

## Reading the result

- **All bases ≥ 2.17** → Strategy A. Container glibc satisfies libc; bundle
  carries only libffi/libssl/libsqlite3/etc. Simpler bundle, no NSS footgun.
- **Any base < 2.17** → Strategy B. Bundle a full glibc + loader; `patchelf
  --set-interpreter` makes container glibc irrelevant.

## Caveats

- `ldd --version` requires libc to be reachable inside the image. If a base
  ships a different libc (musl) it'll print "musl" — that's a heavier port
  and is out of scope for this bundle.
- The recon script uses `--entrypoint sh` to bypass any custom entrypoint. If
  an image lacks `sh`, that image needs a one-off manual check.
