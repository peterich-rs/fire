#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <generated-kotlin-dir> <generated-jni-libs-dir>" >&2
  exit 1
fi

generated_kotlin_dir="$1"
generated_jni_libs_dir="$2"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../../.." && pwd)"
uniffi_config_path="$repo_root/rust/crates/fire-uniffi/uniffi.toml"
build_profile="${FIRE_BUILD_PROFILE:-debug}"
profile_dir="debug"
host_bindings_profile_dir="debug"

if [[ "$build_profile" == "release" ]]; then
  profile_dir="release"
fi

android_sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
android_ndk_version="${ANDROID_NDK_VERSION:-28.2.13676358}"
android_ndk_root="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-$android_sdk_root/ndk/$android_ndk_version}}"
if [[ "${FIRE_SKIP_RUST_CROSS_BUILD:-}" != "1" ]]; then
  toolchain_prebuilt_dir="$(find "$android_ndk_root/toolchains/llvm/prebuilt" -mindepth 1 -maxdepth 1 -type d | sort | head -n 1)"
  toolchain_bin_dir="$toolchain_prebuilt_dir/bin"
  llvm_ar="$toolchain_bin_dir/llvm-ar"

  if [[ ! -x "$llvm_ar" ]]; then
    echo "unable to locate llvm-ar under $android_ndk_root" >&2
    exit 1
  fi
fi

case "$(uname -s)" in
  Darwin)
    host_library_filename="libfire_uniffi.dylib"
    ;;
  Linux)
    host_library_filename="libfire_uniffi.so"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    host_library_filename="fire_uniffi.dll"
    ;;
  *)
    echo "unsupported host platform for UniFFI bindgen library resolution" >&2
    exit 1
    ;;
esac

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/fire-android-uniffi.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

rm -rf "$generated_kotlin_dir" "$generated_jni_libs_dir"
mkdir -p "$generated_kotlin_dir" "$generated_jni_libs_dir"

build_android_target() {
  local rust_target="$1"
  local abi_dir="$2"
  local triple_prefix="$3"
  local output_lib="$repo_root/rust/target/$rust_target/$profile_dir/libfire_uniffi.so"

  if [[ "${FIRE_SKIP_RUST_CROSS_BUILD:-}" != "1" ]]; then
    local clang="$toolchain_bin_dir/${triple_prefix}26-clang"
    local clangxx="$toolchain_bin_dir/${triple_prefix}26-clang++"
    local cargo_args=(build -p fire-uniffi --target "$rust_target")

    if [[ ! -x "$clang" || ! -x "$clangxx" ]]; then
      echo "unable to locate Android clang toolchain for $rust_target" >&2
      exit 1
    fi

    if [[ "$profile_dir" == "release" ]]; then
      cargo_args+=(--release)
    fi

    (
      cd "$repo_root"
      case "$rust_target" in
        aarch64-linux-android)
          export CC_aarch64_linux_android="$clang"
          export CXX_aarch64_linux_android="$clangxx"
          export AR_aarch64_linux_android="$llvm_ar"
          export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$clang"
          ;;
        x86_64-linux-android)
          export CC_x86_64_linux_android="$clang"
          export CXX_x86_64_linux_android="$clangxx"
          export AR_x86_64_linux_android="$llvm_ar"
          export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$clang"
          ;;
        *)
          echo "unsupported rust target: $rust_target" >&2
          exit 1
          ;;
      esac

      cargo "${cargo_args[@]}"
    )
  else
    if [[ ! -f "$output_lib" ]]; then
      echo "FIRE_SKIP_RUST_CROSS_BUILD=1 but $output_lib not found" >&2
      exit 1
    fi
    echo "skipping cargo build: using pre-built $output_lib"
  fi

  mkdir -p "$generated_jni_libs_dir/$abi_dir"
  cp "$output_lib" "$generated_jni_libs_dir/$abi_dir/libfire_uniffi.so"
}

(
  cd "$repo_root"
  # Generate Kotlin bindings from an unstripped host build. The workspace release
  # profile enables `strip = true`, which removes the UniFFI metadata from Linux
  # release host libraries and leaves bindgen with no Kotlin files to emit.
  cargo build -p fire-uniffi

  if [[ "$profile_dir" == "release" ]]; then
    cargo build -p fire-uniffi --release
  fi
  cargo run -p fire-uniffi --bin uniffi-bindgen -- generate \
    --library \
    --language kotlin \
    --no-format \
    --config "$uniffi_config_path" \
    --out-dir "$tmp_dir" \
    "rust/target/$host_bindings_profile_dir/$host_library_filename"
)

if ! find "$tmp_dir" -type f -name '*.kt' | grep -q .; then
  echo "unable to locate generated Kotlin bindings under $tmp_dir" >&2
  find "$tmp_dir" -maxdepth 6 -type f | sort >&2 || true
  exit 1
fi

cp -R "$tmp_dir"/. "$generated_kotlin_dir"/

build_android_target "aarch64-linux-android" "arm64-v8a" "aarch64-linux-android"
build_android_target "x86_64-linux-android" "x86_64" "x86_64-linux-android"
