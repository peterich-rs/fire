# Android Release Signing

Fire's Android release APK/AAB is signed with an upload keystore that lives
**outside the git tree**. GitHub Actions secrets feed CI and GitHub Release
packaging. Local machines can point Gradle at the same backup via
`native/android-app/key.properties`.

## Secrets

| Secret | Purpose |
| --- | --- |
| `FIRE_ANDROID_KEYSTORE_BASE64` | PKCS12 keystore bytes, base64-encoded |
| `FIRE_ANDROID_STORE_PASSWORD` | Keystore password |
| `FIRE_ANDROID_KEY_ALIAS` | Key alias (`fire`) |
| `FIRE_ANDROID_KEY_PASSWORD` | Key password |

CI release jobs decode the keystore with
`scripts/android/prepare_release_keystore.sh`, set
`FIRE_ANDROID_REQUIRE_SIGNING=1`, then run `assembleRelease` /
`bundleRelease`. `scripts/android/verify_release_apk.sh` rejects unsigned
packages.

## Local Backup

The generator writes a private backup to `~/.fire/android/`:

```bash
scripts/android/generate_release_keystore.sh --set-github-secrets
```

Keep `~/.fire/android/fire-release.p12` and `key.properties`. Losing this
keystore after a Play upload blocks updates. Do not commit `.p12`, `.jks`,
`.keystore`, or `key.properties`.

For a local signed release:

```bash
cp ~/.fire/android/key.properties native/android-app/key.properties
native/android-app/gradlew -p native/android-app assembleRelease bundleRelease
scripts/android/verify_release_apk.sh
```

`key.properties.example` documents the file shape. Gradle also accepts the
`FIRE_ANDROID_STORE_FILE`, `FIRE_ANDROID_STORE_PASSWORD`,
`FIRE_ANDROID_KEY_ALIAS`, and `FIRE_ANDROID_KEY_PASSWORD` environment
variables.

## Play Console

Upload the signed `.aab` from GitHub Release assets or a local
`bundleRelease`. The first Play upload of a given application id locks the
certificate; do not rotate the upload key without Play App Signing enrollment.
