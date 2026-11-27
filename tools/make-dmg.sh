#!/bin/zsh
# Builds the app and packs it into a drag-to-Applications installer:
#   tools/make-dmg.sh [output folder]   (default: ~/Downloads)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$HOME/Downloads}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
./build.sh

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R build/DynamicNotch.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$OUT/DynamicNotch-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Dynamic Notch $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null
echo "Installer: $DMG ($(du -h "$DMG" | cut -f1))"
