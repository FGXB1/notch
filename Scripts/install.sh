#!/bin/sh
# Installs or updates Notch from its latest GitHub release:
#
#   curl -fsSL https://github.com/__GITHUB_REPO__/releases/latest/download/install.sh | sh
#
# Notch isn't notarized by Apple, so a copy downloaded in a browser won't open until its quarantine flag is
# cleared. Downloading with curl never sets that flag, so this installs a copy that just opens.
# Scripts/release.sh fills in the repository and attaches this file to each release.
set -eu

REPO="__GITHUB_REPO__"

say() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

version=$(sw_vers -productVersion)
[ "${version%%.*}" -ge 26 ] || fail "Notch needs macOS 26 or later, and this Mac has macOS $version."

# The appcast names the newest disk image.
feed="https://github.com/$REPO/releases/latest/download/appcast.xml"
dmg_url=$(curl -fsSL "$feed" | grep -o 'url="[^"]*\.dmg"' | head -n 1 | sed -e 's/^url="//' -e 's/"$//')
[ -n "$dmg_url" ] || fail "couldn't find the latest release at $feed"

work=$(mktemp -d)
trap 'hdiutil detach "$work/volume" -quiet 2> /dev/null || true; rm -rf "$work"' EXIT

say "Downloading ${dmg_url##*/}..."
curl -fL --progress-bar -o "$work/Notch.dmg" "$dmg_url"
# macOS 27's hdiutil warns that it's deprecated, but still works on every version Notch supports.
hdiutil attach "$work/Notch.dmg" -nobrowse -readonly -mountpoint "$work/volume" -quiet 2> /dev/null \
  || fail "couldn't open the downloaded disk image; try again"
app="$work/volume/Notch.app"
codesign --verify --deep --strict "$app" 2> /dev/null || fail "the downloaded copy of Notch isn't intact; try again"

# /Applications when this account can write there (admins can), otherwise ~/Applications.
destination=/Applications
if [ ! -w "$destination" ]; then
  destination="$HOME/Applications"
  mkdir -p "$destination"
fi

if pgrep -xq Notch; then
  say "Quitting Notch..."
  pkill -x Notch || true
  while pgrep -xq Notch; do sleep 0.2; done
fi

rm -rf "$destination/Notch.app"
ditto "$app" "$destination/Notch.app"
xattr -dr com.apple.quarantine "$destination/Notch.app" 2> /dev/null || true

say "Installed Notch in $destination. Opening it..."
open "$destination/Notch.app"
