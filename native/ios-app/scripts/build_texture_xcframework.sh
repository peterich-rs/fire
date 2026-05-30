#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_ROOT="$IOS_ROOT/LocalPackages/TextureCore"
ARTIFACT_ROOT="$PACKAGE_ROOT/Artifacts"
OUTPUT_XCFRAMEWORK="$ARTIFACT_ROOT/AsyncDisplayKit.xcframework"

TEXTURE_VERSION="${TEXTURE_VERSION:-3.2.0}"
WORK_ROOT="${WORK_ROOT:-$IOS_ROOT/.build/texture-xcframework}"
SOURCE_ROOT="$WORK_ROOT/Texture-$TEXTURE_VERSION"
ARCHIVE_ROOT="$WORK_ROOT/archives"
REPO_URL="https://github.com/TextureGroup/Texture.git"

if [[ ! -d "$SOURCE_ROOT/.git" ]]; then
  rm -rf "$SOURCE_ROOT"
  git clone --depth 1 --branch "$TEXTURE_VERSION" "$REPO_URL" "$SOURCE_ROOT"
fi

rm -rf "$ARCHIVE_ROOT" "$OUTPUT_XCFRAMEWORK"
mkdir -p "$ARCHIVE_ROOT" "$ARTIFACT_ROOT"

COMMON_BUILD_SETTINGS=(
  SKIP_INSTALL=NO
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES
  CODE_SIGNING_ALLOWED=NO
  ONLY_ACTIVE_ARCH=NO
)

xcodebuild archive \
  -project "$SOURCE_ROOT/AsyncDisplayKit.xcodeproj" \
  -scheme AsyncDisplayKit \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_ROOT/AsyncDisplayKit-iOS" \
  "${COMMON_BUILD_SETTINGS[@]}"

xcodebuild archive \
  -project "$SOURCE_ROOT/AsyncDisplayKit.xcodeproj" \
  -scheme AsyncDisplayKit \
  -configuration Release \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "$ARCHIVE_ROOT/AsyncDisplayKit-iOS-Simulator" \
  "${COMMON_BUILD_SETTINGS[@]}"

xcodebuild -create-xcframework \
  -framework "$ARCHIVE_ROOT/AsyncDisplayKit-iOS.xcarchive/Products/Library/Frameworks/AsyncDisplayKit.framework" \
  -framework "$ARCHIVE_ROOT/AsyncDisplayKit-iOS-Simulator.xcarchive/Products/Library/Frameworks/AsyncDisplayKit.framework" \
  -output "$OUTPUT_XCFRAMEWORK"

cp "$SOURCE_ROOT/LICENSE" "$PACKAGE_ROOT/LICENSE-Texture-$TEXTURE_VERSION.txt"

echo "Texture $TEXTURE_VERSION XCFramework written to $OUTPUT_XCFRAMEWORK"
