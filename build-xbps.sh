#!/usr/bin/env bash
# Repackage an upstream Claude Desktop Debian binary release for Void x86_64 glibc.
# Usage: build-xbps.sh DEB [EXPECTED_SHA256]
# The version comes from the Debian control file. REVISION overrides the
# XBPS revision (default 1).
set -euo pipefail
umask 022

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
deb=${1:?usage: build-xbps.sh DEB [EXPECTED_SHA256]}
expected=${2:-}
revision=${REVISION:-1}

for tool in ar tar xz zstd sha256sum xbps-create xbps-rindex; do
  command -v "$tool" >/dev/null || { printf 'Missing tool: %s\n' "$tool" >&2; exit 1; }
done
if [ -n "$expected" ]; then
  printf '%s  %s\n' "$expected" "$deb" | sha256sum -c -
fi
tmp=$(mktemp -d "$here/.build.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/control" "$tmp/stage" "$here/repo"
# Extract a deb member (control/data) whatever its compression.
deb_extract() {
  local member flag
  member=$(ar t "$deb" | grep -m1 "^$1\.tar") || { printf 'No %s in %s\n' "$1" "$deb" >&2; exit 1; }
  case $member in
    *.xz) flag=-J ;; *.zst) flag=--zstd ;; *.gz) flag=-z ;; *) flag= ;;
  esac
  ar p "$deb" "$member" | tar $flag -xpf - -C "$2" --no-same-owner
}
deb_extract control "$tmp/control"
control="$tmp/control/control"
grep -qx 'Package: claude-desktop' "$control"
grep -qx 'Architecture: amd64' "$control"
version=$(sed -n 's/^Version: //p' "$control")
[[ $version =~ ^[0-9]+(\.[0-9]+)*$ ]] || { printf 'Unexpected version: %s\n' "$version" >&2; exit 1; }
pkgver="claude-desktop-${version}_${revision}"
deb_extract data "$tmp/stage"
app="$tmp/stage/usr/lib/claude-desktop"
[ -x "$app/claude-desktop" ] && [ -x "$app/resources/cowork-linux-helper" ] \
  || { printf 'Unexpected package layout\n' >&2; exit 1; }

# Do through package-owned files what the Debian postinst does at runtime.
# APT repository and Ubuntu AppArmor registration are intentionally skipped.
provider="$app/resources/gnome-search-provider"
install -Dm644 "$provider/com.anthropic.Claude.search-provider.ini" \
  "$tmp/stage/usr/share/gnome-shell/search-providers/com.anthropic.Claude.search-provider.ini"
install -Dm644 "$provider/com.anthropic.Claude.SearchProvider.service" \
  "$tmp/stage/usr/share/dbus-1/services/com.anthropic.Claude.SearchProvider.service"
# .mcpb, .dxt and .skill MIME types (shared-mime-info cache refreshed by hooks).
if [ -f "$app/resources/linux-mime/com.anthropic.Claude.xml" ]; then
  install -Dm644 "$app/resources/linux-mime/com.anthropic.Claude.xml" \
    "$tmp/stage/usr/share/mime/packages/com.anthropic.Claude.xml"
fi
# `ccd` terminal launcher, linked only when the build ships one.
if [ -x "$app/resources/bin/ccd" ]; then
  ln -s ../lib/claude-desktop/resources/bin/ccd "$tmp/stage/usr/bin/ccd"
fi
install -Dm644 "$tmp/stage/usr/share/doc/claude-desktop/copyright" \
  "$tmp/stage/usr/share/licenses/claude-desktop/copyright"
rm -rf -- "$tmp/stage/usr/share/lintian"
install -m755 "$here/package-hooks.sh" "$tmp/stage/INSTALL"
install -m755 "$here/package-hooks.sh" "$tmp/stage/REMOVE"

# Cowork: edk2-ovmf owns /usr/share/OVMF -> edk2. Claude probes Debian's flat
# OVMF_CODE_4M.fd path and derives OVMF_VARS_4M.fd from it. Add links in
# the actual target directory without replacing the distro-owned symlink.
mkdir -p "$tmp/stage/usr/share/edk2"
ln -s x64/OVMF_CODE.4m.fd "$tmp/stage/usr/share/edk2/OVMF_CODE_4M.fd"
ln -s x64/OVMF_VARS.4m.fd "$tmp/stage/usr/share/edk2/OVMF_VARS_4M.fd"

# Cowork: the guest agent connects over vsock, so load vhost_vsock at boot
# through Void's runit modules-load step.
mkdir -p "$tmp/stage/usr/lib/modules-load.d"
printf 'vhost_vsock\n' > "$tmp/stage/usr/lib/modules-load.d/claude-desktop.conf"

# Preserve upstream sandbox permissions (4755), including its SUID fallback.
# Direct ELF dependencies, dlopen'd libraries, runtime helpers, and the
# Cowork VM stack (QEMU, OVMF firmware, virtiofsd) plus the Claude Code
# sandbox tools (bubblewrap, socat).
packages='gtk+3 glib atk at-spi2-atk at-spi2-core libnotify nss nspr libdrm libgbm libxcb libsecret libXtst libuuid alsa-lib libpipewire cairo libcups dbus-libs expat libgcc libstdc++ eudev-libudev libX11 libXcomposite libXdamage libXext libXfixes libXrandr libxkbcommon libcap-ng libseccomp xdg-utils desktop-file-utils shared-mime-info hicolor-icon-theme xdg-desktop-portal xdg-desktop-portal-gtk ca-certificates gjs qemu-system-amd64 qemu-img edk2-ovmf virtiofsd bubblewrap socat'
printf -v deps '%s>=0 ' $packages
deps="glibc>=2.34 $deps"
(
  cd "$here/repo"
  xbps-create -q -A x86_64 -n "$pkgver" \
    -s 'Claude Desktop by Anthropic (prebuilt)' \
    -m 'Local Void repackager' -H 'https://claude.ai/download' \
    -l 'Proprietary' -D "$deps" "$tmp/stage"
  xbps-rindex -f -a "${pkgver}.x86_64.xbps"
  sha256sum "${pkgver}.x86_64.xbps" > SHA256SUMS
)
printf 'Created %s/repo/%s.x86_64.xbps\n' "$here" "$pkgver"
