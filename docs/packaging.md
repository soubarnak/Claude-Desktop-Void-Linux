# How the package is built

`build-xbps.sh` turns Anthropic's `claude-desktop_<version>_amd64.deb` into
`claude-desktop-<version>_<revision>.x86_64.xbps`. Nothing is compiled.

## Steps

1. Check the `.deb` SHA-256, if one is given.
2. Extract `control.tar.*` and check `Package: claude-desktop` and
   `Architecture: amd64`. Read `Version`.
3. Extract `data.tar.*` with its original file modes. The `.xz`, `.zst`, and
   `.gz` formats are supported.
4. Add the package-owned files listed below.
5. Run `xbps-create` with Void dependency names, then `xbps-rindex -a` to add
   the package to `repo/x86_64-repodata`.

All files from the `.deb` stay byte-for-byte identical, with the same modes.
That includes `chrome-sandbox` with mode `4755` (SUID root), which Electron
uses as its sandbox fallback. No `--no-sandbox` flag is added.

## Differences from the Debian package

Anthropic's `postinst` and `postrm` scripts are not run. They do things that
do not apply to Void (APT sources, APT signing key, unattended-upgrades,
Ubuntu AppArmor profile). Their other tasks become package-owned files:

| Debian maintainer script | XBPS package |
|--------------------------|--------------|
| Copies the GNOME Shell search provider `.ini` and D-Bus `.service` | Ships them in `/usr/share/gnome-shell/search-providers/` and `/usr/share/dbus-1/services/`. |
| Copies `.mcpb`, `.dxt`, `.skill` MIME types and runs `update-mime-database` | Ships `/usr/share/mime/packages/com.anthropic.Claude.xml`. |
| Links `/usr/bin/ccd` when the build has `resources/bin/ccd` | Same link, only when the file exists. |
| (dpkg triggers) | `INSTALL` and `REMOVE` hooks refresh the desktop, icon, and MIME caches. This makes the `claude://` link handler work for sign-in. |

Additions for Void:

- License file at `/usr/share/licenses/claude-desktop/copyright`.
- Cowork firmware links and `vhost_vsock` boot configuration. See
  [cowork.md](cowork.md).

## Dependencies

Mapped from the Debian `Depends` and `Recommends` fields, the libraries the
binaries link, and the libraries Electron loads at run time:

- Desktop and graphics: `gtk+3`, `glib`, `atk`, `at-spi2-atk`, `at-spi2-core`,
  `cairo`, `libdrm`, `libgbm`, `libxcb`, `libX11`, `libXcomposite`,
  `libXdamage`, `libXext`, `libXfixes`, `libXrandr`, `libXtst`, `libxkbcommon`
- System: `glibc>=2.34`, `nss`, `nspr`, `libuuid`, `dbus-libs`, `expat`,
  `libgcc`, `libstdc++`, `eudev-libudev`, `libcap-ng`, `libseccomp`,
  `libcups`, `libsecret`, `libnotify`, `ca-certificates`
- Audio and screen capture: `alsa-lib`, `libpipewire`
- Desktop integration: `xdg-utils`, `xdg-desktop-portal`,
  `xdg-desktop-portal-gtk`, `desktop-file-utils`, `shared-mime-info`,
  `hicolor-icon-theme`, `gjs` (GNOME search provider)
- Cowork: `qemu-system-amd64`, `qemu-img`, `edk2-ovmf`, `virtiofsd`
- Claude Code sandbox: `bubblewrap`, `socat`

Optional, not required: `gnome-keyring` (secret storage) and
`libayatana-appindicator` (tray icon on some desktops).

## Revisions

The XBPS revision starts at `1` for each upstream version. To publish a
packaging-only change for the same upstream version, rebuild with a higher
revision so `xbps-install -u` sees it as newer:

```sh
REVISION=2 ./build-xbps.sh downloads/claude-desktop_<version>_amd64.deb
```
