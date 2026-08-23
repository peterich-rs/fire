#!/usr/bin/env bash
set -euo pipefail

# Verify that a Fire Android release APK is signed (v2/v3) and installable.

apk_path="${1:-}"
if [[ -z "$apk_path" ]]; then
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  mapfile -t apks < <(find "$repo_root/native/android-app/build/outputs/apk/release" -type f -name '*.apk' | sort)
  if [[ ${#apks[@]} -eq 0 ]]; then
    echo "No release APK found under native/android-app/build/outputs/apk/release" >&2
    exit 1
  fi
  apk_path="${apks[0]}"
fi

if [[ ! -f "$apk_path" ]]; then
  echo "APK not found: $apk_path" >&2
  exit 1
fi

sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "$sdk_root" ]]; then
  echo "ANDROID_SDK_ROOT or ANDROID_HOME is required to locate apksigner" >&2
  exit 1
fi

apksigner=""
if [[ -x "${ANDROID_HOME:-}/build-tools/35.0.0/apksigner" ]]; then
  apksigner="${ANDROID_HOME}/build-tools/35.0.0/apksigner"
elif [[ -x "${sdk_root}/build-tools/35.0.0/apksigner" ]]; then
  apksigner="${sdk_root}/build-tools/35.0.0/apksigner"
else
  apksigner="$(find "$sdk_root/build-tools" -name apksigner -type f | sort | tail -n 1 || true)"
fi

if [[ -z "$apksigner" || ! -x "$apksigner" ]]; then
  echo "apksigner not found under $sdk_root/build-tools" >&2
  exit 1
fi

echo "Verifying signed APK: $apk_path"
verify_log="$(mktemp)"
trap 'rm -f "$verify_log"' EXIT
if ! "$apksigner" verify --verbose --print-certs "$apk_path" >"$verify_log" 2>&1; then
  cat "$verify_log" >&2
  echo "Android release APK is unsigned or has an invalid signature" >&2
  exit 1
fi
cat "$verify_log"

if ! grep -Eq "Verified using v2 scheme \(APK Signature Scheme v2\): true|Verified using v3 scheme \(APK Signature Scheme v3\): true" "$verify_log"; then
  echo "Android release APK is missing APK Signature Scheme v2/v3" >&2
  exit 1
fi
