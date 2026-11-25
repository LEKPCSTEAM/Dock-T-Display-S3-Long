#!/bin/bash
# Usage: export.sh [out-dir]  (default: the app's bundled sprites)
set -euo pipefail
cd "$(dirname "$0")"
ASEPRITE="${ASEPRITE:-/Applications/Aseprite.app/Contents/MacOS/aseprite}"
OUT="${1:-../Sources/LongDeckCore/Resources/sprites}"
mkdir -p "$OUT"
for name in claude-agent claude-hats; do
    "$ASEPRITE" -b "$name.aseprite" \
        --sheet "$OUT/$name.png" --data "$OUT/$name.json" \
        --format json-array --list-tags --list-slices --sheet-type horizontal
done
echo "exported to $OUT"
