#!/usr/bin/env bash
#
# Phase 0 — Recon. Survey the 11 SWE-bench Pro base images to pick Strategy A or B.
#
# For each image: get its glibc version (from `ldd --version`) and PRETTY_NAME.
# Also record the host kernel (uname -r) — the irreducible 1%.
# Write out/recon.json. Exit non-zero with a message if any base has glibc
# below the Strategy A floor (2.17) — that's the signal to switch to Strategy B.
#
# Inputs (env vars):
#   IMAGES   Space-separated list of fully-qualified image tags.
#            REQUIRED — no defaults; derive the 11 tags via the SWE-bench Pro
#            helper_code/image_uri.py against one instance_id per repo.
#   FLOOR    Minimum glibc version that Strategy A tolerates. Default 2.17
#            (matches a manylinux2014 builder).
#
# Output:
#   out/recon.json — array of {image, glibc, distro} plus a top-level "kernel"
#   and "recommended_strategy" ("A" or "B").

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/out"
RECON_FILE="$OUT_DIR/recon.json"
FLOOR="${FLOOR:-2.17}"

if [[ -z "${IMAGES:-}" ]]; then
  cat >&2 <<'EOF'
phase0_recon: IMAGES env var is empty.

Set it to the space-separated list of the 11 base image tags, e.g.:
  IMAGES="jefzda/sweap-images:repo1 jefzda/sweap-images:repo2 ..." \
    scripts/phase0_recon.sh

Derive tags by running the SWE-bench Pro helper_code/image_uri.py on one
instance_id per repo (11 lookups total).
EOF
  exit 2
fi

command -v docker >/dev/null || { echo "phase0_recon: docker not found in PATH" >&2; exit 2; }

mkdir -p "$OUT_DIR"
KERNEL="$(uname -r)"

# version_ge A B  -> 0 if A >= B (dotted versions)
version_ge() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]
}

entries=()
worst_glibc=""
needs_b=0

for img in $IMAGES; do
  echo "== probing $img" >&2
  out="$(docker run --rm --entrypoint sh "$img" -c \
    'ldd --version 2>/dev/null | head -1; grep PRETTY /etc/os-release 2>/dev/null || true' \
    2>/dev/null || true)"
  glibc="$(printf '%s\n' "$out" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)"
  distro="$(printf '%s\n' "$out" | sed -n 's/^PRETTY_NAME="\(.*\)"/\1/p')"
  glibc="${glibc:-unknown}"
  distro="${distro:-unknown}"

  if [[ "$glibc" == "unknown" ]]; then
    echo "  WARN: could not read glibc version from $img" >&2
  else
    if ! version_ge "$glibc" "$FLOOR"; then
      needs_b=1
      echo "  BELOW FLOOR: $img has glibc $glibc < $FLOOR" >&2
    fi
    if [[ -z "$worst_glibc" ]] || version_ge "$worst_glibc" "$glibc"; then
      worst_glibc="$glibc"
    fi
  fi

  entries+=("$(printf '{"image":"%s","glibc":"%s","distro":"%s"}' "$img" "$glibc" "$distro")")
done

if [[ "$needs_b" -eq 1 ]]; then
  strategy="B"
else
  strategy="A"
fi

{
  printf '{\n'
  printf '  "kernel": "%s",\n' "$KERNEL"
  printf '  "floor": "%s",\n' "$FLOOR"
  printf '  "worst_glibc": "%s",\n' "${worst_glibc:-unknown}"
  printf '  "recommended_strategy": "%s",\n' "$strategy"
  printf '  "bases": [\n    '
  ( IFS=,; printf '%s' "${entries[*]}" ) | sed 's/},/},\n    /g'
  printf '\n  ]\n}\n'
} > "$RECON_FILE"

echo
echo "Wrote $RECON_FILE"
echo "Host kernel: $KERNEL"
echo "Worst glibc across bases: ${worst_glibc:-unknown} (floor $FLOOR)"
echo "Recommended strategy: $strategy"
echo
if [[ "$strategy" == "B" ]]; then
  echo "At least one base undershoots the Strategy A floor."
  echo "Build with: BUNDLE_STRATEGY=B make build" >&2
  exit 1
fi
