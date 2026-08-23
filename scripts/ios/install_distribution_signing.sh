#!/usr/bin/env bash
set -euo pipefail

# Install optional Apple Distribution .p12 and provisioning profile on the runner.

if [[ -n "${APPLE_DISTRIBUTION_CERTIFICATE_BASE64:-}" ]]; then
  if [[ -z "${APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD:-}" ]]; then
    echo "APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD is required when APPLE_DISTRIBUTION_CERTIFICATE_BASE64 is set" >&2
    exit 1
  fi

  keychain_password="${APPLE_SIGNING_KEYCHAIN_PASSWORD:-$(openssl rand -hex 16)}"
  keychain_path="${RUNNER_TEMP:-/tmp}/fire-signing.keychain-db"
  certificate_path="${RUNNER_TEMP:-/tmp}/apple-distribution.p12"

  printf '%s' "$APPLE_DISTRIBUTION_CERTIFICATE_BASE64" | base64 --decode > "$certificate_path"
  security create-keychain -p "$keychain_password" "$keychain_path"
  security set-keychain-settings -lut 21600 "$keychain_path"
  security unlock-keychain -p "$keychain_password" "$keychain_path"
  security import "$certificate_path" -P "$APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD" -A -f pkcs12 -k "$keychain_path"
  security list-keychains -d user -s "$keychain_path" "$HOME/Library/Keychains/login.keychain-db"
  security default-keychain -d user -s "$keychain_path"
  security set-key-partition-list -S apple-tool:,apple: -k "$keychain_password" "$keychain_path"

  identity_output="$(security find-identity -v -p codesigning "$keychain_path" || true)"
  echo "$identity_output"
  if grep -q "0 valid identities found" <<< "$identity_output"; then
    echo "Imported signing identity is missing a private key or is otherwise unusable. Export the Apple Distribution certificate as a .p12 that includes the private key." >&2
    exit 1
  fi
fi

if [[ -n "${APPLE_PROVISIONING_PROFILE_BASE64:-}" ]]; then
  profile_path="${RUNNER_TEMP:-/tmp}/Fire_App_Store.mobileprovision"
  profile_plist="${RUNNER_TEMP:-/tmp}/Fire_App_Store.mobileprovision.plist"
  profiles_dir="$HOME/Library/MobileDevice/Provisioning Profiles"

  printf '%s' "$APPLE_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$profile_path"
  security cms -D -i "$profile_path" > "$profile_plist"
  profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print UUID' "$profile_plist")"
  mkdir -p "$profiles_dir"
  cp "$profile_path" "$profiles_dir/${profile_uuid}.mobileprovision"
fi
