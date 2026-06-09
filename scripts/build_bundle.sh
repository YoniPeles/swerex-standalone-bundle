#!/usr/bin/env bash
#
# Phase 1 — Build. Host entrypoint that runs the manylinux2014 builder image
# and delegates the actual work to scripts/build_in_builder.sh inside it.
#
# The output lands in ./out/swerex/ as a fully self-contained directory tree.
#
# Inputs (env vars):
#   SWEREX_VERSION      REQUIRED. Pin from SWE-bench Pro scaffold's SWE-agent
#                       submodule. A skew here fails at *connect* time, not build.
#   PYTHON_TARBALL_URL  REQUIRED. Internal-mirror URL of the standalone CPython
#                       gnu install_only tarball
#                       (e.g. cpython-3.11.x+<date>-x86_64-unknown-linux-gnu-install_only.tar.gz).
#   BUNDLE_STRATEGY     "A" (default; library-only) or "B" (bundle libc + loader).
#   BUILDER_IMAGE       Default quay.io/pypa/manylinux2014_x86_64.
#   EXTRA_PIP_INDEX     Optional; passed through to pip for the builder's network.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/out"
STRATEGY="${BUNDLE_STRATEGY:-A}"
BUILDER_IMAGE="${BUILDER_IMAGE:-quay.io/pypa/manylinux2014_x86_64}"

if [[ -z "${SWEREX_VERSION:-}" ]]; then
  echo "SWEREX_VERSION must be set (pin to SWE-bench Pro scaffold's swe-rex)" >&2
  exit 2
fi
if [[ -z "${PYTHON_TARBALL_URL:-}" ]]; then
  echo "PYTHON_TARBALL_URL must be set (standalone CPython gnu install_only)" >&2
  exit 2
fi

if [[ "$STRATEGY" != "A" && "$STRATEGY" != "B" ]]; then
  echo "BUNDLE_STRATEGY must be A or B (got: $STRATEGY)" >&2
  exit 2
fi

command -v docker >/dev/null || { echo "docker not found in PATH" >&2; exit 2; }

mkdir -p "$OUT_DIR"
# clean prior build so RPATH/lib state can't survive a strategy switch
rm -rf "$OUT_DIR/swerex"

echo "Building bundle (strategy $STRATEGY) into $OUT_DIR/swerex"

docker run --rm \
  --platform linux/amd64 \
  -e SWEREX_VERSION="$SWEREX_VERSION" \
  -e PYTHON_TARBALL_URL="$PYTHON_TARBALL_URL" \
  -e BUNDLE_STRATEGY="$STRATEGY" \
  -e EXTRA_PIP_INDEX="${EXTRA_PIP_INDEX:-}" \
  -v "$OUT_DIR:/out" \
  -v "$REPO_ROOT/scripts:/scripts:ro" \
  "$BUILDER_IMAGE" \
  bash /scripts/build_in_builder.sh

echo
echo "Done. Verify:"
echo "  readelf -d $OUT_DIR/swerex/python/bin/python3 | grep -E 'RPATH|RUNPATH|INTERP'"
echo "  scripts/selftest.sh"
