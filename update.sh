#!/usr/bin/env bash
# One-step Claude Desktop update for Void Linux:
#   1. Find the newest release in Anthropic's APT repository and verify it.
#   2. Download the .deb, repack it as XBPS, and refresh the local repository.
#   3. Remove obsolete packages and downloads, then install or upgrade.
# If the Anthropic repository cannot be reached or no longer lists the
# package, the script asks for a local .deb file or a new Anthropic link
# (APT repository URL, Packages URL, the full curl command, or a .deb URL).
# A working new repository link is saved to update.conf for next time.
# When this script lives in a git clone, it first pulls the newest version
# of itself (disable with --no-self-update).
set -euo pipefail
umask 022

usage() {
  cat <<'EOF'
Usage: update.sh [options]
  -f, --force        rebuild even if the newest version is already in the repo
  -d, --deb FILE     use a local .deb instead of downloading
  -l, --link LINK    use this Anthropic link instead of the saved repository
  -n, --no-install   build and refresh the repository only
  -y, --yes          do not ask xbps-install for confirmation
      --no-self-update  do not git pull this script's repository first
      --install-command link this script as ~/.local/bin/claude-desktop-update
  -h, --help         show this help
EOF
}

here=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
repo="$here/repo"
downloads="$here/downloads"
conf="$here/update.conf"
key="$here/keys/claude-desktop-archive-keyring.asc"
fingerprint=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
xbps_conf=/etc/xbps.d/30-claude-desktop.conf
arch=amd64

APT_BASE=https://downloads.claude.ai/claude-desktop/apt/stable
APT_SUITE=stable
APT_COMPONENT=main
if [ -f "$conf" ]; then
  while IFS='=' read -r name value; do
    case $name in
      APT_BASE|APT_SUITE|APT_COMPONENT) printf -v "$name" '%s' "$value" ;;
    esac
  done < "$conf"
fi

force=0 install=1 yes='' opt_deb='' opt_link='' self_update=1 link_command=0
args=("$@")
while [ $# -gt 0 ]; do
  case $1 in
    -f|--force) force=1 ;;
    -d|--deb) opt_deb=${2:?--deb needs a file}; shift ;;
    -l|--link) opt_link=${2:?--link needs a link}; shift ;;
    -n|--no-install) install=0 ;;
    -y|--yes) yes=-y ;;
    --no-self-update) self_update=0 ;;
    --install-command) link_command=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

info() { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
ask() {  # ask PROMPT -> REPLY
  { : > /dev/tty; } 2>/dev/null || die "no terminal for input: $1"
  printf '%s' "$1" > /dev/tty
  IFS= read -r REPLY < /dev/tty || REPLY=
}
confirm() { ask "$1 [y/N] "; [[ $REPLY =~ ^[Yy] ]]; }

if [ "$link_command" = 1 ]; then
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$here/update.sh" "$HOME/.local/bin/claude-desktop-update"
  info "Linked $HOME/.local/bin/claude-desktop-update -> $here/update.sh"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "$HOME/.local/bin is not in PATH; add it to your shell profile" ;;
  esac
  exit 0
fi

# Pull script updates once, then rerun the new copy with the same arguments.
if [ "$self_update" = 1 ] && [ -z "${CLAUDE_VOID_UPDATED:-}" ] \
   && [ -d "$here/.git" ] && command -v git >/dev/null; then
  old_head=$(git -C "$here" rev-parse HEAD 2>/dev/null || true)
  if git -C "$here" pull --ff-only --quiet 2>/dev/null; then
    if [ "$(git -C "$here" rev-parse HEAD)" != "$old_head" ]; then
      info "Updated scripts to $(git -C "$here" rev-parse --short HEAD); restarting"
      CLAUDE_VOID_UPDATED=1 exec "$here/update.sh" "${args[@]}"
    fi
  else
    warn "could not update scripts with git pull; continuing with this copy"
  fi
fi

case $(xbps-uhelper arch 2>/dev/null) in
  x86_64) ;;
  *) die "only x86_64 glibc Void Linux is supported (upstream ships amd64 only)" ;;
esac
missing=''
for tool in curl gpg sha256sum ar tar xz zstd xbps-query xbps-rindex xbps-create; do
  command -v "$tool" >/dev/null || missing+=" $tool"
