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
GIT_SHA="${FIRE_GIT_SHA:-$(git -C "$ROOT_DIR" rev-parse HEAD)}"
METADATA_PATH="$OUT_ROOT/build-metadata.json"
DSYMS_DIR="$OUT_ROOT/dSYMs"
EXPORT_METHOD="${EXPORT_METHOD:-}"
EXPORT_DESTINATION="${EXPORT_DESTINATION:-export}"
EXPORT_PATH="${EXPORT_PATH:-$OUT_ROOT/export}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-}"
TESTFLIGHT_UPLOAD="${TESTFLIGHT_UPLOAD:-NO}"
TESTFLIGHT_INTERNAL_ONLY="${TESTFLIGHT_INTERNAL_ONLY:-YES}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-NO}"
APP_STORE_CONNECT_API_KEY_PATH="${APP_STORE_CONNECT_API_KEY_PATH:-${ASC_API_KEY_PATH:-}}"
APP_STORE_CONNECT_API_KEY_ID="${APP_STORE_CONNECT_API_KEY_ID:-${ASC_API_KEY_ID:-}}"
APP_STORE_CONNECT_API_ISSUER_ID="${APP_STORE_CONNECT_API_ISSUER_ID:-${ASC_API_KEY_ISSUER_ID:-}}"
FIRE_UNIFFI_PLATFORM_NAME="${FIRE_UNIFFI_PLATFORM_NAME:-iphoneos}"
ARCHIVE_CODE_SIGN_IDENTITY="${FIRE_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-${EXPORT_SIGNING_CERTIFICATE:-}}}"

is_truthy() {
  case "${1:-}" in
    1 | true | TRUE | yes | YES | y | Y | on | ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if is_truthy "$TESTFLIGHT_UPLOAD"; then
  EXPORT_METHOD="${EXPORT_METHOD:-app-store-connect}"
  EXPORT_DESTINATION="upload"
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-YES}"
else
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
fi

if [[ -n "$EXPORT_METHOD" && "$EXPORT_METHOD" == "app-store" ]]; then
  echo "EXPORT_METHOD=app-store is deprecated by Xcode; use app-store-connect" >&2
  exit 1
fi

mkdir -p "$OUT_ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required but not installed" >&2
  exit 1
fi

prepare_uniffi_artifacts() {
  if is_truthy "${FIRE_SKIP_UNIFFI_PREPARE:-NO}"; then
    echo "FIRE_SKIP_UNIFFI_PREPARE=1: skipping UniFFI preparation before XcodeGen"
    return 0
  fi

  echo "Preparing UniFFI artifacts for $FIRE_UNIFFI_PLATFORM_NAME before XcodeGen"
  (
    cd "$IOS_DIR"
    SRCROOT="$IOS_DIR" \
      PLATFORM_NAME="$FIRE_UNIFFI_PLATFORM_NAME" \
      CONFIGURATION="$CONFIGURATION" \
      FIRE_SKIP_UNIFFI_BINDGEN= \
      ./scripts/sync_uniffi_bindings.sh
  )

  export FIRE_SKIP_UNIFFI_BINDGEN=1
}

pushd "$ROOT_DIR" >/dev/null
git submodule update --init --recursive
./scripts/check_clean_submodules.sh
popd >/dev/null

prepare_uniffi_artifacts

pushd "$ROOT_DIR" >/dev/null
xcodegen generate --spec native/ios-app/project.yml
popd >/dev/null

declare -a auth_args=()
if [[ -n "$APP_STORE_CONNECT_API_KEY_PATH" || -n "$APP_STORE_CONNECT_API_KEY_ID" || -n "$APP_STORE_CONNECT_API_ISSUER_ID" ]]; then
  if [[ -z "$APP_STORE_CONNECT_API_KEY_PATH" || -z "$APP_STORE_CONNECT_API_KEY_ID" || -z "$APP_STORE_CONNECT_API_ISSUER_ID" ]]; then
    echo "APP_STORE_CONNECT_API_KEY_PATH, APP_STORE_CONNECT_API_KEY_ID, and APP_STORE_CONNECT_API_ISSUER_ID must be set together" >&2
    exit 1
  fi

  auth_args=(
    -authenticationKeyPath "$APP_STORE_CONNECT_API_KEY_PATH"
    -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID"
    -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID"
  )
fi

