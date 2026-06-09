#!/usr/bin/env bash
#
# Phase 2 — Self-test. Prove the bundle stands alone by mounting it into a
# deliberately hostile container (debian:oldstable, no usable Python of its own)
# and running:
#   - `import pydantic_core, ssl, sqlite3`  (compiled ext + non-libc libs)
#   - `swerex-remote --help`                (entrypoint + full import graph)
# Strategy B additionally starts the server, hits it, and kills it — to flush
# NSS/getaddrinfo issues that only show up at run time.
#
# Inputs (env):
#   BUNDLE_DIR  Path to the built bundle. Default ./out/swerex.
#   TEST_IMAGE  Hostile base. Default debian:oldstable.
#   STRATEGY    Override what was built. Default: detect via ELF INTERP.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_DIR="${BUNDLE_DIR:-$REPO_ROOT/out/swerex}"
TEST_IMAGE="${TEST_IMAGE:-debian:oldstable}"

if [[ ! -x "$BUNDLE_DIR/python/bin/python3" ]]; then
  echo "selftest: $BUNDLE_DIR/python/bin/python3 not found — run build first" >&2
  exit 2
fi

# Detect strategy from the ELF interpreter if not provided.
if [[ -z "${STRATEGY:-}" ]]; then
  if readelf -l "$BUNDLE_DIR/python/bin/python3" 2>/dev/null \
       | grep -q "Requesting program interpreter: $BUNDLE_DIR/../lib/ld-linux"; then
    # Path comparison is fragile — fall back to "contains /opt/swerex/lib"
    STRATEGY="B"
  elif readelf -l "$BUNDLE_DIR/python/bin/python3" 2>/dev/null \
       | grep -qE "Requesting program interpreter: .*swerex.*ld-linux"; then
    STRATEGY="B"
  else
    STRATEGY="A"
  fi
fi
echo "selftest: BUNDLE_DIR=$BUNDLE_DIR  TEST_IMAGE=$TEST_IMAGE  STRATEGY=$STRATEGY"

# ---- core test ----
docker run --rm \
  --platform linux/amd64 \
  -v "$BUNDLE_DIR:/opt/swerex:ro" \
  "$TEST_IMAGE" \
  sh -euxc '
    /opt/swerex/python/bin/python3 -c "import pydantic_core, ssl, sqlite3; print(\"ext ok\")"
    /opt/swerex/python/bin/swerex-remote --help >/dev/null
    echo "swerex ok"
  '

# ---- Strategy B extra: real bind + round trip to flush NSS ----
if [[ "$STRATEGY" == "B" ]]; then
  echo "selftest: strategy B — running localhost bind/round-trip"
  docker run --rm \
    --platform linux/amd64 \
    -v "$BUNDLE_DIR:/opt/swerex:ro" \
    "$TEST_IMAGE" \
    sh -euxc '
      /opt/swerex/python/bin/swerex-remote --port 17654 &
      SERVER=$!
      trap "kill $SERVER 2>/dev/null || true" EXIT
      # poll briefly for listener
      for i in 1 2 3 4 5 6 7 8 9 10; do
        if /opt/swerex/python/bin/python3 -c "import socket,sys; s=socket.socket(); s.settimeout(1); s.connect((\"127.0.0.1\",17654)); s.close()" 2>/dev/null; then
          echo "bind+connect ok"
          exit 0
        fi
        sleep 1
      done
      echo "selftest B: server never bound 127.0.0.1:17654" >&2
      exit 1
    '
fi

echo
echo "selftest: PASS"
