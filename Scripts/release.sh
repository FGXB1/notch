#!/bin/zsh
# Builds a release of Notch to hand to other people: a universal, signed (and, with a paid Apple Developer
# account, notarized) disk image, plus the appcast.xml that tells installed copies about it. Settings are
# in Config/release.env.
#
#   Scripts/release.sh keys                    once: create the key Sparkle updates are signed with
#   Scripts/release.sh <version> [notes.md]    build build/release/<version>/Notch-<version>.dmg
#   Scripts/release.sh publish <version>       upload that build as a GitHub release (needs gh)
#
# Without a paid Apple Developer account releases aren't notarized, so people install with the one-line
# installer (Scripts/install.sh, attached to each release): curl doesn't quarantine what it downloads.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

ROOT=${0:A:h:h}
cd "$ROOT"
source Config/release.env

DERIVED="$ROOT/build/DerivedData-Release"
SPARKLE_BIN="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
# The keychain account Sparkle's private key is stored under.
SPARKLE_ACCOUNT="notch"

die() { print -u2 "error: $*"; exit 1; }
step() { print -P "%B==> $*%b"; }

resolve_packages() {
  [[ -x "$SPARKLE_BIN/generate_keys" ]] && return
  step "Resolving packages"
  xcodegen generate --quiet
  xcodebuild -resolvePackageDependencies -project Notch.xcodeproj -scheme Notch -derivedDataPath "$DERIVED" -quiet
}

# MARK: keys

cmd_keys() {
  resolve_packages
  local generate="$SPARKLE_BIN/generate_keys"
  if ! "$generate" --account "$SPARKLE_ACCOUNT" -p > /dev/null 2>&1; then
    step "Creating Sparkle's signing key in your login keychain"
    "$generate" --account "$SPARKLE_ACCOUNT" > /dev/null
  fi
  local key
  key=$("$generate" --account "$SPARKLE_ACCOUNT" -p)
  [[ $key =~ '^[A-Za-z0-9+/]{43}=$' ]] || die "unexpected public key from generate_keys: $key"
  sed -i '' -E "s#^SPARKLE_PUBLIC_KEY=.*#SPARKLE_PUBLIC_KEY=\"$key\"#" Config/release.env
  print "Public key saved to Config/release.env."
  print
  print "Back up the private key now. Without it, copies already out there can never update again:"
  print "  $generate --account $SPARKLE_ACCOUNT -x ~/Desktop/notch-sparkle-key.txt"
  print "then put that file's contents in your password manager and delete the file."
}

# MARK: build

notarize() {
  local file=$1 result id notary_status
  step "Notarizing ${file:t} (usually a few minutes)"
  result=$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json) || true
  id=$(plutil -extract id raw -o - - <<< "$result" 2> /dev/null || true)
  notary_status=$(plutil -extract status raw -o - - <<< "$result" 2> /dev/null || true)
  if [[ $notary_status != Accepted ]]; then
    [[ -n $id ]] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2
    die "notarization of ${file:t} failed: ${notary_status:-$result}"
  fi
  xcrun stapler staple -q "$file"
}

