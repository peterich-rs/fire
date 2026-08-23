#!/usr/bin/env bash
set -euo pipefail

# Generate a PKCS12 upload keystore for Fire Android release builds.
# Optionally write GitHub Actions secrets. The keystore itself is never committed.

usage() {
  cat <<'EOF'
Usage: scripts/android/generate_release_keystore.sh [--set-github-secrets] [--force]

Writes:
  ~/.fire/android/fire-release.p12
  ~/.fire/android/key.properties
  ~/.fire/android/README.txt

Options:
  --set-github-secrets  Upload FIRE_ANDROID_* secrets with `gh secret set`
  --force               Overwrite an existing local keystore
EOF
}

set_github_secrets=0
force=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --set-github-secrets) set_github_secrets=1 ;;
    --force) force=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ -z "${JAVA_HOME:-}" && -x /usr/libexec/java_home ]]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || /usr/libexec/java_home)"
  export JAVA_HOME
fi
if [[ -x "${JAVA_HOME:-}/bin/keytool" ]]; then
  KEYTOOL="$JAVA_HOME/bin/keytool"
elif command -v keytool >/dev/null 2>&1; then
  KEYTOOL="$(command -v keytool)"
else
  echo "keytool is required (JDK 17)" >&2
  exit 1
fi

output_dir="${FIRE_ANDROID_KEYSTORE_DIR:-$HOME/.fire/android}"
keystore_path="$output_dir/fire-release.p12"
properties_path="$output_dir/key.properties"
readme_path="$output_dir/README.txt"
alias_name="${FIRE_ANDROID_KEY_ALIAS:-fire}"

mkdir -p "$output_dir"
chmod 700 "$output_dir"

if [[ -f "$keystore_path" && "$force" -ne 1 ]]; then
  echo "Refusing to overwrite $keystore_path without --force" >&2
  exit 1
fi

store_password="$(python3 - <<'PY'
import secrets
alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
print("".join(secrets.choice(alphabet) for _ in range(32)))
PY
)"
key_password="$store_password"

"$KEYTOOL" -genkeypair \
  -keystore "$keystore_path" \
  -storetype PKCS12 \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias "$alias_name" \
  -storepass "$store_password" \
  -keypass "$key_password" \
  -dname "CN=Fire, OU=Mobile, O=peterich-rs, L=Unknown, ST=Unknown, C=CN"

chmod 600 "$keystore_path"

cat > "$properties_path" <<EOF
storeFile=$keystore_path
storePassword=$store_password
keyAlias=$alias_name
keyPassword=$key_password
EOF
chmod 600 "$properties_path"

cat > "$readme_path" <<EOF
Fire Android release upload keystore
Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Alias: $alias_name
Store: $keystore_path

Keep this directory private. Losing the keystore or rotating it after a Play
upload will block app updates. GitHub Actions secrets:

  FIRE_ANDROID_KEYSTORE_BASE64
  FIRE_ANDROID_STORE_PASSWORD
  FIRE_ANDROID_KEY_ALIAS
  FIRE_ANDROID_KEY_PASSWORD
EOF
chmod 600 "$readme_path"

echo "Generated $keystore_path"

if [[ "$set_github_secrets" -eq 1 ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh is required for --set-github-secrets" >&2
    exit 1
  fi
  python3 - "$keystore_path" <<'PY' | gh secret set FIRE_ANDROID_KEYSTORE_BASE64
import base64, pathlib, sys
print(base64.b64encode(pathlib.Path(sys.argv[1]).read_bytes()).decode("ascii"))
PY
  printf '%s' "$store_password" | gh secret set FIRE_ANDROID_STORE_PASSWORD
  printf '%s' "$alias_name" | gh secret set FIRE_ANDROID_KEY_ALIAS
  printf '%s' "$key_password" | gh secret set FIRE_ANDROID_KEY_PASSWORD
  echo "Configured GitHub Actions secrets FIRE_ANDROID_*"
fi
