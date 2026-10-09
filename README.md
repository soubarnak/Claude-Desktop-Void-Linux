<p align="center">
  <a href="https://bongbetic.com">
    <img src="https://bongbetic.com/branding/bongbetic-logo-lockup.png#gh-light-mode-only" alt="Bongbetic" width="320">
  </a>
</p>

<h1 align="center">Claude Desktop for Void Linux</h1>

<p align="center">
  Install and update Anthropic's official Claude Desktop, including <b>Cowork</b>,
  on Void Linux with <code>xbps-install</code>.<br>
  A <a href="https://bongbetic.com">Bongbetic</a> open-source project.
</p>

---

## What this repository does

Anthropic publishes Claude Desktop for Linux as a Debian package (`.deb`) in
its own APT repository. Void Linux uses XBPS, so it cannot install that
package directly.

This repository contains a script that does the whole job on your machine:

1. Finds the newest Claude Desktop release in Anthropic's APT repository.
2. Verifies the repository signature with Anthropic's signing key and checks
   the `.deb` SHA-256.
3. Repacks the `.deb` as a native XBPS package. The application files stay
   byte-for-byte identical to Anthropic's.
4. Adds the package to a local XBPS repository and registers that repository
   with XBPS.
5. Installs or upgrades `claude-desktop` with `xbps-install`.

After the first run, Claude Desktop is a normal XBPS package. New releases
arrive through `xbps-install -Syu`, like any other package.

The package also makes **Cowork** (Claude's sandboxed virtual machine) work
on Void. See [Cowork on Void Linux](docs/cowork.md).

> **This repository contains no Anthropic binaries.** Claude Desktop is
> proprietary software of Anthropic PBC. Each user downloads it directly from
> Anthropic. This project is not affiliated with or endorsed by Anthropic.

## Requirements

- Void Linux, **x86_64 glibc** (Anthropic ships no musl or ARM build for Linux).
- `sudo` rights, to register the repository and install the package.
- About 1 GB of free disk space for the download, the build, and the package.
- These tools:

  ```sh
  sudo xbps-install -S git curl gnupg binutils xz zstd
  ```

- For Cowork: hardware virtualization (Intel VT-x or AMD-V) enabled in firmware.

## Install

Clone the repository to a permanent location. XBPS reads packages from the
`repo/` folder inside the clone, so do not move or delete the clone later.

```sh
git clone https://github.com/soubarnak/Claude-Desktop-Void-Linux.git \
  ~/.local/share/claude-desktop-void
cd ~/.local/share/claude-desktop-void
./update.sh --install-command   # adds the claude-desktop-update command
claude-desktop-update           # download, build, register, install
```

`--install-command` links the script to `~/.local/bin/claude-desktop-update`.
If `~/.local/bin` is not in your `PATH`, run `./update.sh` from the clone instead.

The first run asks for your `sudo` password. It writes
`/etc/xbps.d/30-claude-desktop.conf` with this line:

```
repository=/home/<you>/.local/share/claude-desktop-void/repo
```

For Cowork, add your user to the `kvm` group, then log out and back in:

```sh
sudo usermod -aG kvm "$USER"
```

Start Claude from your application menu or run `claude-desktop`.

## Update

Two ways to get new Claude Desktop releases.

**Manual:** run the update command. It updates this repository's scripts
with `git pull`, builds the newest Claude Desktop release if needed, and
upgrades the installed package.

```sh
claude-desktop-update
```

**Automatic:** let cron build new releases in the background. Then your
normal system upgrade installs them:

```sh
sudo xbps-install -Syu
```

Set up the cron job once (Void does not install cron by default):

```sh
sudo xbps-install -S cronie
sudo ln -s /etc/sv/cronie /var/service/
mkdir -p ~/.cache
( crontab -l 2>/dev/null
  echo '0 */6 * * * $HOME/.local/bin/claude-desktop-update --no-install >>$HOME/.cache/claude-desktop-update.log 2>&1'
) | crontab -
```

Every 6 hours, the job checks Anthropic for a new release and adds it to
your local repository. It never installs anything by itself.

After an upgrade, quit and reopen Claude Desktop to use the new version.

## The update script

```
claude-desktop-update [options]
  -f, --force             rebuild even if the newest version is already in the repo
  -d, --deb FILE          use a local .deb instead of downloading
  -l, --link LINK         use this Anthropic link instead of the saved repository
  -n, --no-install        build and refresh the repository only
  -y, --yes               do not ask xbps-install for confirmation
      --no-self-update    do not git pull this script's repository first
      --install-command   link this script as ~/.local/bin/claude-desktop-update
  -h, --help              show this help
```

If Anthropic moves its repository, the script asks for a new source. You can
give a downloaded `.deb`, the new repository URL, its `Packages` URL, the
whole `curl` command from Anthropic's install instructions, or a direct
`.deb` link. A repository link that works is saved for later runs.

Full details: [docs/update-script.md](docs/update-script.md).

## Uninstall

```sh
sudo xbps-remove claude-desktop
sudo rm /etc/xbps.d/30-claude-desktop.conf
rm ~/.local/bin/claude-desktop-update
rm -rf ~/.local/share/claude-desktop-void
crontab -e    # delete the claude-desktop-update line, if you added it
```

Your Claude settings and data stay in `~/.config/Claude`.

## Documentation

| Document | Contents |
|----------|----------|
| [docs/update-script.md](docs/update-script.md) | Every option, sources and fallbacks, verification, files the script writes |
| [docs/cowork.md](docs/cowork.md) | Cowork requirements, what the package changes for it, how to test it |
| [docs/packaging.md](docs/packaging.md) | How the `.deb` becomes an XBPS package, dependencies, differences from Debian |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common problems and fixes |

## License

The scripts and documentation in this repository use the [MIT License](LICENSE).
Claude Desktop is © Anthropic PBC and is licensed by Anthropic under its own
terms. "Claude" and "Anthropic" are trademarks of Anthropic PBC.

<p align="center">
  <sub>Made by <a href="https://bongbetic.com">Bongbetic</a>.</sub>
</p>
