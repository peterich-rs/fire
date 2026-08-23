#!/usr/bin/env bash
set -euo pipefail

# Decode FIRE_ANDROID_KEYSTORE_BASE64 into a local PKCS12/keystore file and
# export FIRE_ANDROID_STORE_FILE for Gradle. Used by CI release jobs.

if [[ -z "${FIRE_ANDROID_KEYSTORE_BASE64:-}" ]]; then
  echo "FIRE_ANDROID_KEYSTORE_BASE64 is required to prepare the Android release keystore" >&2
  exit 1
fi

if [[ -z "${FIRE_ANDROID_STORE_PASSWORD:-}" || -z "${FIRE_ANDROID_KEY_ALIAS:-}" || -z "${FIRE_ANDROID_KEY_PASSWORD:-}" ]]; then
  echo "FIRE_ANDROID_STORE_PASSWORD, FIRE_ANDROID_KEY_ALIAS, and FIRE_ANDROID_KEY_PASSWORD are required" >&2
  exit 1
fi

store_file="${FIRE_ANDROID_STORE_FILE:-${RUNNER_TEMP:-/tmp}/fire-release.p12}"
mkdir -p "$(dirname "$store_file")"

python3 - "$store_file" <<'PY'
import base64
import os
import pathlib
import sys

destination = pathlib.Path(sys.argv[1])
raw = os.environ["FIRE_ANDROID_KEYSTORE_BASE64"].strip()
if not raw:
    raise SystemExit("FIRE_ANDROID_KEYSTORE_BASE64 is empty")

try:
    payload = base64.b64decode(raw)
except Exception as exc:  # noqa: BLE001
    raise SystemExit(f"FIRE_ANDROID_KEYSTORE_BASE64 is not valid base64: {exc}") from exc

if not payload:
    raise SystemExit("FIRE_ANDROID_KEYSTORE_BASE64 decoded to an empty file")

destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_bytes(payload)
destination.chmod(0o600)
print(f"Wrote Android release keystore ({len(payload)} bytes)")
PY

if [[ -z "${JAVA_HOME:-}" && -x /usr/libexec/java_home ]]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || /usr/libexec/java_home)"
  export JAVA_HOME
fi
if [[ -x "${JAVA_HOME:-}/bin/keytool" ]]; then
  KEYTOOL="$JAVA_HOME/bin/keytool"
elif command -v keytool >/dev/null 2>&1; then
  KEYTOOL="$(command -v keytool)"
else
  echo "keytool is required to validate the decoded Android release keystore" >&2
  exit 1
fi

if ! "$KEYTOOL" -list \
  -keystore "$store_file" \
  -storepass "${FIRE_ANDROID_STORE_PASSWORD}" \
  -alias "${FIRE_ANDROID_KEY_ALIAS}" >/dev/null; then
  echo "Decoded keystore does not contain alias ${FIRE_ANDROID_KEY_ALIAS}" >&2
  exit 1
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "FIRE_ANDROID_STORE_FILE=${store_file}"
    echo "FIRE_ANDROID_REQUIRE_SIGNING=1"
  } >> "$GITHUB_ENV"
fi

export FIRE_ANDROID_STORE_FILE="$store_file"
export FIRE_ANDROID_REQUIRE_SIGNING="${FIRE_ANDROID_REQUIRE_SIGNING:-1}"
echo "FIRE_ANDROID_STORE_FILE=$store_file"
