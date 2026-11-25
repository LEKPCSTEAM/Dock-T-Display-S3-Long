#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/LongDeckApp"

APP=build/LongDeck.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LongDeck"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R "$(dirname "$BIN")/LongDeck_LongDeckCore.bundle" "$APP/Contents/Resources/"
test -f "$APP/Contents/Resources/LongDeck_LongDeckCore.bundle/Contents/Resources/sprites/claude-agent.png"

codesign --force --deep -s "${LONGDECK_SIGN_ID:--}" "$APP"
echo "Built $APP"
