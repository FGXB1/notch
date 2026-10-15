#!/bin/zsh
# Builds ungive/mediaremote-adapter (if its sources changed) and copies the framework + perl script to $1.
# Called by the "Embed mediaremote-adapter" build phase with the app's Resources/MediaRemoteAdapter folder.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

ROOT=${0:A:h:h}
SRC="$ROOT/Vendor/mediaremote-adapter"
BUILD="$SRC/build"
FRAMEWORK="$BUILD/MediaRemoteAdapter.framework"
DEST=${1:?usage: build-adapter.sh <destination>}

if [[ ! -f "$SRC/CMakeLists.txt" ]]; then
  echo "error: mediaremote-adapter submodule missing; run: git submodule update --init" >&2
  exit 1
fi

if [[ ! -d "$FRAMEWORK" || -n $(find "$SRC/src" "$SRC/include" "$SRC/CMakeLists.txt" -newer "$FRAMEWORK" -print -quit) ]]; then
  cmake -S "$SRC" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release > /dev/null
  cmake --build "$BUILD" --target MediaRemoteAdapter > /dev/null
  touch "$FRAMEWORK"
fi

mkdir -p "$DEST"
rsync -a --delete "$FRAMEWORK" "$DEST/"
cp "$SRC/bin/mediaremote-adapter.pl" "$DEST/"

# Nested code must be signed before Xcode seals the app bundle.
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$DEST/MediaRemoteAdapter.framework" > /dev/null
