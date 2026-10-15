#!/bin/zsh
# Sends a command to a running Debug build of Notch (see App/DebugCommands.swift), e.g.
#   Scripts/notchcmd.sh expand
#   Scripts/notchcmd.sh tray:add:$HOME/Downloads/file.pdf
#   Scripts/notchcmd.sh click:818,110,cmd
# `Scripts/notchcmd.sh build-harness` compiles the drag test apps in Tools/DragHarness into build/Tools.
set -euo pipefail

if [[ "${1:-}" == "build-harness" ]]; then
  ROOT=${0:A:h:h}
  mkdir -p "$ROOT/build/Tools"
  for tool in DragSource DropTarget; do
    swiftc -O "$ROOT/Tools/DragHarness/$tool.swift" -o "$ROOT/build/Tools/$tool"
  done
  echo "Built into build/Tools"
  exit 0
fi

osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('dev.ishan.notch.debug', '$1', \$(), true)" >/dev/null