declare -a provisioning_args=()
if is_truthy "$ALLOW_PROVISIONING_UPDATES"; then
  provisioning_args=(-allowProvisioningUpdates)
fi

declare -a build_setting_args=()
if [[ -n "${FIRE_MARKETING_VERSION:-}" ]]; then
  build_setting_args+=(FIRE_MARKETING_VERSION="$FIRE_MARKETING_VERSION")
fi
if [[ -n "${FIRE_BUILD_NUMBER:-}" ]]; then
  build_setting_args+=(FIRE_BUILD_NUMBER="$FIRE_BUILD_NUMBER")
fi
if [[ -n "${FIRE_DEVELOPMENT_TEAM:-}" ]]; then
  build_setting_args+=(FIRE_DEVELOPMENT_TEAM="$FIRE_DEVELOPMENT_TEAM")
fi
if [[ -n "${FIRE_PRODUCT_BUNDLE_IDENTIFIER:-}" ]]; then
  build_setting_args+=(FIRE_PRODUCT_BUNDLE_IDENTIFIER="$FIRE_PRODUCT_BUNDLE_IDENTIFIER")
fi
if [[ -n "${FIRE_CODE_SIGN_STYLE:-}" ]]; then
  build_setting_args+=(FIRE_CODE_SIGN_STYLE="$FIRE_CODE_SIGN_STYLE")
fi
if [[ -n "${FIRE_PROVISIONING_PROFILE_SPECIFIER:-}" ]]; then
  build_setting_args+=(FIRE_PROVISIONING_PROFILE_SPECIFIER="$FIRE_PROVISIONING_PROFILE_SPECIFIER")
fi
if [[ -n "$ARCHIVE_CODE_SIGN_IDENTITY" ]]; then
  build_setting_args+=(CODE_SIGN_IDENTITY="$ARCHIVE_CODE_SIGN_IDENTITY")
fi

