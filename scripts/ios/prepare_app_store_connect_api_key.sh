#!/usr/bin/env bash
set -euo pipefail

# Write the App Store Connect API .p8 from env and export APP_STORE_CONNECT_API_KEY_PATH.

if [[ -z "${APP_STORE_CONNECT_API_KEY_ID:-}" || -z "${APP_STORE_CONNECT_API_ISSUER_ID:-}" || -z "${APP_STORE_CONNECT_API_PRIVATE_KEY:-}" ]]; then
  echo "APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_API_ISSUER_ID, and APP_STORE_CONNECT_API_PRIVATE_KEY are required" >&2
  exit 1
fi

key_dir="${RUNNER_TEMP:-/tmp}/app-store-connect"
key_path="${key_dir}/AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8"
mkdir -p "$key_dir"
printf '%s' "$APP_STORE_CONNECT_API_PRIVATE_KEY" > "$key_path"
chmod 600 "$key_path"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "APP_STORE_CONNECT_API_KEY_PATH=$key_path" >> "$GITHUB_ENV"
fi
export APP_STORE_CONNECT_API_KEY_PATH="$key_path"
echo "APP_STORE_CONNECT_API_KEY_PATH=$key_path"
