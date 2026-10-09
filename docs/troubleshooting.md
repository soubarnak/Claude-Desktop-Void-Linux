# Troubleshooting

## `missing tools: ...`

Install the build tools:

```sh
sudo xbps-install -S git curl gnupg binutils xz zstd
```

## `only x86_64 glibc Void Linux is supported`

Anthropic publishes Linux builds for amd64 (and arm64 Debian only). There is
no musl build, so Void musl cannot run Claude Desktop.

## The script asks for a file or link

The saved Anthropic repository did not work. Check Anthropic's Linux install
instructions for the current link and paste it, or paste the whole `curl`
command. See [update-script.md](update-script.md#when-the-default-source-fails).

## `InRelease is not signed by the stored Anthropic key`

The repository signature does not match the key in `keys/`. Anthropic may
have rotated its key, or the download may be tampered with. Answer `N`
unless you have confirmed the change with Anthropic. If Anthropic published
a new key, update `keys/claude-desktop-archive-keyring.asc` and the
`fingerprint=` line in `update.sh`, or pull a newer version of this
repository.

## `xbps-install -Syu` does not show the new version

- Run `claude-desktop-update -n` (or check the cron log in
  `~/.cache/claude-desktop-update.log`). XBPS only sees versions that were
  built into `repo/`.
- Check that the repository is registered:

  ```sh
  cat /etc/xbps.d/30-claude-desktop.conf
  xbps-query -L | grep claude
  ```

- If you moved the clone, run `claude-desktop-update` again. It rewrites the
  repository path.

## Claude Desktop still shows the old version

Quit Claude Desktop completely (also from the tray, if shown) and start it
again. Check the installed version with `xbps-query -p pkgver claude-desktop`.

## Sign-in in the browser does not return to the app

The `claude://` link handler must be registered. The package hooks refresh
the desktop database on install. Check:

```sh
xdg-mime query default x-scheme-handler/claude   # com.anthropic.Claude.desktop
```

If the output is empty, run
`sudo update-desktop-database /usr/share/applications` and try again. A
working `xdg-desktop-portal` backend is needed on Wayland.

## Cowork says virtualization is not available

See [cowork.md](cowork.md#what-you-must-do). Most often:

- Virtualization is disabled in firmware, so `/dev/kvm` does not exist.
- Your user is not in the `kvm` group, or you did not log in again after
  adding it.
- `vhost_vsock` is not loaded: run `sudo modprobe vhost_vsock`.

## The window does not appear, or the sandbox fails

The package keeps `chrome-sandbox` as SUID root (mode `4755`). Check it:

```sh
ls -l /usr/lib/claude-desktop/chrome-sandbox   # -rwsr-xr-x root root
sudo xbps-pkgdb claude-desktop                   # verifies installed files
```

If the mode is wrong, reinstall with `sudo xbps-install -f claude-desktop`.

## Clean rebuild

```sh
claude-desktop-update --force
```
