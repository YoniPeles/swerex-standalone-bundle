#!/usr/bin/env bash
#
# Runs inside the manylinux2014 builder. Do not invoke directly — use
# scripts/build_bundle.sh on the host. This script assumes:
#   - /out is a writable mount that will become the operator's ./out
#   - /src/swe-rex is the read-only YoniPeles/SWE-ReX submodule checkout
#   - PYTHON_TARBALL_URL, BUNDLE_STRATEGY are set
#   - SWEREX_DESCRIBE / SWEREX_SHA are set by build_bundle.sh for the version
#     stamp at the end (informational only)
#   - patchelf is on PATH (manylinux images ship it)
#
# Produces /out/swerex/ with:
#   python/                standalone CPython (install_only)
#   lib/                   bundled .so files
#   (Strategy B only) lib/ld-linux-x86-64.so.2 + libnss_files/libnss_dns/libresolv

set -euxo pipefail

: "${PYTHON_TARBALL_URL:?}"
STRATEGY="${BUNDLE_STRATEGY:-A}"
SWEREX_SRC=/src/swe-rex
SWEREX_DESCRIBE="${SWEREX_DESCRIBE:-unknown}"
SWEREX_SHA="${SWEREX_SHA:-unknown}"

test -f "$SWEREX_SRC/pyproject.toml" || {
  echo "Expected swe-rex source at $SWEREX_SRC (mount the submodule)" >&2
  exit 2
}

# Build at the path the bundle will be MOUNTED at in the eval container.
# pip bakes shebangs as #!$DEST/python/bin/python3 — if $DEST != mount path,
# every console_script (swerex-remote, pip, etc.) becomes unrunnable when the
# bundle is mounted elsewhere ("interpreter not found" via execve).
# Symlink /opt/swerex -> /out/swerex so files actually land in the mounted
# output dir while shebangs reference the future mount path.
mkdir -p /out/swerex /opt
ln -sfn /out/swerex /opt/swerex
DEST=/opt/swerex
LIBDIR="$DEST/lib"
mkdir -p "$DEST" "$LIBDIR"

# ---- 1. fetch + unpack standalone CPython (gnu install_only) ----
curl -fL -o /tmp/py.tgz "$PYTHON_TARBALL_URL"
tar -xzf /tmp/py.tgz -C "$DEST"
test -x "$DEST/python/bin/python3"

# ---- 2. install swe-rex from the vendored submodule ----
# The submodule SHA is the pin: it carries our aiohttp-timeout fix so the
# harness's 30-min BashAction.timeout isn't silently capped at aiohttp's
# default 5 min. We copy the tree to a writable path because pip writes
# build artifacts (egg-info, build/) next to pyproject.toml.
cp -a "$SWEREX_SRC" /tmp/swe-rex-src
PIP_ARGS=()
if [[ -n "${EXTRA_PIP_INDEX:-}" ]]; then
  PIP_ARGS+=(--extra-index-url "$EXTRA_PIP_INDEX")
fi
# ${PIP_ARGS[@]+"${PIP_ARGS[@]}"} expands to nothing when the array is empty;
# a bare "${PIP_ARGS[@]}" trips `set -u` on bash <5.2.
"$DEST/python/bin/python3" -m pip install --no-cache-dir \
  ${PIP_ARGS[@]+"${PIP_ARGS[@]}"} \
  /tmp/swe-rex-src

# ---- 3. collect shared library deps ----
# copy_deps <elf>: append non-libc shared-lib deps of <elf> into $LIBDIR.
# Strategy A filters out glibc — we let the container's libc satisfy those.
# Strategy B keeps everything; the full glibc set is added below.
copy_deps() {
  local elf="$1"
  # $3 must look like an absolute path — skips "(0x...)" rows (vdso, in-RPATH libs).
  if [[ "$STRATEGY" == "A" ]]; then
    ldd "$elf" 2>/dev/null \
      | awk '/=>/ && $3 ~ /^\// && !/libc\.so|ld-linux|libpthread\.so|libm\.so|libdl\.so|librt\.so|libutil\.so/ {print $3}' \
      | sort -u \
      | xargs -r -I{} cp -nL {} "$LIBDIR/"
  else
    ldd "$elf" 2>/dev/null \
      | awk '/=>/ && $3 ~ /^\// {print $3}' \
      | sort -u \
      | xargs -r -I{} cp -nL {} "$LIBDIR/"
  fi
}

copy_deps "$DEST/python/bin/python3"
find "$DEST/python" -name '*.so' -print0 \
  | while IFS= read -r -d '' so; do copy_deps "$so"; done

# Strategy B: bundle the dynamic loader + NSS so getaddrinfo / localhost binding
# don't dlopen the container's mismatched libnss_*.
if [[ "$STRATEGY" == "B" ]]; then
  for l in ld-linux-x86-64.so.2 \
           libnss_files.so.2 libnss_dns.so.2 libresolv.so.2 \
           libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 libutil.so.1; do
    src="$(find /lib64 /lib /usr/lib64 /usr/lib -name "$l" 2>/dev/null | head -1 || true)"
    if [[ -z "$src" ]]; then
      echo "Strategy B: could not locate $l in builder" >&2
      exit 3
    fi
    cp -nL "$src" "$LIBDIR/"
  done
fi

# ---- 4. patchelf — RPATH ($ORIGIN-relative, single-quoted) ----
# Depth: python/bin/python3 -> ../../lib ; python/lib/python3.X/.../foo.so -> ../../../lib
patchelf --set-rpath '$ORIGIN/../../lib' "$DEST/python/bin/python3"
find "$DEST/python" -name '*.so' -print0 | xargs -0 -r -I{} \
  patchelf --set-rpath '$ORIGIN/../../../lib' {}

if [[ "$STRATEGY" == "B" ]]; then
  # Point the ELF interpreter at our bundled loader. After this, the container's
  # glibc is irrelevant — we boot via $LIBDIR/ld-linux-x86-64.so.2.
  patchelf --set-interpreter "$LIBDIR/ld-linux-x86-64.so.2" "$DEST/python/bin/python3"
fi

# ---- 5. sanity prints (build-time, not isolation test — that's selftest.sh) ----
echo
echo "== bundle layout =="
ls -la "$DEST" "$DEST/python/bin" "$LIBDIR" | head -100

echo
echo "== readelf on python3 =="
readelf -d "$DEST/python/bin/python3" | grep -E 'RPATH|RUNPATH|INTERP|NEEDED' || true

echo
echo "Build complete: strategy=$STRATEGY, swe-rex=$SWEREX_DESCRIBE ($SWEREX_SHA)"
