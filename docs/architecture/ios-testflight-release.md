# iOS TestFlight Release Pipeline

This document defines the production TestFlight release lane for the native iOS app.

## Goals

- Keep unsigned release archives available for local and CI symbolication rehearsal.
- Add a signed App Store Connect export path that can either produce an `.ipa` or upload directly to TestFlight.
- Keep Apple account credentials, signing certificates, provisioning profiles, and local team overrides outside the repository.
- Reuse the generated Xcode project and existing Rust/UniFFI release build path.

## Entry points

- `scripts/ios/archive_release.sh`
  - Default mode remains unsigned archive generation with `CODE_SIGNING_ALLOWED=NO`.
  - TestFlight mode is enabled by setting `CODE_SIGNING_ALLOWED=YES` plus `EXPORT_METHOD=app-store-connect`.
  - Direct upload is enabled with `TESTFLIGHT_UPLOAD=YES`; otherwise the script exports a signed `.ipa`.
- `.github/workflows/ios-release-artifacts.yml`
  - Manual unsigned archive/dSYM artifact generation.
- `.github/workflows/ios-testflight.yml`
  - Manual signed TestFlight archive/export/upload lane.

## Versioning

The app now has explicit version build settings:

- `FIRE_MARKETING_VERSION` maps to `MARKETING_VERSION` / `CFBundleShortVersionString`.
- `FIRE_BUILD_NUMBER` maps to `CURRENT_PROJECT_VERSION` / `CFBundleVersion`.
- `FIRE_GIT_SHA` maps to the generated `FireGitSha` Info.plist value.
- Defaults live in `native/ios-app/Configs/Fire-Shared.xcconfig`.
- CI passes both values into `archive_release.sh`; the TestFlight workflow defaults the build number to the GitHub run number if the dispatch input is empty.
- The iOS settings page displays the version, build number, and short git SHA when the build includes one.
- Release tags use `ios-v<version>-b<build>`, for example `ios-v0.1.0-b123`.
- `just ios-release-info <version> [build]` prints the version/build/hash/tag coordinates for local checks.
- `just ios-release-tag <version> <build>` creates the annotated release tag for the current commit; `just ios-release-tag-push <version> <build>` pushes it.

## Signing and credentials

The TestFlight workflow expects these repository secrets:

- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_PRIVATE_KEY`
- `APPLE_TEAM_ID`

These optional secrets support explicit local-keychain signing on GitHub runners:

- `APPLE_DISTRIBUTION_CERTIFICATE_BASE64`
- `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`
- `APPLE_PROVISIONING_PROFILE_BASE64`
- `APPLE_SIGNING_KEYCHAIN_PASSWORD`

These optional repository variables tune the signed export:

- `IOS_BUNDLE_ID`
- `IOS_CODE_SIGN_STYLE`
- `IOS_PROVISIONING_PROFILE_SPECIFIER`
- `IOS_EXPORT_SIGNING_CERTIFICATE`

No `.p8`, `.p12`, `.mobileprovision`, or local `Fire-Local-*.xcconfig` file should be committed.

## Output artifacts

`archive_release.sh` writes release artifacts under `artifacts/` by default:

- `Fire.xcarchive`
- `dSYMs/`
- `dSYMs.zip`, when dSYM bundles exist
- `ExportOptions.plist`, when export/upload is requested
- exported `.ipa`, when `EXPORT_DESTINATION=export`
- `build-metadata.json`

The metadata file records the git SHA, version, build number, archive path, export method, export destination, and IPA path when present.

## Local TestFlight rehearsal

Use local ignored signing config for developer-machine archives:

```bash
cp native/ios-app/Configs/Fire-Local-Release.example.xcconfig \
  native/ios-app/Configs/Fire-Local-Release.xcconfig
```

Then set the team, bundle id, and optional manual profile values in the ignored file.

To produce a signed App Store Connect `.ipa` without uploading:

```bash
CODE_SIGNING_ALLOWED=YES \
ALLOW_PROVISIONING_UPDATES=YES \
EXPORT_METHOD=app-store-connect \
FIRE_MARKETING_VERSION=0.1.0 \
FIRE_BUILD_NUMBER=1 \
./scripts/ios/archive_release.sh
```

To upload directly to TestFlight, also provide App Store Connect API key settings and set `TESTFLIGHT_UPLOAD=YES`.

## GitHub TestFlight dispatch

After the workflow has landed on the default branch, use these helpers:

```bash
just ios-testflight-dry-run 0.1.0
just ios-testflight-upload 0.1.0
```

Both commands leave `build_number` empty by default so GitHub Actions uses the run number. Pass an explicit build number when you need to align a build with a release tag:

```bash
just ios-release-tag 0.1.0 123
just ios-release-tag-push 0.1.0 123
just ios-testflight-upload 0.1.0 123 main true
```

## Guardrails

- The generated Xcode project stays derived from `native/ios-app/project.yml`.
- Release signing values flow through xcconfig settings or environment overrides, not manual edits to `Fire.xcodeproj`.
- The default archive script remains safe for CI artifact rehearsal because it does not sign or upload unless explicitly requested.
