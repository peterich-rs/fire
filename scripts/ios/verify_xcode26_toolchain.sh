#!/usr/bin/env bash
set -euo pipefail

developer_dir="$(xcode-select -p)"
xcode_version="$(xcodebuild -version | awk '/^Xcode / { print $2; exit }')"
iphoneos_sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"

echo "Selected DEVELOPER_DIR: $developer_dir"
echo "Selected Xcode: $xcode_version"
echo "Selected iPhoneOS SDK: $iphoneos_sdk_version"

if [[ -z "$xcode_version" || -z "$iphoneos_sdk_version" ]]; then
  echo "Failed to resolve the active Xcode toolchain or iPhoneOS SDK version" >&2
  exit 1
fi

xcode_major="${xcode_version%%.*}"
iphoneos_sdk_major="${iphoneos_sdk_version%%.*}"

if ! [[ "$xcode_major" =~ ^[0-9]+$ && "$iphoneos_sdk_major" =~ ^[0-9]+$ ]]; then
  echo "Unable to parse Xcode or iPhoneOS SDK major version" >&2
  exit 1
fi

if (( xcode_major < 26 )); then
  echo "App Store Connect uploads now require Xcode 26 or later; found Xcode $xcode_version" >&2
  exit 1
fi

if (( iphoneos_sdk_major < 26 )); then
  echo "App Store Connect uploads now require the iOS 26 SDK or later; found iPhoneOS SDK $iphoneos_sdk_version" >&2
  exit 1
fi