done
[ -z "$missing" ] || die "missing tools:$missing (install: sudo xbps-install -S curl gnupg binutils xz zstd)"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$downloads" "$repo"

deb='' sha='' version=''

deb_version() {  # deb_version FILE: print the Debian control Version
  local member flag
  member=$(ar t "$1" | grep -m1 '^control\.tar') || return 1
  case $member in
    *.xz) flag=-J ;; *.zst) flag=--zstd ;; *.gz) flag=-z ;; *) flag= ;;
  esac
  ar p "$1" "$member" | tar $flag -xOf - ./control 2>/dev/null \
    | sed -n 's/^Version: //p'
}

repo_has() {  # repo_has VERSION: true when the local repo indexes it
  xbps-query -i --repository="$repo" -R -p pkgver claude-desktop 2>/dev/null \
    | grep -qx "claude-desktop-${1}_[0-9]*"
}

use_local() {  # use_local FILE
  [ -f "$1" ] || { warn "not a file: $1"; return 1; }
  version=$(deb_version "$1") || true
  [ -n "$version" ] || { warn "not a Claude Desktop .deb: $1"; return 1; }
  deb=$(readlink -f -- "$1")
  sha=$(sha256sum "$deb" | cut -d' ' -f1)
  info "Using $deb (version $version, SHA-256 $sha)"
}

use_deb_url() {  # use_deb_url URL: direct download, no signed index
  local out="$downloads/${1##*/}"
  info "Downloading $1"
  curl -fL -o "$out.part" "$1" || { rm -f "$out.part"; warn "download failed"; return 1; }
  mv -- "$out.part" "$out"
  warn "direct .deb link: no signed index, so authenticity is not verified"
  use_local "$out"
}

