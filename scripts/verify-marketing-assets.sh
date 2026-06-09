#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MARKETING_ASSETS_ROOT="${FIRE_MARKETING_ASSETS_ROOT:-$ROOT_DIR}"
if [[ "$MARKETING_ASSETS_ROOT" != /* ]]; then
  MARKETING_ASSETS_ROOT="$ROOT_DIR/$MARKETING_ASSETS_ROOT"
fi

failure_count=0
dimension_tool_warned=0

fail() {
  failure_count=$((failure_count + 1))
  printf 'FAIL: %s\n' "$*" >&2
}

info() {
  printf 'INFO: %s\n' "$*"
}

warn_once_dimension_tool() {
  if [[ "$dimension_tool_warned" -eq 0 ]]; then
    dimension_tool_warned=1
    printf 'WARN: python3 and sips are unavailable; screenshot dimensions cannot be decoded.\n' >&2
  fi
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

asset_path() {
  printf '%s/%s' "$MARKETING_ASSETS_ROOT" "$1"
}

contains_fake_asset_marker() {
  local value
  value="$(lowercase "$1")"

  [[ "$value" =~ (^|[^[:alnum:]])(fake|mock|placeholder|dummy|synthetic)([^[:alnum:]]|$) ]] ||
    [[ "$value" =~ (^|[^[:alnum:]])(todo|tbd)([^[:alnum:]]|$) ]] ||
    [[ "$value" == *example.com* ]] ||
    [[ "$value" == *not-real* ]] ||
    [[ "$value" == *"not real"* ]]
}

validate_asset_filename() {
  local label="$1"
  local asset_file="$2"
  local filename

  filename="$(basename "$asset_file")"
  if contains_fake_asset_marker "$filename"; then
    fail "$label: asset filename must not contain fake, mock, placeholder, dummy, synthetic, TODO, TBD, example.com, not-real, or not real markers: $asset_file"
    return 1
  fi
}

image_dimensions() {
  local image_file="$1"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$image_file" <<'PY'
import sys
from pathlib import Path

data = Path(sys.argv[1]).read_bytes()

if data[:8] == b"\x89PNG\r\n\x1a\n":
    index = 8
    width = None
    height = None
    seen_idat = False
    seen_iend = False
    while index + 12 <= len(data):
        length = int.from_bytes(data[index:index + 4], "big")
        chunk_type = data[index + 4:index + 8]
        chunk_end = index + 12 + length
        if chunk_end > len(data):
            break
        if chunk_type == b"IHDR":
            if length != 13 or width is not None:
                break
            width = int.from_bytes(data[index + 8:index + 12], "big")
            height = int.from_bytes(data[index + 12:index + 16], "big")
        elif chunk_type == b"IDAT":
            seen_idat = True
        elif chunk_type == b"IEND":
            seen_iend = True
            break
        index = chunk_end

    if width is not None and height is not None and seen_idat and seen_iend:
        print(f"{width}x{height}")
        sys.exit(0)
    sys.exit(1)

if len(data) >= 4 and data[:2] == b"\xff\xd8":
    index = 2
    start_of_frame_markers = {
        0xC0,
        0xC1,
        0xC2,
        0xC3,
        0xC5,
        0xC6,
        0xC7,
        0xC9,
        0xCA,
        0xCB,
        0xCD,
        0xCE,
        0xCF,
    }
    while index < len(data):
        if data[index] != 0xFF:
            index += 1
            continue
        while index < len(data) and data[index] == 0xFF:
            index += 1
        if index >= len(data):
            break
        marker = data[index]
        index += 1
        if marker in (0xD8, 0xD9):
            continue
        if index + 2 > len(data):
            break
        length = int.from_bytes(data[index:index + 2], "big")
        if length < 2 or index + length > len(data):
            break
        if marker in start_of_frame_markers and length >= 7:
            height = int.from_bytes(data[index + 3:index + 5], "big")
            width = int.from_bytes(data[index + 5:index + 7], "big")
            print(f"{width}x{height}")
            sys.exit(0)
        index += length

sys.exit(1)
PY
    return $?
  fi

  if command -v sips >/dev/null 2>&1; then
    local sips_output
    if sips_output="$(sips -g pixelWidth -g pixelHeight "$image_file" 2>/dev/null)"; then
      local width
      local height
      width="$(printf '%s\n' "$sips_output" | awk '/pixelWidth:/ { print $2; exit }')"
      height="$(printf '%s\n' "$sips_output" | awk '/pixelHeight:/ { print $2; exit }')"
      if [[ -n "$width" && -n "$height" ]]; then
        printf '%sx%s\n' "$width" "$height"
        return 0
      fi
    fi
    return 1
  fi

  return 2
}

validate_image_file() {
  local label="$1"
  local image_file="$2"
  local expected_dimensions="${3:-}"
  local minimum_dimension="${4:-0}"
  local filename
  local extension

  filename="$(basename "$image_file")"
  extension="$(lowercase "${filename##*.}")"

  validate_asset_filename "$label" "$image_file" || return 1

  case "$extension" in
    png|jpg|jpeg)
      ;;
    *)
      fail "$label: unsupported image extension for $image_file; use .png, .jpg, or .jpeg"
      return 1
      ;;
  esac

  if [[ ! -s "$image_file" ]]; then
    fail "$label: image file is empty: $image_file"
    return 1
  fi

  local dimensions
  if dimensions="$(image_dimensions "$image_file")"; then
    if [[ ! "$dimensions" =~ ^[0-9]+x[0-9]+$ ]]; then
      fail "$label: could not parse image dimensions for $image_file"
      return 1
    fi

    local width="${dimensions%x*}"
    local height="${dimensions#*x}"
    if (( width <= 0 || height <= 0 )); then
      fail "$label: invalid image dimensions for $image_file: $dimensions"
      return 1
    fi

    if [[ -n "$expected_dimensions" && "$dimensions" != "$expected_dimensions" ]]; then
      fail "$label: expected $expected_dimensions, found $dimensions for $image_file"
      return 1
    fi

    if [[ "$minimum_dimension" =~ ^[0-9]+$ ]] &&
       (( minimum_dimension > 0 )) &&
       (( width < minimum_dimension || height < minimum_dimension )); then
      fail "$label: expected dimensions of at least ${minimum_dimension}px on each side, found $dimensions for $image_file"
      return 1
    fi

    info "$label: valid image $image_file ($dimensions)"
    return 0
  else
    local dimension_status=$?
    if [[ "$dimension_status" -eq 2 &&
          -z "$expected_dimensions" &&
          ( ! "$minimum_dimension" =~ ^[0-9]+$ || "$minimum_dimension" -eq 0 ) ]]; then
      warn_once_dimension_tool
      info "$label: accepted $image_file by extension and non-empty size only"
      return 0
    fi

    if [[ "$dimension_status" -eq 2 ]]; then
      if [[ -n "$expected_dimensions" ]]; then
        fail "$label: cannot verify required $expected_dimensions dimensions for $image_file because neither python3 nor sips is available"
      else
        fail "$label: cannot verify minimum ${minimum_dimension}px dimensions for $image_file because neither python3 nor sips is available"
      fi
    else
      fail "$label: could not read PNG or JPEG dimensions for $image_file"
    fi
    return 1
  fi
}

validate_screenshot_directory() {
  local label="$1"
  local directory="$2"
  local asset_count=0
  local valid_count=0
  local image_file

  if [[ ! -d "$directory" ]]; then
    fail "$label: screenshot directory is missing: $directory"
    return
  fi

  while IFS= read -r image_file; do
    asset_count=$((asset_count + 1))
    if validate_image_file "$label" "$image_file" "" 320; then
      valid_count=$((valid_count + 1))
    fi
  done < <(find "$directory" -maxdepth 1 -type f ! -name '.gitkeep' ! -name '.*' | sort)

  if [[ "$asset_count" -eq 0 ]]; then
    fail "$label: no final screenshots found in $directory"
    return
  fi

  if [[ "$valid_count" -eq 0 ]]; then
    fail "$label: no valid screenshots found in $directory"
  fi
}

validate_mp4_file() {
  local label="$1"
  local video_file="$2"
  local extension

  extension="$(lowercase "${video_file##*.}")"
  if [[ "$extension" != "mp4" ]]; then
    fail "$label: unsupported video extension for $video_file; use .mp4"
    return 1
  fi

  validate_asset_filename "$label" "$video_file" || return 1

  if command -v python3 >/dev/null 2>&1; then
    if python3 - "$video_file" <<'PY'
import sys
from pathlib import Path

data = Path(sys.argv[1]).read_bytes()
if len(data) >= 12 and data[4:8] == b"ftyp":
    sys.exit(0)
sys.exit(1)
PY
    then
      return 0
    fi
    fail "$label: MP4 file must contain an ftyp box near the start: $video_file"
    return 1
  fi

  if ! command -v od >/dev/null 2>&1; then
    fail "$label: cannot verify MP4 signature because neither python3 nor od is available"
    return 1
  fi

  local signature_text
  if ! signature_text="$(LC_ALL=C od -An -j4 -N4 -tc "$video_file" 2>/dev/null | tr -d ' \n')"; then
    fail "$label: cannot read MP4 signature for $video_file"
    return 1
  fi
  if [[ "$signature_text" != "ftyp" ]]; then
    fail "$label: MP4 file must contain an ftyp box near the start: $video_file"
    return 1
  fi
}

validate_optional_preview_video() {
  local directory
  directory="$(asset_path "native/ios-app/marketing/preview-video")"
  local video_file="$directory/app-preview.mp4"
  local other_file
  local unexpected_count=0

  if [[ ! -d "$directory" ]]; then
    fail "iOS App Preview video: preview-video directory is missing: $directory"
    return
  fi

  while IFS= read -r other_file; do
    if [[ "$other_file" != "$video_file" ]]; then
      unexpected_count=$((unexpected_count + 1))
      fail "iOS App Preview video: unexpected preview asset $other_file; use $video_file or leave only .gitkeep"
    fi
  done < <(find "$directory" -maxdepth 1 -type f ! -name '.gitkeep' ! -name '.*' | sort)

  if [[ ! -f "$video_file" ]]; then
    if [[ "$unexpected_count" -eq 0 ]]; then
      info "iOS App Preview video: optional $video_file is not present"
    fi
    return
  fi

  if [[ ! -s "$video_file" ]]; then
    fail "iOS App Preview video: video file is empty: $video_file"
    return
  fi
  validate_mp4_file "iOS App Preview video" "$video_file" || return

  info "iOS App Preview video: found optional $video_file"
}

validate_required_feature_graphic() {
  local graphic_file
  graphic_file="$(asset_path "native/android-app/marketing/feature-graphic.png")"
  local signature_hex

  if [[ ! -f "$graphic_file" ]]; then
    fail "Play Store feature graphic: required file is missing: $graphic_file"
    return
  fi

  if [[ ! -s "$graphic_file" ]]; then
    fail "Play Store feature graphic: image file is empty: $graphic_file"
    return
  fi
  validate_asset_filename "Play Store feature graphic" "$graphic_file" || return

  if ! command -v od >/dev/null 2>&1; then
    fail "Play Store feature graphic: cannot verify PNG signature because od is unavailable"
    return
  fi

  if ! signature_hex="$(LC_ALL=C od -An -N8 -tx1 "$graphic_file" 2>/dev/null | tr -d ' \n')"; then
    fail "Play Store feature graphic: cannot read PNG signature for $graphic_file"
    return
  fi
  if [[ "$signature_hex" != "89504e470d0a1a0a" ]]; then
    fail "Play Store feature graphic: file must be PNG content: $graphic_file"
    return
  fi

  validate_image_file "Play Store feature graphic" "$graphic_file" "1024x500" || true
}

ios_screenshot_sets=(
  "App Store iPhone 6.5 screenshots|$(asset_path "native/ios-app/marketing/screenshots/iPhone6.5")"
  "App Store iPhone 5.5 screenshots|$(asset_path "native/ios-app/marketing/screenshots/iPhone5.5")"
  "App Store iPad 12.9 screenshots|$(asset_path "native/ios-app/marketing/screenshots/iPad12.9")"
  "App Store iPad 11 screenshots|$(asset_path "native/ios-app/marketing/screenshots/iPad11")"
)

android_screenshot_sets=(
  "Play Store phone screenshots|$(asset_path "native/android-app/marketing/screenshots/phone")"
  "Play Store 7 inch tablet screenshots|$(asset_path "native/android-app/marketing/screenshots/tablet7")"
  "Play Store 10 inch tablet screenshots|$(asset_path "native/android-app/marketing/screenshots/tablet10")"
)

for entry in "${ios_screenshot_sets[@]}"; do
  IFS='|' read -r label directory <<< "$entry"
  validate_screenshot_directory "$label" "$directory"
done

validate_optional_preview_video

for entry in "${android_screenshot_sets[@]}"; do
  IFS='|' read -r label directory <<< "$entry"
  validate_screenshot_directory "$label" "$directory"
done

validate_required_feature_graphic

if [[ "$failure_count" -gt 0 ]]; then
  printf 'Marketing asset verification failed: %d failure(s)\n' "$failure_count" >&2
  exit 1
fi

printf 'Marketing asset verification passed.\n'
