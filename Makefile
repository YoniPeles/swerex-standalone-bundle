# Isolated SWE-ReX runtime bundle.
# One bundle, mounted read-only into every SWE-bench Pro eval container.
# See README.md and docs/ for the why; this Makefile is just the UX.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

REPO_ROOT      := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
OUT_DIR        := $(REPO_ROOT)/out
BUNDLE_DIR     := $(OUT_DIR)/swerex
TARBALL        := $(OUT_DIR)/swerex-bundle.tar.gz

# Overridable on the command line / env.
STRATEGY            ?= A
PYTHON_TARBALL_URL  ?=
IMAGES              ?=
FLOOR               ?= 2.17
BUILDER_IMAGE       ?= quay.io/pypa/manylinux2014_x86_64
TEST_IMAGE          ?= debian:oldstable
OCI_REGISTRY        ?=
OCI_TAG             ?= latest

# swe-rex is pinned via the ./swe-rex submodule (YoniPeles/SWE-ReX). Move the
# pin by checking out a new SHA in the submodule and committing the gitlink.

export PYTHON_TARBALL_URL BUILDER_IMAGE TEST_IMAGE OCI_REGISTRY OCI_TAG IMAGES FLOOR

.PHONY: help recon build test package all clean

help:
	@echo "Targets:"
	@echo "  recon    - Phase 0: survey IMAGES, write out/recon.json, recommend A or B"
	@echo "  build    - Phase 1: produce out/swerex/ (set STRATEGY=B for full glibc isolation)"
	@echo "  test     - Phase 2: self-test against $(TEST_IMAGE)"
	@echo "  package  - Phase 3: write $(TARBALL); push OCI image if OCI_REGISTRY is set"
	@echo "  all      - recon + build + test + package"
	@echo "  clean    - rm -rf out/"
	@echo ""
	@echo "Required vars for build: PYTHON_TARBALL_URL (swe-rex comes from ./swe-rex submodule)"
	@echo "Required vars for recon: IMAGES (space-separated tags)"

recon:
	@scripts/phase0_recon.sh

build:
	@BUNDLE_STRATEGY=$(STRATEGY) scripts/build_bundle.sh

test:
	@scripts/selftest.sh

package:
	@scripts/package_bundle.sh

all: recon build test package

clean:
	rm -rf $(OUT_DIR)
