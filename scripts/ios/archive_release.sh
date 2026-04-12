#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/native/ios-app"
SCHEME="${SCHEME:-Fire}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-generic/platform=iOS}"
STAMP="$(date +"%Y%m%d-%H%M%S")"
OUT_ROOT="${OUT_ROOT:-$ROOT_DIR/artifacts/ios-release/$STAMP}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$OUT_ROOT/Fire.xcarchive}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$OUT_ROOT/DerivedData}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
GIT_SHA="${FIRE_GIT_SHA:-$(git -C "$ROOT_DIR" rev-parse HEAD)}"
METADATA_PATH="$OUT_ROOT/build-metadata.json"
DSYMS_DIR="$OUT_ROOT/dSYMs"

mkdir -p "$OUT_ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required but not installed" >&2
  exit 1
fi

pushd "$ROOT_DIR" >/dev/null
git submodule update --init --recursive
./scripts/check_clean_submodules.sh
popd >/dev/null

pushd "$ROOT_DIR" >/dev/null
xcodegen generate --spec native/ios-app/project.yml
popd >/dev/null

xcodebuild \
  -project "$IOS_DIR/Fire.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
  FIRE_GIT_SHA="$GIT_SHA" \
  archive

mkdir -p "$DSYMS_DIR"
if [[ -d "$ARCHIVE_PATH/dSYMs" ]]; then
  cp -R "$ARCHIVE_PATH/dSYMs/." "$DSYMS_DIR/"
fi

if [[ -d "$DSYMS_DIR" ]] && compgen -G "$DSYMS_DIR/*.dSYM" >/dev/null; then
  ditto -c -k --sequesterRsrc --keepParent "$DSYMS_DIR" "$OUT_ROOT/dSYMs.zip"
fi

cat >"$METADATA_PATH" <<EOF
{
  "scheme": "$SCHEME",
  "configuration": "$CONFIGURATION",
  "destination": "$DESTINATION",
  "git_sha": "$GIT_SHA",
  "archive_path": "$ARCHIVE_PATH",
  "derived_data_path": "$DERIVED_DATA_PATH",
  "code_signing_allowed": "$CODE_SIGNING_ALLOWED",
  "created_at_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo "archive_path=$ARCHIVE_PATH"
echo "metadata_path=$METADATA_PATH"
if [[ -f "$OUT_ROOT/dSYMs.zip" ]]; then
  echo "dsyms_zip=$OUT_ROOT/dSYMs.zip"
fi
