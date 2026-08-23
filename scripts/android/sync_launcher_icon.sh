#!/usr/bin/env bash
set -euo pipefail

# Copy the iOS marketing App Icon into Android launcher resources.
# Source of truth: native/ios-app/App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT_DIR/native/ios-app/App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
RES="$ROOT_DIR/native/android-app/src/main/res"
FOREGROUND="$RES/drawable-nodpi/ic_launcher_foreground.png"

if [[ ! -f "$SRC" ]]; then
  echo "iOS app icon is missing: $SRC" >&2
  exit 1
fi

mkdir -p "$(dirname "$FOREGROUND")"
VECTOR_FOREGROUND="$RES/drawable/ic_launcher_foreground.xml"
if [[ -f "$VECTOR_FOREGROUND" ]]; then
  rm -f "$VECTOR_FOREGROUND"
fi

cp "$SRC" "$FOREGROUND"

resize_png() {
  local size="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if command -v sips >/dev/null 2>&1; then
    sips --setProperty format png --resampleHeightWidth "$size" "$size" "$SRC" --out "$dest" >/dev/null
  elif command -v magick >/dev/null 2>&1; then
    magick "$SRC" -resize "${size}x${size}" "$dest"
  else
    echo "sips or ImageMagick magick is required to generate density mipmaps" >&2
    exit 1
  fi
}

resize_png 48 "$RES/mipmap-mdpi/ic_launcher.png"
resize_png 72 "$RES/mipmap-hdpi/ic_launcher.png"
resize_png 96 "$RES/mipmap-xhdpi/ic_launcher.png"
resize_png 144 "$RES/mipmap-xxhdpi/ic_launcher.png"
resize_png 192 "$RES/mipmap-xxxhdpi/ic_launcher.png"

echo "Synced Android launcher icons from $SRC"