cmd_build() {
  local version=$1 notes=${2:-}
  [[ $version =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ]] || die "the version should look like 1.2.3, not '$version'"
  [[ -z $notes || -f $notes ]] || die "no release notes at $notes"

  # Developer ID and notarization when there's a paid team, otherwise the Apple Development certificate
  # Debug builds use. Either way the signature stays the same from release to release, which is what
  # keeps people's privacy permissions working after an update.
  local identities identity notarize=false
  identities=$(security find-identity -v -p codesigning)
  if [[ -n $DEVELOPER_ID_TEAM ]]; then
    identity=$(print -r -- "$identities" | grep -oE "\"Developer ID Application: [^\"]+ \\($DEVELOPER_ID_TEAM\\)\"" \
      | head -1 | tr -d '"' || true)
    [[ -n $identity ]] || die "no Developer ID Application certificate for team $DEVELOPER_ID_TEAM in your keychain"
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" > /dev/null 2>&1 \
      || die "no notarization credentials under '$NOTARY_PROFILE'; see Config/release.env"
    notarize=true
  else
    identity=$(print -r -- "$identities" | grep -oE '"Apple Development: [^"]+"' | head -1 | tr -d '"' || true)
    [[ -n $identity ]] || die "no Apple Development certificate in your keychain"
    print "Not notarized (no DEVELOPER_ID_TEAM): people should install with the one-line installer."
  fi

  local feed="" key=""
  if [[ -n $GITHUB_REPO && -n $SPARKLE_PUBLIC_KEY ]]; then
    feed="https://github.com/$GITHUB_REPO/releases/latest/download/appcast.xml"
    key=$SPARKLE_PUBLIC_KEY
  else
    print "warning: this build won't update itself (set GITHUB_REPO and run 'Scripts/release.sh keys')."
  fi

  local previous build
  previous=$(sed -nE 's/^CURRENT_PROJECT_VERSION = ([0-9]+)$/\1/p' Config/Version.xcconfig)
  build=$(( previous + 1 ))
  local work
  work=$(mktemp -d "${TMPDIR:-/tmp}/notch-release.XXXXXX")
  trap "rm -rf '$work'" EXIT

  # Built with the everyday signing settings (an identity override would reach the packages' resource
  # bundles too, which sign themselves), then re-signed for release below.
  step "Building Notch $version ($build)"
  xcodegen generate --quiet
  rm -rf "$DERIVED/Build/Products/Release"
  xcodebuild -project Notch.xcodeproj -scheme Notch -configuration Release -derivedDataPath "$DERIVED" \
    -destination 'generic/platform=macOS' ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
    NOTCH_APPCAST_URL="$feed" NOTCH_SPARKLE_KEY="$key" \
    -quiet build
  local app="$DERIVED/Build/Products/Release/Notch.app"
  [[ -d $app ]] || die "the build didn't produce $app"

  # Inside out, every piece of code with the same identity, the hardened runtime and a secure timestamp:
  # what notarization requires, and what Xcode doesn't do for the helpers nested inside Sparkle.
  step "Signing as $identity"
  sign() {
    local output
    output=$(codesign --force --timestamp --options runtime --sign "$identity" "$@" 2>&1) || die "$output"
  }
  local sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
  sign "$sparkle/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
  sign "$sparkle/Autoupdate"
  sign "$sparkle/Updater.app"
  sign "$app/Contents/Frameworks/Sparkle.framework"
  sign "$app/Contents/Resources/MediaRemoteAdapter/MediaRemoteAdapter.framework"
  sign "$app/Contents/Resources/MediaRemoteAdapter/MediaRemoteAdapterTestClient"
  sign --entitlements Config/Notch.entitlements "$app"
  codesign --verify --deep --strict "$app" || die "the signature doesn't verify"
  for arch in arm64 x86_64; do
    lipo "$app/Contents/MacOS/Notch" -verify_arch "$arch" || die "Notch wasn't built for $arch"
  done

  if $notarize; then
    ditto -c -k --keepParent "$app" "$work/Notch.zip"
    notarize "$work/Notch.zip"
    xcrun stapler staple -q "$app"
  fi

  step "Making the disk image"
  local out="$ROOT/build/release/$version"
  local dmg="$out/Notch-$version.dmg"
  rm -rf "$out"
  mkdir -p "$out" "$work/dmg"
  ditto "$app" "$work/dmg/Notch.app"
  ln -s /Applications "$work/dmg/Applications"
  if ! $notarize; then
    cat > "$work/dmg/If Notch won't open.txt" <<'EOF'
macOS only opens apps from developers Apple has verified, and Notch isn't one of them yet. To open it:

1. Drag Notch into Applications.
2. Open Terminal and paste:

       xattr -dr com.apple.quarantine /Applications/Notch.app

3. Open Notch from Applications.

You only have to do this once. Updates install without it.
EOF
  fi
  hdiutil create -volname "Notch" -srcfolder "$work/dmg" -fs HFS+ -format UDZO -ov -quiet "$dmg"
  codesign --force --timestamp --sign "$identity" "$dmg"
  $notarize && notarize "$dmg"

  if [[ -n $feed ]]; then
    # An appcast of just this release: Sparkle only needs the newest, and each release carries its own.
    step "Writing the appcast"
    mkdir -p "$work/appcast"
    cp "$dmg" "$work/appcast/"
    [[ -n $notes ]] && cp "$notes" "$work/appcast/Notch-$version.md"
    "$SPARKLE_BIN/generate_appcast" --account "$SPARKLE_ACCOUNT" --maximum-deltas 0 --embed-release-notes \
      --download-url-prefix "https://github.com/$GITHUB_REPO/releases/download/v$version/" \
      -o "$out/appcast.xml" "$work/appcast"
  fi
  [[ -n $notes ]] && cp "$notes" "$out/notes.md"
  [[ -n $GITHUB_REPO ]] && sed "s#__GITHUB_REPO__#$GITHUB_REPO#g" Scripts/install.sh > "$out/install.sh"

  sed -i '' -E -e "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $version/" \
    -e "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $build/" Config/Version.xcconfig

  print
  print "Built $dmg"
  [[ -f $out/appcast.xml ]] && print "  and $out/appcast.xml"
  if [[ -n $GITHUB_REPO ]]; then
    print "Next: Scripts/release.sh publish $version"
    print "People install it with:"
    print "  curl -fsSL https://github.com/$GITHUB_REPO/releases/latest/download/install.sh | sh"
  else
    print "Share the disk image however you like; set GITHUB_REPO to publish releases and updates."
  fi
}

# MARK: publish

cmd_publish() {
  local version=${1:?usage: release.sh publish <version>}
  local out="$ROOT/build/release/$version"
  [[ -n $GITHUB_REPO ]] || die "set GITHUB_REPO in Config/release.env first"
  command -v gh > /dev/null || die "the GitHub CLI isn't installed: brew install gh && gh auth login"
  [[ -f $out/Notch-$version.dmg ]] || die "build it first: Scripts/release.sh $version"
  local assets=("$out/Notch-$version.dmg")
  [[ -f $out/appcast.xml ]] && assets+=("$out/appcast.xml")
  [[ -f $out/install.sh ]] && assets+=("$out/install.sh")
  local notes_args=(--notes "")
  [[ -f $out/notes.md ]] && notes_args=(--notes-file "$out/notes.md")
  step "Publishing v$version to github.com/$GITHUB_REPO"
  gh release create "v$version" "${assets[@]}" --repo "$GITHUB_REPO" --title "Notch $version" "${notes_args[@]}"
}

case ${1:-} in
  keys) cmd_keys ;;
  publish) shift; cmd_publish "$@" ;;
  "" | -h | --help) sed -nE '2,11s/^# ?//p' "$0" ;;
  *) cmd_build "$@" ;;
esac
