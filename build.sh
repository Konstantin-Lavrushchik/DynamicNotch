#!/bin/zsh
# Builds DynamicNotch.app into ./build. Pass --install to copy it to ~/Applications and start it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64

APP="build/DynamicNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
touch build/.metadata_never_index   # keep Spotlight from offering this dev copy
BIN="$(swift build -c release --arch arm64 --show-bin-path)"
cp "$BIN/DynamicNotch" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x DynamicNotch 2>/dev/null || true
  sleep 0.5
  mkdir -p ~/Applications
  rm -rf ~/Applications/DynamicNotch.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/DynamicNotch.app
  echo "Installed to ~/Applications and started"
fi
