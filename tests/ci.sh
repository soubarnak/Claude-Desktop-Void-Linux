#!/usr/bin/env bash
# Build the newest upstream Claude Desktop in a Void Linux container and
# check the result. Used by .github/workflows/upstream-check.yml.
# Needs: bash git curl gnupg binutils xz zstd python3 (see tests/ci-setup.sh).
# Local run with rootless podman, from a clean checkout:
#   podman run --rm -v "$PWD":/work:Z ghcr.io/void-linux/void-glibc-full:latest \
#     sh -c '/work/tests/ci-setup.sh && /work/tests/ci.sh'
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

cd "$here"
./update.sh --no-install --no-self-update

xbps=$(ls repo/claude-desktop-*.x86_64.xbps)
version=${xbps#repo/claude-desktop-}
version=${version%.x86_64.xbps}
version=${version%_*}
deb=downloads/claude-desktop_${version}_amd64.deb
echo "Built $xbps from $deb"

python3 -I tests/check-package.py "$deb" "$xbps"

# Every run-time dependency must resolve from the official Void repositories.
count=$(xbps-install -S --repository="$here/repo" -n claude-desktop | wc -l)
echo "PASS: dependencies resolve ($count packages would be installed)"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "version=$version" >> "$GITHUB_OUTPUT"
fi
