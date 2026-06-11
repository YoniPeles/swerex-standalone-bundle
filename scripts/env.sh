#!/usr/bin/env bash
# Source this before `make recon` / `make build`.
#   source scripts/env.sh

# 1. swe-rex is now pinned via the ./swe-rex submodule (YoniPeles/SWE-ReX),
#    which carries the aiohttp-timeout fix. Move the pin with
#    `git -C swe-rex fetch && git -C swe-rex checkout <ref> && git commit`.

# 2. Standalone CPython tarball.
#    Upstream URL for local/online testing. For on-prem deploy, swap the host
#    for your internal mirror but keep the filename identical so bumping the
#    upstream version doesn't churn the path.
export PYTHON_TARBALL_URL="https://github.com/astral-sh/python-build-standalone/releases/download/20241016/cpython-3.11.10+20241016-x86_64-unknown-linux-gnu-install_only.tar.gz"

# 3. One ECR image tag per repo (11 total) — derived from sweap_eval_full_v2.jsonl.
export IMAGES="\
084828598639.dkr.ecr.us-west-2.amazonaws.com/sweap-images/nodebb.nodebb:NodeBB__NodeBB-04998908ba6721d64eba79ae3b65a351dcfbc5b5 \
084828598639.dkr.ecr.us-west-2.amazonaws.com/sweap-images/qutebrowser.qutebrowser:qutebrowser__qutebrowser-f91ace96223cac8161c16dd061907e138fe85111-v059c6fdc75567943479b23ebca7c07b5e9a7f34c \
084828598639.dkr.ecr.us-west-2.amazonaws.com/sweap-images/ansible.ansible:ansible__ansible-f327e65d11bb905ed9f15996024f857a95592629-vba6da65a0f3baefda7a058ebbd0a8dcafb8512f5 \
084828598639.dkr.ecr.us-west-2.amazonaws.com/sweap-images/internetarchive.openlibrary:internetarchive__openlibrary-4a5d2a7d24c9e4c11d3069220c0685b736d5ecde-v13642507b4fc1f8d234172bf8129942da2c2ca26 \
084828598639.dkr.ecr.us-west-2.amazonaws.com/sweap-images/gravitational.teleport:gravitational__teleport-3fa6904377c006497169945428e8197158667910-v626ec2a48416b10a88641359a169d99e935ff037 \
084828598639.dkr.ecr.us-west-2.amazonaws.com/sweap-images/navidrome.navidrome:navidrome__navidrome-7073d18b54da7e53274d11c9e2baef1242e8769e \
084828598639.dkr.ecr.us-west-2.amazonaws.com/sweap-images/element-hq.element:element-hq__element-web-33e8edb3d508d6eefb354819ca693b7accc695e7 \
084828598639.dkr.ecr.us-west-2.amazonaws.com/sweap-images/future-architect.vuls:future-architect__vuls-407407d306e9431d6aa0ab566baa6e44e5ba2904 \
084828598639.dkr.ecr.us-west-2.amazonaws.com/sweap-images/protonmail.webclients:protonmail__webclients-2c3559cad02d1090985dba7e8eb5a129144d9811 \
084828598639.dkr.ecr.us-west-2.amazonaws.com/sweap-images/flipt-io.flipt:flipt-io__flipt-e42da21a07a5ae35835ec54f74004ebd58713874 \
084828598639.dkr.ecr.us-west-2.amazonaws.com/sweap-images/tutao.tutanota:tutao__tutanota-da4edb7375c10f47f4ed3860a591c5e6557f7b5c-vbc0d9ba8f0071fbe982809910959a6ff8884dbbf\
"

# Reminder: the ECR registry above needs auth before `make recon` can pull.
#   aws ecr get-login-password --region us-west-2 \
#     | docker login --username AWS --password-stdin 084828598639.dkr.ecr.us-west-2.amazonaws.com

echo "swerex-bundle env loaded:"
echo "  swe-rex pin: ./swe-rex submodule @ $(git -C "$(dirname "${BASH_SOURCE[0]}")/.." submodule status swe-rex 2>/dev/null | awk '{print $1, $3}')"
echo "  PYTHON_TARBALL_URL=$PYTHON_TARBALL_URL"
echo "  IMAGES=$(echo $IMAGES | wc -w) tags"
