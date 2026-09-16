#!/bin/sh
# Regenera ios/ColorsApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024{,-dark,-tinted}.png
# desde el emblema vectorial (ver render_app_icon.swift). Compila en un directorio temporal
# (TMPDIR) con el swiftc de Xcode para macOS; no toca nada fuera del appiconset.
#   sh ios/Scripts/render_app_icon.sh [--preview <png>]
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
BRAND="$HERE/../ColorsApp/Design/Brand"
OUT="$HERE/../ColorsApp/Assets.xcassets/AppIcon.appiconset"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/render_app_icon.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
xcrun --sdk macosx swiftc -O -parse-as-library -swift-version 5 \
  "$BRAND/BrandKeyframes.swift" "$BRAND/BrandPalette.swift" "$BRAND/ChromaSolEmblem.swift" \
  "$HERE/render_app_icon.swift" -o "$WORK/render_app_icon"
"$WORK/render_app_icon" --out "$OUT" "$@"
