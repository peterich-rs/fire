#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT_DIR/native/ios-app/App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
FOREGROUND="$ROOT_DIR/native/android-app/src/main/res/drawable-nodpi/ic_launcher_foreground.png"
LAUNCHER_XML="$ROOT_DIR/native/android-app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
ROUND_XML="$ROOT_DIR/native/android-app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml"
COLORS="$ROOT_DIR/native/android-app/src/main/res/values/colors.xml"
VECTOR="$ROOT_DIR/native/android-app/src/main/res/drawable/ic_launcher_foreground.xml"

fail() {
  echo "$1" >&2
  exit 1
}

[[ -f "$SRC" ]] || fail "missing iOS AppIcon-1024.png"
[[ -f "$FOREGROUND" ]] || fail "missing Android drawable-nodpi/ic_launcher_foreground.png"
[[ ! -e "$VECTOR" ]] || fail "generic vector launcher foreground must not exist: $VECTOR"

if ! cmp -s "$SRC" "$FOREGROUND"; then
  fail "Android launcher foreground is not byte-identical to iOS AppIcon-1024.png"
fi

for xml in "$LAUNCHER_XML" "$ROUND_XML"; do
  grep -q 'android:drawable="@drawable/ic_launcher_foreground"' "$xml" \
    || fail "$xml must use @drawable/ic_launcher_foreground"
  grep -q 'android:drawable="@color/launcher_background"' "$xml" \
    || fail "$xml must use @color/launcher_background"
done

grep -Eq '<color name="launcher_background">#FFF4F3EF</color>' "$COLORS" \
  || fail "launcher_background must match the iOS icon cream (#F4F3EF)"

for rel in \
  mipmap-mdpi/ic_launcher.png \
  mipmap-hdpi/ic_launcher.png \
  mipmap-xhdpi/ic_launcher.png \
  mipmap-xxhdpi/ic_launcher.png \
  mipmap-xxxhdpi/ic_launcher.png
do
  [[ -f "$ROOT_DIR/native/android-app/src/main/res/$rel" ]] \
    || fail "missing density fallback $rel"
done

echo "Android launcher icon matches iOS AppIcon-1024.png"
