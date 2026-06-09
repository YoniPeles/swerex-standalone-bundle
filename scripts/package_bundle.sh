#!/usr/bin/env bash
#
# Phase 3 — Distribute. Produces a single tarball of out/swerex/ that any
# operator can rsync to /opt/swerex-bundle on worker nodes. If OCI_REGISTRY is
# set, also builds a `FROM scratch` image and pushes it.
#
# Inputs (env):
#   BUNDLE_DIR    Default ./out/swerex
#   TARBALL       Default ./out/swerex-bundle.tar.gz
#   OCI_REGISTRY  Optional; e.g. registry.internal/swerex-bundle
#   OCI_TAG       Default "latest"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_DIR="${BUNDLE_DIR:-$REPO_ROOT/out/swerex}"
TARBALL="${TARBALL:-$REPO_ROOT/out/swerex-bundle.tar.gz}"

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "package: $BUNDLE_DIR not found — run build first" >&2
  exit 2
fi

# Read-only-friendly perms: 0555 on dirs, 0444 on files, but preserve x on bin/.
echo "Normalizing perms under $BUNDLE_DIR (read-only-friendly)"
find "$BUNDLE_DIR" -type d -exec chmod 0555 {} +
find "$BUNDLE_DIR" -type f -exec chmod 0444 {} +
# Restore execute on bin/ and any *.so so the loader can mmap them executable.
find "$BUNDLE_DIR" -type f \( -path '*/bin/*' -o -name '*.so' -o -name '*.so.*' \) \
  -exec chmod 0555 {} +

echo "Writing $TARBALL"
tar -C "$(dirname "$BUNDLE_DIR")" -czf "$TARBALL" "$(basename "$BUNDLE_DIR")"
ls -lh "$TARBALL"

if [[ -n "${OCI_REGISTRY:-}" ]]; then
  TAG="${OCI_TAG:-latest}"
  REF="$OCI_REGISTRY:$TAG"
  echo "Building OCI image $REF"
  TMPCTX="$(mktemp -d)"
  trap 'rm -rf "$TMPCTX"' EXIT
  cp -a "$BUNDLE_DIR" "$TMPCTX/swerex"
  cat > "$TMPCTX/Dockerfile" <<'EOF'
FROM scratch
COPY swerex /swerex
EOF
  docker build --platform linux/amd64 -t "$REF" "$TMPCTX"
  docker push "$REF"
  echo "Pushed $REF"
fi

echo "package: done"