use_repo() {  # use_repo BASE SUITE COMPONENT
  local base=${1%/} suite=$2 component=$3 signed=0 want filename
  info "Checking $base (suite $suite, component $component)"
  if curl -fsSL -o "$tmp/InRelease" "$base/dists/$suite/InRelease"; then
    export GNUPGHOME="$tmp/gnupg"
    rm -rf "$GNUPGHOME"; mkdir -m700 "$GNUPGHOME"
    gpg --batch --quiet --import "$key" 2>/dev/null
    if gpg --batch --quiet --status-fd 3 --output "$tmp/Release" \
         --decrypt "$tmp/InRelease" 3>"$tmp/status" 2>/dev/null \
       && grep -q "^\[GNUPG:\] VALIDSIG $fingerprint " "$tmp/status"; then
      signed=1
      info "InRelease signature verified ($fingerprint)"
    else
      rm -f "$tmp/Release"
      warn "InRelease is not signed by the stored Anthropic key"
    fi
  else
    warn "no InRelease at $base/dists/$suite/InRelease"
  fi
  local index="$component/binary-$arch/Packages"
  curl -fsSL -o "$tmp/Packages" "$base/dists/$suite/$index" \
    || { warn "cannot download $base/dists/$suite/$index"; return 1; }
  if [ "$signed" = 1 ]; then
    want=$(awk -v f="$index" '/^SHA256:/{s=1;next} /^[^ ]/{s=0} s && $3==f {print $1}' "$tmp/Release")
    printf '%s  %s\n' "$want" "$tmp/Packages" | sha256sum -c --quiet - 2>/dev/null \
      || { warn "Packages does not match the signed InRelease"; return 1; }
  else
    confirm "Continue without signature verification?" || return 1
  fi
  read -r version sha filename < <(awk '
    /^Package: /{p=$2} /^Version: /{v=$2} /^SHA256: /{s=$2} /^Filename: /{f=$2}
    /^$/{if(p=="claude-desktop") print v, s, f; p=v=s=f=""}
    END{if(p=="claude-desktop") print v, s, f}' "$tmp/Packages" | sort -V | tail -n 1) || true
  [ -n "${filename:-}" ] || { warn "no claude-desktop entry in Packages"; return 1; }
  info "Newest upstream version: $version"

  deb="$downloads/${filename##*/}"
  if [ "$force" = 0 ] && repo_has "$version"; then
    info "Repository already has $version"
  elif [ -f "$deb" ] && printf '%s  %s\n' "$sha" "$deb" | sha256sum -c --quiet - 2>/dev/null; then
    info "Using cached $deb"
  else
    info "Downloading $base/$filename"
    curl -fL -o "$deb.part" "$base/$filename" || { rm -f "$deb.part"; warn "download failed"; return 1; }
    printf '%s  %s\n' "$sha" "$deb.part" | sha256sum -c --quiet - \
      || { rm -f "$deb.part"; warn "SHA-256 mismatch for downloaded .deb"; return 1; }
    mv -- "$deb.part" "$deb"
  fi

  if [ "$base" != "${APT_BASE%/}" ] || [ "$suite" != "$APT_SUITE" ] || [ "$component" != "$APT_COMPONENT" ]; then
    printf 'APT_BASE=%s\nAPT_SUITE=%s\nAPT_COMPONENT=%s\n' "$base" "$suite" "$component" > "$conf"
    info "Saved new repository link to $conf"
  fi
}

use_link() {  # use_link TEXT: a file path, .deb URL, repo URL, or curl command
  local text=$1 url urls base rest suite component
  if [ -f "$text" ]; then use_local "$text"; return; fi
  mapfile -t urls < <(grep -oE 'https?://[^]"'"'"' )$`]+' <<<"$text")
  [ ${#urls[@]} -gt 0 ] || { warn "no file or URL found in: $text"; return 1; }
  for url in "${urls[@]}"; do
    if [[ $url == *.deb ]]; then use_deb_url "$url"; return; fi
  done
  for url in "${urls[@]}"; do
    if [[ $url == */dists/* ]]; then
      base=${url%%/dists/*}; rest=${url#*/dists/}
      suite=${rest%%/*}; rest=${rest#"$suite"}; rest=${rest#/}
      component=${rest%%/*}
      case $component in ''|InRelease|Release|Release.gpg|binary-*) component=main ;; esac
      use_repo "$base" "$suite" "$component"; return
    fi
  done
  use_repo "${urls[0]%/}" stable main
}

prompt_source() {
  cat > /dev/tty <<'EOF'

Could not get Claude Desktop from the saved Anthropic repository.
Enter one of:
  - path to a downloaded claude-desktop .deb file
  - Anthropic APT repository URL (e.g. https://downloads.claude.ai/claude-desktop/apt/stable)
  - the Packages URL, or the whole curl command from Anthropic's install page
  - a direct .deb download URL
EOF
  while :; do
    ask 'File or link (empty to quit): '
    [ -n "$REPLY" ] || die "no source given"
    use_link "$REPLY" && return 0
    warn "that source did not work; try again"
  done
}

if [ -n "$opt_deb" ]; then
  use_local "$opt_deb" || die "cannot use $opt_deb"
elif [ -n "$opt_link" ]; then
  use_link "$opt_link" || die "cannot use $opt_link"
else
  use_repo "$APT_BASE" "$APT_SUITE" "$APT_COMPONENT" || prompt_source
fi

if [ "$force" = 0 ] && repo_has "$version"; then
  info "Skipping build: $version already in $repo (use --force to rebuild)"
else
  "$here/build-xbps.sh" "$deb" "$sha"
fi

info "Removing obsolete packages from $repo"
xbps-rindex -r "$repo" >/dev/null
xbps-rindex -c "$repo" >/dev/null
for old in "$downloads"/*.deb; do
  [ -e "$old" ] && [ "$(readlink -f -- "$old")" != "$deb" ] && { rm -f -- "$old"; info "Removed $old"; }
done

[ "$install" = 1 ] || { info "Done (no install requested)"; exit 0; }

if ! grep -qsx "repository=$repo" "$xbps_conf"; then
  info "Registering $repo in $xbps_conf"
  printf 'repository=%s\n' "$repo" | sudo tee "$xbps_conf" >/dev/null
fi
before=$(xbps-query -p pkgver claude-desktop 2>/dev/null || true)
if [ -n "$before" ]; then
  sudo xbps-install -Su $yes claude-desktop
else
  sudo xbps-install -S $yes claude-desktop
fi
after=$(xbps-query -p pkgver claude-desktop 2>/dev/null || true)
info "Installed: ${after:-none} (was: ${before:-none})"
if [ "$before" != "$after" ] && pgrep -f '^/usr/lib/claude-desktop/claude-desktop' >/dev/null; then
  info "Claude Desktop is running the old version; quit and reopen it."
fi
