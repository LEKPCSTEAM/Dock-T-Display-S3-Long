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

codesign --force --deep -s "${LONGDECK_SIGN_ID:--}" "$APP"
echo "Built $APP"
