#!/usr/bin/env bash
#
# Phase 1 — Build. Host entrypoint that runs the manylinux2014 builder image
# and delegates the actual work to scripts/build_in_builder.sh inside it.
#
# The output lands in ./out/swerex/ as a fully self-contained directory tree.
#
# Inputs (env vars):
#   PYTHON_TARBALL_URL  REQUIRED. Internal-mirror URL of the standalone CPython
#                       gnu install_only tarball
#                       (e.g. cpython-3.11.x+<date>-x86_64-unknown-linux-gnu-install_only.tar.gz).
#   BUNDLE_STRATEGY     "A" (default; library-only) or "B" (bundle libc + loader).
#   BUILDER_IMAGE       Default quay.io/pypa/manylinux2014_x86_64.
#   EXTRA_PIP_INDEX     Optional; passed through to pip for the builder's network.
#
# swe-rex is installed from the vendored YoniPeles/SWE-ReX submodule at
# ./swe-rex (which carries our aiohttp-timeout fix). The submodule SHA is the
# pin — update it with `git -C swe-rex checkout <ref> && git commit` rather
# than via an env var. The previous SWEREX_VERSION env var is ignored.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/out"
SWEREX_SRC="$REPO_ROOT/swe-rex"
STRATEGY="${BUNDLE_STRATEGY:-A}"
BUILDER_IMAGE="${BUILDER_IMAGE:-quay.io/pypa/manylinux2014_x86_64}"

if [[ -z "${PYTHON_TARBALL_URL:-}" ]]; then
  echo "PYTHON_TARBALL_URL must be set (standalone CPython gnu install_only)" >&2
  exit 2
fi

if [[ ! -f "$SWEREX_SRC/pyproject.toml" ]]; then
  echo "swe-rex submodule missing at $SWEREX_SRC — run: git submodule update --init" >&2
  exit 2
fi

if [[ "$STRATEGY" != "A" && "$STRATEGY" != "B" ]]; then
  echo "BUNDLE_STRATEGY must be A or B (got: $STRATEGY)" >&2
  exit 2
fi

command -v docker >/dev/null || { echo "docker not found in PATH" >&2; exit 2; }

SWEREX_SHA="$(git -C "$SWEREX_SRC" rev-parse HEAD)"
SWEREX_DESCRIBE="$(git -C "$SWEREX_SRC" describe --tags --always --dirty 2>/dev/null || echo "$SWEREX_SHA")"

mkdir -p "$OUT_DIR"
# clean prior build so RPATH/lib state can't survive a strategy switch
rm -rf "$OUT_DIR/swerex"

echo "Building bundle (strategy $STRATEGY) into $OUT_DIR/swerex"
echo "  swe-rex source: $SWEREX_SRC @ $SWEREX_DESCRIBE ($SWEREX_SHA)"

docker run --rm \
  --platform linux/amd64 \
  -e SWEREX_DESCRIBE="$SWEREX_DESCRIBE" \
  -e SWEREX_SHA="$SWEREX_SHA" \
  -e PYTHON_TARBALL_URL="$PYTHON_TARBALL_URL" \
  -e BUNDLE_STRATEGY="$STRATEGY" \
  -e EXTRA_PIP_INDEX="${EXTRA_PIP_INDEX:-}" \
  -v "$OUT_DIR:/out" \
  -v "$REPO_ROOT/scripts:/scripts:ro" \
  -v "$SWEREX_SRC:/src/swe-rex:ro" \
  "$BUILDER_IMAGE" \
  bash /scripts/build_in_builder.sh

echo
echo "Done. Verify:"
echo "  readelf -d $OUT_DIR/swerex/python/bin/python3 | grep -E 'RPATH|RUNPATH|INTERP'"
echo "  scripts/selftest.sh"