declare -a archive_args=(xcodebuild)
if [[ ${#auth_args[@]} -gt 0 ]]; then
  archive_args+=("${auth_args[@]}")
fi
if [[ ${#provisioning_args[@]} -gt 0 ]]; then
  archive_args+=("${provisioning_args[@]}")
fi
archive_args+=(
  -project "$IOS_DIR/Fire.xcodeproj"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "$DESTINATION"
  -archivePath "$ARCHIVE_PATH"
  -derivedDataPath "$DERIVED_DATA_PATH"
  CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED"
  FIRE_GIT_SHA="$GIT_SHA"
)
if [[ ${#build_setting_args[@]} -gt 0 ]]; then
  archive_args+=("${build_setting_args[@]}")
fi
archive_args+=(
  archive
)

"${archive_args[@]}"

mkdir -p "$DSYMS_DIR"
if [[ -d "$ARCHIVE_PATH/dSYMs" ]]; then
  cp -R "$ARCHIVE_PATH/dSYMs/." "$DSYMS_DIR/"
fi

if [[ -d "$DSYMS_DIR" ]] && compgen -G "$DSYMS_DIR/*.dSYM" >/dev/null; then
  ditto -c -k --sequesterRsrc --keepParent "$DSYMS_DIR" "$OUT_ROOT/dSYMs.zip"
fi

write_export_options_plist() {
  local path="$1"
  mkdir -p "$(dirname "$path")"

  python3 - "$path" <<'PY'
import os
import plistlib
import sys


def truthy(name, default=False):
    value = os.environ.get(name)
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "y", "on"}


def optional(name):
    value = os.environ.get(name)
    return value if value else None


data = {
    "method": os.environ["EXPORT_METHOD"],
    "destination": os.environ.get("EXPORT_DESTINATION", "export"),
    "stripSwiftSymbols": truthy("STRIP_SWIFT_SYMBOLS", True),
    "uploadSymbols": truthy("UPLOAD_SYMBOLS", True),
    "manageAppVersionAndBuildNumber": truthy("MANAGE_APP_VERSION_AND_BUILD_NUMBER", False),
}

signing_style = optional("EXPORT_SIGNING_STYLE") or optional("FIRE_CODE_SIGN_STYLE")
if signing_style:
    data["signingStyle"] = signing_style.lower()

team_id = optional("EXPORT_TEAM_ID") or optional("FIRE_DEVELOPMENT_TEAM")
if team_id:
    data["teamID"] = team_id

bundle_id = optional("DISTRIBUTION_BUNDLE_IDENTIFIER") or optional("FIRE_PRODUCT_BUNDLE_IDENTIFIER")
profile = optional("EXPORT_PROVISIONING_PROFILE_SPECIFIER") or optional("FIRE_PROVISIONING_PROFILE_SPECIFIER")
if bundle_id and profile:
    data["provisioningProfiles"] = {bundle_id: profile}

certificate = optional("EXPORT_SIGNING_CERTIFICATE")
if certificate:
    data["signingCertificate"] = certificate

if os.environ.get("EXPORT_DESTINATION") == "upload" and os.environ.get("TESTFLIGHT_INTERNAL_ONLY") is not None:
    data["testFlightInternalTestingOnly"] = truthy("TESTFLIGHT_INTERNAL_ONLY")

with open(sys.argv[1], "wb") as fh:
    plistlib.dump(data, fh, sort_keys=False)
PY
}

IPA_PATH=""
if [[ -n "$EXPORT_METHOD" ]]; then
  if [[ -z "$EXPORT_OPTIONS_PLIST" ]]; then
    EXPORT_OPTIONS_PLIST="$OUT_ROOT/ExportOptions.plist"
    export EXPORT_METHOD EXPORT_DESTINATION TESTFLIGHT_INTERNAL_ONLY
    export EXPORT_SIGNING_STYLE EXPORT_TEAM_ID EXPORT_PROVISIONING_PROFILE_SPECIFIER
    export DISTRIBUTION_BUNDLE_IDENTIFIER EXPORT_SIGNING_CERTIFICATE
    export FIRE_CODE_SIGN_STYLE FIRE_DEVELOPMENT_TEAM FIRE_PRODUCT_BUNDLE_IDENTIFIER FIRE_PROVISIONING_PROFILE_SPECIFIER
    export MANAGE_APP_VERSION_AND_BUILD_NUMBER STRIP_SWIFT_SYMBOLS UPLOAD_SYMBOLS
    write_export_options_plist "$EXPORT_OPTIONS_PLIST"
  fi

  mkdir -p "$EXPORT_PATH"
  declare -a export_args=(xcodebuild)
  if [[ ${#auth_args[@]} -gt 0 ]]; then
    export_args+=("${auth_args[@]}")
  fi
  if [[ ${#provisioning_args[@]} -gt 0 ]]; then
    export_args+=("${provisioning_args[@]}")
  fi
  export_args+=(
    -exportArchive
    -archivePath "$ARCHIVE_PATH"
    -exportPath "$EXPORT_PATH"
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
  )

  "${export_args[@]}"

  if [[ "$EXPORT_DESTINATION" == "export" ]]; then
    IPA_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -name "*.ipa" -print -quit)"
  fi
fi

cat >"$METADATA_PATH" <<EOF
{
  "scheme": "$SCHEME",
  "configuration": "$CONFIGURATION",
  "destination": "$DESTINATION",
  "git_sha": "$GIT_SHA",
  "marketing_version": "${FIRE_MARKETING_VERSION:-}",
  "build_number": "${FIRE_BUILD_NUMBER:-}",
  "uniffi_platform_name": "$FIRE_UNIFFI_PLATFORM_NAME",
  "archive_code_sign_identity": "$ARCHIVE_CODE_SIGN_IDENTITY",
  "archive_path": "$ARCHIVE_PATH",
  "derived_data_path": "$DERIVED_DATA_PATH",
  "code_signing_allowed": "$CODE_SIGNING_ALLOWED",
  "export_method": "$EXPORT_METHOD",
  "export_destination": "$EXPORT_DESTINATION",
  "export_path": "$EXPORT_PATH",
  "export_options_plist": "$EXPORT_OPTIONS_PLIST",
  "ipa_path": "$IPA_PATH",
  "created_at_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo "archive_path=$ARCHIVE_PATH"
echo "metadata_path=$METADATA_PATH"
if [[ -f "$OUT_ROOT/dSYMs.zip" ]]; then
  echo "dsyms_zip=$OUT_ROOT/dSYMs.zip"
fi
if [[ -n "$IPA_PATH" ]]; then
  echo "ipa_path=$IPA_PATH"
fi
if [[ -n "$EXPORT_METHOD" ]]; then
  echo "export_options_plist=$EXPORT_OPTIONS_PLIST"
  echo "export_path=$EXPORT_PATH"
fi
