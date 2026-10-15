#!/bin/zsh
# Builds the throwaway Phase 0 spike as an ad-hoc signed, menu-bar-less app bundle.
set -euo pipefail

ROOT=${0:A:h}
APP="$ROOT/build/NotchSpike.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

xcrun swiftc -O -swift-version 5 -target arm64-apple-macos26.0 \
  -framework AppKit -framework SwiftUI -framework CoreAudio -framework AudioToolbox \
  "$ROOT/NotchSpike/main.swift" -o "$APP/Contents/MacOS/NotchSpike"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.ishan.NotchSpike</string>
  <key>CFBundleName</key><string>NotchSpike</string>
  <key>CFBundleExecutable</key><string>NotchSpike</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
