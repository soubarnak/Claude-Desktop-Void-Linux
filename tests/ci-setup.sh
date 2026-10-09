#!/bin/sh
# Prepare a fresh ghcr.io/void-linux/void-glibc-full container for tests/ci.sh.
set -eu
xbps-install -Syu xbps
xbps-install -yu
xbps-install -y bash git curl gnupg binutils xz zstd python3
