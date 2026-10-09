# The update script

`update.sh` (installed as `claude-desktop-update`) does the full update in
one run: get the newest Claude Desktop release, verify it, build the XBPS
package, refresh the local repository, and install or upgrade.

## Usage

```
claude-desktop-update [options]
```

| Option | Effect |
|--------|--------|
| `-f`, `--force` | Rebuild even if the newest version is already in `repo/`. |
| `-d`, `--deb FILE` | Use a `.deb` file you downloaded yourself. No download. |
| `-l`, `--link LINK` | Use this Anthropic link instead of the saved repository. |
| `-n`, `--no-install` | Build and refresh the repository only. No `sudo`, no install. |
| `-y`, `--yes` | Pass `-y` to `xbps-install`, so it does not ask for confirmation. |
| `--no-self-update` | Do not `git pull` the scripts before running. |
| `--install-command` | Link the script as `~/.local/bin/claude-desktop-update`, then exit. |
| `-h`, `--help` | Show help. |

## Examples

```sh
claude-desktop-update                      # normal update and upgrade
claude-desktop-update -y                   # same, no confirmation prompt
claude-desktop-update -n                   # build only (for cron)
claude-desktop-update -f                   # rebuild the current version
claude-desktop-update -d ~/Downloads/claude-desktop_2.26454.2_amd64.deb
claude-desktop-update -l https://downloads.claude.ai/claude-desktop/apt/stable
```

## What one run does

1. **Updates itself.** If the script is in a git clone, it runs
   `git pull --ff-only`. When new commits arrive, it restarts with the new
   version and the same options. If the pull fails (offline, local changes),
   it warns and continues with the current copy.
2. **Checks the system.** Only x86_64 Void Linux is supported. It stops with
   an install hint if a required tool is missing.
3. **Gets the release** from one source (see [Sources](#sources)).
4. **Builds** the XBPS package with `build-xbps.sh`, unless the same version
   is already in `repo/` (use `--force` to rebuild).
5. **Cleans up.** Removes older packages from `repo/` (`xbps-rindex -r`),
   cleans the repository index, and deletes older `.deb` files from
   `downloads/`.
6. **Registers the repository** in `/etc/xbps.d/30-claude-desktop.conf` if
   that file is missing or points elsewhere (uses `sudo`).
7. **Installs or upgrades** with `sudo xbps-install -S claude-desktop` or
   `sudo xbps-install -Su claude-desktop`. Only `claude-desktop` and its
   dependencies change; it does not upgrade the rest of the system.
8. **Reports** the old and new installed versions. If Claude Desktop is
   running the old version, it tells you to restart it.

Steps 6 to 8 are skipped with `--no-install`.

## Sources

By default the script reads Anthropic's stable APT repository:

```
https://downloads.claude.ai/claude-desktop/apt/stable
  dists/stable/InRelease
  dists/stable/main/binary-amd64/Packages
```

It selects the highest `claude-desktop` version listed in `Packages`.

### When the default source fails

If the repository cannot be reached, the files are missing, or Claude
Desktop is not listed, the script asks for another source (in a terminal):

```
Could not get Claude Desktop from the saved Anthropic repository.
Enter one of:
  - path to a downloaded claude-desktop .deb file
  - Anthropic APT repository URL
  - the Packages URL, or the whole curl command from Anthropic's install page
  - a direct .deb download URL
File or link (empty to quit):
```

| You enter | The script |
|-----------|------------|
| A file path | Uses that `.deb`. |
| A URL ending in `.deb` | Downloads that file. |
| A URL with `/dists/<suite>/<component>/...` | Takes the repository base, suite, and component from it. |
| Any other URL | Uses it as the repository base, suite `stable`, component `main`. |
| A whole shell command | Finds the URLs inside it, then applies the rules above. |

So you can paste Anthropic's install command as it is, for example:

```sh
curl -fLO "https://downloads.claude.ai/claude-desktop/apt/stable/$(curl -s "https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-$(dpkg --print-architecture)/Packages" | grep '^Filename: pool/main/c/claude-desktop/claude-desktop_' | sort -V | tail -n 1 | cut -d' ' -f2)"
```

If a source does not work, the script asks again. An empty answer quits.
When a new repository link works, it is saved to `update.conf` in the clone
and used on later runs. `--link` takes the same kinds of input without the
prompt.

Without a terminal (for example from cron), the script cannot ask. It exits
with an error, and the next manual run asks.

## Verification

| Source | Checks |
|--------|--------|
| APT repository | `InRelease` must have a valid signature from key `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE` (stored in `keys/`). The `Packages` file must match the SHA-256 in `InRelease`. The `.deb` must match the SHA-256 in `Packages`. |
| Repository with no valid signature | Warns and asks before continuing. Never continues by itself. |
| Direct `.deb` link or local file | Warns that authenticity cannot be verified. Prints the SHA-256 so you can compare it. |

In all cases, `build-xbps.sh` checks that the `.deb` is the `claude-desktop`
package for `amd64` before it builds anything.

The key in `keys/claude-desktop-archive-keyring.asc` is Anthropic's public
release signing key. Anthropic's own `.deb` installs the same key for APT.

## Files the script writes

| Path | Contents |
|------|----------|
| `repo/` | The XBPS package, `x86_64-repodata`, and `SHA256SUMS`. |
| `downloads/` | The current `.deb`. Older ones are deleted. |
| `update.conf` | A replacement repository link, only if you gave one. |
| `/etc/xbps.d/30-claude-desktop.conf` | `repository=<clone>/repo`. |
| `~/.local/bin/claude-desktop-update` | Link to `update.sh`, from `--install-command`. |

All but the last two live in the clone and are ignored by git.

## Automatic updates

The [README](../README.md#update) shows a cron job that runs the script with
`--no-install` every 6 hours. New releases then reach your system with a
normal `sudo xbps-install -Syu`. The log is in
`~/.cache/claude-desktop-update.log`.

## build-xbps.sh

`update.sh` calls `build-xbps.sh`. You can also run it directly:

```sh
./build-xbps.sh DEB [EXPECTED_SHA256]
REVISION=2 ./build-xbps.sh DEB      # bump the XBPS revision
```

It reads the version from the `.deb`, builds
`claude-desktop-<version>_<revision>.x86_64.xbps` in `repo/`, and updates the
index. See [packaging.md](packaging.md).

## Continuous checks

`.github/workflows/upstream-check.yml` runs every day, on pushes that touch
the scripts, and on demand. Inside a `ghcr.io/void-linux/void-glibc-full`
container it runs `tests/ci.sh`, which:

1. runs `update.sh --no-install` against Anthropic's repository;
2. runs `tests/check-package.py`, which fails if any upstream file differs,
   `chrome-sandbox` is not `4755`, a Void addition is missing, or `app.asar`
   no longer mentions the Cowork paths the package relies on;
3. checks that every dependency resolves from the official Void repositories.

On success, the "tested with Claude Desktop" badge is updated. On failure,
an issue labelled `upstream-check` is opened. The built package never leaves
the CI runner.

Run the same check locally with rootless podman from a clean checkout:

```sh
podman run --rm -v "$PWD":/work:Z ghcr.io/void-linux/void-glibc-full:latest \
  sh -c '/work/tests/ci-setup.sh && /work/tests/ci.sh'
```

Or check a package you built yourself:

```sh
python3 tests/check-package.py downloads/claude-desktop_<version>_amd64.deb \
  repo/claude-desktop-<version>_1.x86_64.xbps
```
