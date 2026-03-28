#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="${SRCROOT:-$(cd -- "$script_dir/.." && pwd)}"
repo_root="$(cd -- "$project_root/../.." && pwd)"
generated_dir="$project_root/Generated"
swift_out_dir="$generated_dir"
ffi_out_dir="$generated_dir/fire_uniffiFFI"
lib_out_root="$generated_dir/lib"
uniffi_config_path="$repo_root/rust/crates/fire-uniffi/uniffi.toml"

export PATH="$HOME/.cargo/bin:$PATH"

cargo_bin="${CARGO:-$(command -v cargo || true)}"
rustup_bin="${RUSTUP:-$(command -v rustup || true)}"

if [[ -z "$cargo_bin" ]]; then
  echo "unable to locate cargo in PATH" >&2
  exit 1
fi

if [[ -z "$rustup_bin" ]]; then
  echo "unable to locate rustup in PATH" >&2
  exit 1
fi

platform_name="${PLATFORM_NAME:-iphonesimulator}"
configuration_name="${CONFIGURATION:-Debug}"
profile_dir="debug"

if [[ "$configuration_name" == "Release" ]]; then
  profile_dir="release"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/fire-ios-uniffi.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$swift_out_dir" "$ffi_out_dir" "$lib_out_root/$platform_name"
rm -f "$generated_dir/fire_uniffiFFI.h" "$generated_dir/fire_uniffiFFI.modulemap"

ensure_rust_target_installed() {
  local rust_target="$1"
  local installed_targets

  installed_targets="$(
    env \
      HOME="$HOME" \
      PATH="$PATH" \
      RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}" \
      "$rustup_bin" target list --installed
  )"

  if ! grep -qx "$rust_target" <<<"$installed_targets"; then
    echo "required Rust target is not installed: $rust_target" >&2
    echo "run: rustup target add $rust_target" >&2
    exit 1
  fi
}

map_simulator_arch_to_rust_target() {
  local arch="$1"

  case "$arch" in
    arm64)
      printf '%s\n' "aarch64-apple-ios-sim"
      ;;
    x86_64)
      printf '%s\n' "x86_64-apple-ios"
      ;;
    *)
      echo "unsupported iOS simulator arch: $arch" >&2
      exit 1
      ;;
  esac
}

declare -a rust_targets=()

case "$platform_name" in
  iphoneos)
    if [[ -z "${IPHONEOS_DEPLOYMENT_TARGET:-}" ]]; then
      export IPHONEOS_DEPLOYMENT_TARGET="17.0"
    fi
    rust_targets=("aarch64-apple-ios")
    ;;
  iphonesimulator)
    if [[ -n "${ARCHS:-}" ]]; then
      for arch in $ARCHS; do
        rust_targets+=("$(map_simulator_arch_to_rust_target "$arch")")
      done
    else
      case "$(uname -m)" in
        arm64)
          rust_targets=("aarch64-apple-ios-sim")
          ;;
        x86_64)
          rust_targets=("x86_64-apple-ios")
          ;;
        *)
          echo "unable to infer simulator Rust target from host architecture" >&2
          exit 1
          ;;
      esac
    fi
    ;;
  *)
    echo "unsupported PLATFORM_NAME: $platform_name" >&2
    exit 1
    ;;
esac

dedupe_targets() {
  local seen=""
  local rust_target
  local deduped=()

  for rust_target in "${rust_targets[@]}"; do
    if [[ " $seen " == *" $rust_target "* ]]; then
      continue
    fi

    seen+=" $rust_target"
    deduped+=("$rust_target")
  done

  rust_targets=("${deduped[@]}")
}

build_staticlib() {
  local rust_target="$1"

  if [[ "$profile_dir" == "release" ]]; then
    (
      cd "$repo_root"
      run_host_cargo "$cargo_bin" rustc -p fire-uniffi --lib --target "$rust_target" --release --crate-type staticlib
    )
  else
    (
      cd "$repo_root"
      run_host_cargo "$cargo_bin" rustc -p fire-uniffi --lib --target "$rust_target" --crate-type staticlib
    )
  fi
}

run_host_cargo() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    local sdk_root
    local host_cc
    local rustflags
    local library_path
    local iphoneos_deployment_target

    sdk_root="$(xcrun --sdk macosx --show-sdk-path)"
    host_cc="$(xcrun --sdk macosx --find clang)"
    rustflags="-C linker=${host_cc} -C link-arg=-isysroot -C link-arg=${sdk_root}"
    library_path="${sdk_root}/usr/lib"
    iphoneos_deployment_target="${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"

    env -i \
      HOME="$HOME" \
      PATH="$PATH" \
      SDKROOT="$sdk_root" \
      RUSTFLAGS="$rustflags" \
      LIBRARY_PATH="$library_path" \
      PLATFORM_NAME= \
      EFFECTIVE_PLATFORM_NAME= \
      ARCHS= \
      IPHONEOS_DEPLOYMENT_TARGET="$iphoneos_deployment_target" \
      TVOS_DEPLOYMENT_TARGET= \
      WATCHOS_DEPLOYMENT_TARGET= \
      "$@"
  else
    "$@"
  fi
}

dedupe_targets

(
  cd "$repo_root"
  if [[ "$profile_dir" == "release" ]]; then
    run_host_cargo "$cargo_bin" build -p fire-uniffi --lib --release
  else
    run_host_cargo "$cargo_bin" build -p fire-uniffi --lib
  fi
  run_host_cargo "$cargo_bin" run -p fire-uniffi --bin uniffi-bindgen -- generate \
    --library "$repo_root/rust/target/$profile_dir/libfire_uniffi.dylib" \
    --language swift \
    --no-format \
    --config "$uniffi_config_path" \
    --out-dir "$tmp_dir/bindings"
)

cp "$tmp_dir/bindings/fire_uniffi.swift" "$swift_out_dir/fire_uniffi.swift"
cp "$tmp_dir/bindings/fire_uniffiFFI.h" "$ffi_out_dir/fire_uniffiFFI.h"
cp "$tmp_dir/bindings/fire_uniffiFFI.modulemap" "$ffi_out_dir/module.modulemap"

declare -a built_libraries=()

for rust_target in "${rust_targets[@]}"; do
  build_staticlib "$rust_target"
  built_libraries+=("$repo_root/rust/target/$rust_target/$profile_dir/libfire_uniffi.a")
done

final_library_path="$lib_out_root/$platform_name/libfire_uniffi.a"

if [[ ${#built_libraries[@]} -eq 1 ]]; then
  cp "${built_libraries[0]}" "$final_library_path"
else
  simulator_library_path="$tmp_dir/libfire_uniffi.a"
  xcrun lipo -create "${built_libraries[@]}" -output "$simulator_library_path"
  cp "$simulator_library_path" "$final_library_path"
fi
