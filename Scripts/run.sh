#!/bin/zsh
# Regenerates the Xcode project, builds Debug, and relaunches the app.
set -euo pipefail

ROOT=${0:A:h:h}
cd "$ROOT"

xcodegen generate --quiet
xcodebuild -project Notch.xcodeproj -scheme Notch -configuration Debug \
  -derivedDataPath build/DerivedData -quiet build

pkill -x Notch || true
while pgrep -x Notch > /dev/null; do sleep 0.1; done
# LaunchServices can still be tearing down the old instance; retry briefly instead of failing with -600.
for attempt in 1 2 3 4 5; do
  open build/DerivedData/Build/Products/Debug/Notch.app 2>/dev/null && break
  sleep 0.5
done
echo "Notch launched. Logs: log stream --predicate 'subsystem == \"dev.ishan.notch\"'"
