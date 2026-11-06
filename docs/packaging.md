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
- Claude logo in every place launchers and docks look: the upstream hicolor
  `claude-desktop` PNGs, plus the 512 px `resources/icon.png` as
  `hicolor/512x512` and `/usr/share/pixmaps/claude-desktop.png`, and
  `com.anthropic.Claude` aliases (the window app_id) for docks that look up
  icons by app_id. The build fails if the package has no Claude icon.
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

The packaging revision is set by the default `REVISION` in `update.sh` and
`build-xbps.sh` (currently `2`). Bump both defaults when the packaging changes
for the same upstream version. `update.sh` then rebuilds, because it checks
for the exact `<version>_<revision>`, and `xbps-install -u` sees the package
as newer. A one-off rebuild:

```sh
REVISION=3 ./build-xbps.sh downloads/claude-desktop_<version>_amd64.deb
```
