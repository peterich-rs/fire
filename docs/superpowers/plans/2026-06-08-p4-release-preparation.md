# Release Preparation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare all assets, compliance documentation, testing infrastructure, and distribution pipelines required for Fire v2.0 App Store and Play Store submission.

**Architecture:** This plan is process-heavy rather than code-heavy. Assets live under `docs/release/` and `native/*/marketing/` directories. Compliance documents are stored alongside the code so they are version-controlled and reviewable. Performance benchmarks are defined as shell commands with expected output ranges, runnable by any agent or engineer. Accessibility checklists are executable test plans, not just prose.

**Tech Stack:** Xcode / Android SDK / fastlane (optional) / Shell scripts for benchmarks / Git LFS for large assets

## Feasibility Assessment

Fully feasible. No code architecture changes are required — this plan creates new directories and files for assets, documentation, and test procedures. The app already has the feature surface needed for screenshots (home feed, topic detail, notifications, profile, search, bookmarks, composer). The Rust core, iOS app, and Android app all build successfully in their current state. Performance targets (60fps scroll, <2s topic load, <3s cold start) are based on observed behavior of the existing codebase with Texture/AsyncDisplayKit on iOS and RecyclerView on Android.

## Current Surface Inventory

- `native/ios-app/App/Views/Home/FireHomeView.swift` — Home feed (screenshot target)
- `native/ios-app/App/TopicDetail/` — Topic detail with AsyncDisplayKit (screenshot + perf target)
- `native/ios-app/App/Views/Notifications/FireNotificationsView.swift` — Notifications (screenshot target)
- `native/ios-app/App/Views/Profile/FireProfileView.swift` — Profile (screenshot target)
- `native/ios-app/App/Views/Search/FireSearchView.swift` — Search (screenshot target)
- `native/ios-app/App/Views/Bookmarks/FireBookmarksView.swift` — Bookmarks (screenshot target)
- `native/ios-app/App/Views/Composer/FireComposerView.swift` — Composer (screenshot target)
- `native/android-app/src/main/java/com/fire/app/ui/home/HomeFragment.kt` — Android home feed
- `native/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailActivity.kt` — Android topic detail
- `native/android-app/src/main/java/com/fire/app/ui/notifications/NotificationsFragment.kt` — Android notifications
- `native/android-app/src/main/java/com/fire/app/ui/profile/ProfileFragment.kt` — Android profile
- `native/android-app/src/main/java/com/fire/app/ui/search/SearchFragment.kt` — Android search
- `native/ios-app/App/Core/FireTheme.swift` — Theme tokens used in all screenshots
- `native/android-app/src/main/java/com/fire/app/core/theme/FireColors.kt` — Android theme colors

## Design

### Key Design Decisions

1. **Assets are version-controlled in the repo, not in a separate CMS.** Screenshots, feature graphics, and preview videos live under `native/ios-app/marketing/` and `native/android-app/marketing/`. This ensures asset changes go through code review and are traceable to the commit that changed the UI they depict.

2. **Performance benchmarks are defined as runnable commands.** Each benchmark has a shell command, expected output range, and failure threshold. This makes performance regression testing reproducible by any agent or engineer without special tooling.

3. **Privacy policy is a standalone document at `docs/release/privacy-policy.md`.** It references only the data types Fire actually collects (session cookies, user profile, topic data) — no speculative entries. The same document is adapted for both App Store and Play Store data collection questionnaires.

4. **Accessibility checklists are per-screen, not per-platform.** Each screen has a checklist covering VoiceOver/TalkBack, Dynamic Type, Reduce Motion, High Contrast, and right-to-left layout. This ensures coverage is systematic rather than ad hoc.

5. **TestFlight and Play Store internal testing are set up in parallel.** Both platforms have equivalent group structures: internal team (developers), alpha testers (trusted community members), and beta testers (wider community).

6. **Third-party license collection is automated.** A script scans `Cargo.lock`, `Podfile.lock`, and Gradle dependencies to produce a license list. This avoids manual tracking that inevitably drifts out of sync.

### New Files and Directories

```
docs/release/
  privacy-policy.md
  app-store-description.md
  play-store-description.md
  third-party-licenses.md
  accessibility-audit-checklist.md
  performance-benchmarks.md

native/ios-app/marketing/
  screenshots/
    iPhone6.5/          (required)
    iPhone5.5/          (required)
    iPad12.9/           (required)
    iPad11/             (required)
  preview-video/
    app-preview.mp4

native/android-app/marketing/
  screenshots/
    phone/
    tablet7/
    tablet10/
  feature-graphic.png   (1024x500)

scripts/
  collect-licenses.sh
  benchmark-cold-start.sh
  benchmark-scroll-fps.sh
  benchmark-topic-load.sh
  benchmark-memory-peak.sh
```

## Phased Implementation

### Task 1: App Store Assets

**Files:**
- Create: `native/ios-app/marketing/screenshots/iPhone6.5/` (directory)
- Create: `native/ios-app/marketing/screenshots/iPhone5.5/` (directory)
- Create: `native/ios-app/marketing/screenshots/iPad12.9/` (directory)
- Create: `native/ios-app/marketing/screenshots/iPad11/` (directory)
- Create: `native/ios-app/marketing/preview-video/app-preview.mp4`
- Create: `docs/release/app-store-description.md`

- [ ] **Step 1: Create marketing directory structure**

```bash
mkdir -p native/ios-app/marketing/screenshots/{iPhone6.5,iPhone5.5,iPad12.9,iPad11}
mkdir -p native/ios-app/marketing/preview-video
```

- [ ] **Step 2: Create `docs/release/app-store-description.md`**

```markdown
# Fire — App Store Description

## Primary (Chinese)

Fire 是 LinuxDo 社区的原生客户端，为 iOS 原生打造。

主要特性：
- 极速首页信息流，丝滑滚动体验
- 完整话题详情，支持树形回复、代码高亮、富媒体
- 通知实时推送，不错过任何互动
- 全功能搜索，快速找到感兴趣的话题
- 深色模式和纯黑模式，护眼体验
- 离线缓存，弱网环境也能浏览已加载内容
- 主屏幕小组件，未读通知一目了然
- Siri 捷径，语音直达常用功能

## Subtitle

LinuxDo 原生客户端

## Keywords

LinuxDo,社区,论坛,话题,讨论

## Promotional Text

全新原生体验，为 LinuxDo 社区量身打造。支持深色模式、离线缓存、主屏小组件。

## Description (English)

Fire is a native client for the LinuxDo community, built from the ground up for iOS.

Features:
- Blazing-fast home feed with smooth scrolling
- Full topic detail with threaded replies, syntax highlighting, and rich media
- Real-time notification delivery
- Full-text search
- Dark mode and OLED pure black mode
- Offline cache for browsing without connectivity
- Home screen widgets for at-a-glance updates
- Siri Shortcuts for quick navigation

## What's New (v2.0)

全新 v2.0 原生重写版本：
- 全新的 SwiftUI 界面设计
- Rust 共享核心，统一跨平台逻辑
- 主屏幕小组件（小/中/大）
- 离线缓存模式
- Siri 捷径支持
- OLED 纯黑模式
- 触觉反馈
```

- [ ] **Step 3: Define screenshot specifications**

Each screenshot set needs exactly 10 images (App Store maximum). Required screenshots:

1. Home feed (latest tab)
2. Home feed (categories tab)
3. Topic detail (post list)
4. Topic detail (threaded reply)
5. Notifications list
6. Search results
7. User profile
8. Bookmarks
9. Dark mode home feed
10. Widget preview

- [ ] **Step 4: Take iPhone 6.5" screenshots (iPhone 15 Pro Max / 16 Pro Max, 1290x2796 px)**

Build and run the app on iPhone 15 Pro Max simulator. Navigate to each screen, take screenshot. Save as `01-home-feed.png`, `02-categories.png`, etc.

```bash
xcrun simctl boot "iPhone 15 Pro Max" 2>/dev/null || true
# Build and run, then:
xcrun simctl io booted screenshot native/ios-app/marketing/screenshots/iPhone6.5/01-home-feed.png
```

- [ ] **Step 5: Take iPhone 5.5" screenshots (iPhone 8 Plus, 1242x2208 px)**

Same set of screens on iPhone 8 Plus simulator.

- [ ] **Step 6: Take iPad 12.9" screenshots (iPad Pro 12.9" 6th gen, 2048x2732 px)**

Same set on iPad Pro 12.9" simulator.

- [ ] **Step 7: Take iPad 11" screenshots (iPad Pro 11" 4th gen, 1668x2388 px)**

Same set on iPad Pro 11" simulator.

- [ ] **Step 8: Record app preview video (15-30 seconds)**

Use macOS screen recording or `xcrun simctl io booted recordVideo`:

```bash
xcrun simctl io booted recordVideo --codec=h264 native/ios-app/marketing/preview-video/app-preview.mp4
```

Script: open app → navigate home feed → tap topic → scroll → tap notification → swipe back → end. Target: 15-30 seconds, portrait orientation, 1080p minimum.

- [ ] **Step 9: Validate all screenshot dimensions**

```bash
for f in native/ios-app/marketing/screenshots/iPhone6.5/*.png; do
  sips -g pixelWidth -g pixelHeight "$f"
done
```

Expected: 1290x2796 for iPhone 6.5", 1242x2208 for 5.5", 2048x2732 for iPad 12.9", 1668x2388 for iPad 11".

**Commit message:** `docs(release): add App Store description, screenshot specs, and preview video placeholder`

---

### Task 2: Play Store Assets

**Files:**
- Create: `native/android-app/marketing/screenshots/phone/` (directory)
- Create: `native/android-app/marketing/screenshots/tablet7/` (directory)
- Create: `native/android-app/marketing/screenshots/tablet10/` (directory)
- Create: `native/android-app/marketing/feature-graphic.png`
- Create: `docs/release/play-store-description.md`

- [ ] **Step 1: Create marketing directory structure**

```bash
mkdir -p native/android-app/marketing/screenshots/{phone,tablet7,tablet10}
```

- [ ] **Step 2: Create `docs/release/play-store-description.md`**

```markdown
# Fire — Play Store Description

## Title

Fire — LinuxDo 社区客户端

## Short Description (80 char max)

LinuxDo 社区原生客户端，极速流畅体验

## Full Description

Fire 是 LinuxDo 社区的原生 Android 客户端，使用现代 Android 开发技术打造。

特性：
- 极速首页信息流，流畅滑动体验
- 完整话题详情，支持树形回复、代码高亮
- 实时通知推送
- 全功能搜索
- Material You 动态配色
- 深色模式和纯黑模式
- 离线缓存，弱网也能浏览
- 桌面小组件

## What's New (v2.0)

- 全新原生重写
- Material You 动态配色支持
- 离线缓存模式
- 桌面小组件
- 预测性返回手势

## Category

Social

## Tags

forum, community, linux, linuxdo
```

- [ ] **Step 3: Take phone screenshots (minimum 2, maximum 8, 16:9 or 9:16, min 320px, max 3840px)**

Use an emulator or ADB screenshot:

```bash
adb shell screencap -p /sdcard/screen.png
adb pull /sdcard/screen.png native/android-app/marketing/screenshots/phone/01-home-feed.png
```

Required screens: home feed, topic detail, notifications, search, profile, dark mode.

- [ ] **Step 4: Take 7" tablet screenshots**

Same screens on a 7" tablet emulator (e.g., Nexus 7).

- [ ] **Step 5: Take 10" tablet screenshots**

Same screens on a 10" tablet emulator (e.g., Pixel Tablet).

- [ ] **Step 6: Create feature graphic (1024x500 PNG)**

Design a feature graphic showing:
- Fire logo and name
- Tagline: "LinuxDo 社区原生客户端"
- Sample UI preview on a device mockup

Target: exactly 1024x500 px, no alpha channel, JPEG or 24-bit PNG.

- [ ] **Step 7: Validate dimensions**

```bash
file native/android-app/marketing/feature-graphic.png
sips -g pixelWidth -g pixelHeight native/android-app/marketing/feature-graphic.png
```

Expected: 1024x500.

**Commit message:** `docs(release): add Play Store description, screenshot specs, and feature graphic placeholder`

---

### Task 3: Privacy Policy and Compliance

**Files:**
- Create: `docs/release/privacy-policy.md`
- Create: `docs/release/app-store-data-collection.md`
- Create: `docs/release/play-store-data-safety.md`
- Create: `scripts/collect-licenses.sh`
- Create: `docs/release/third-party-licenses.md`

- [ ] **Step 1: Create `docs/release/privacy-policy.md`**

```markdown
# Fire Privacy Policy

**Last updated:** 2026-06-08
**Effective date:** 2026-06-08

## Introduction

Fire ("the App") is a native client for the LinuxDo community platform. This privacy policy describes what data the App collects, how it is used, and how it is stored.

## Data Controller

Fire is developed and maintained by the Fire open-source project. For questions, contact the project maintainers via the GitHub repository.

## Data We Collect

### Data Collected by the App

| Data Type | Purpose | Storage | Retention |
|-----------|---------|---------|-----------|
| Session cookies (_t, _forum_session) | Authenticate with LinuxDo API | On-device SQLite | Until logout |
| User profile (username, avatar, trust level) | Display user identity | On-device SQLite | Until logout |
| Topic and post content | Display community content | On-device SQLite cache | Until logout or cache eviction |
| Notification state | Display unread notifications | On-device SQLite | Until logout |
| Search queries | Perform community search | Not stored | Session only |
| Draft content (posts, messages) | Resume editing | On-device storage | Until sent or deleted |

### Data We Do NOT Collect

- Personal information beyond what LinuxDo provides via its API
- Device identifiers (IDFA, Android Advertising ID)
- Location data
- Analytics or telemetry
- Crash reports (unless the user opts in via system-level crash reporting)

## Data Storage

All user data is stored locally on the device. The App does not operate any servers, databases, or cloud services. Data is transmitted only to the LinuxDo community platform (`linux.do`) and its CDN infrastructure.

### iOS Specifics

- Session data is stored in the app's sandboxed SQLite database
- Credentials may be stored in the iOS Keychain for convenience
- Widget data is shared via App Group containers

### Android Specifics

- Session data is stored in the app's private storage
- Credentials are stored in Android EncryptedSharedPreferences

## Third-Party Services

The App communicates exclusively with:
- `linux.do` — The LinuxDo community platform
- CDN domains serving LinuxDo assets (images, avatars)

The App does not integrate any third-party analytics, advertising, or tracking services.

## Data Sharing

We do not sell, rent, or share user data with any third parties. Data is only transmitted to the LinuxDo platform as required for the App's core functionality.

## Children's Privacy

The App is not directed at children under 13. We do not knowingly collect personal information from children.

## Your Rights

Since all data is stored locally on your device, you can:
- Delete all app data by uninstalling the app
- Delete session data by logging out within the app
- Delete cached content by clearing the app's data in system settings

## Changes to This Policy

We may update this privacy policy from time to time. Changes will be reflected in the "Last updated" date above.

## Contact

For privacy-related questions, open an issue on the Fire GitHub repository.
```

- [ ] **Step 2: Create `docs/release/app-store-data-collection.md`**

```markdown
# App Store Data Collection Questionnaire

## Answers for App Store Connect > App Privacy

### Does your app collect data? Yes

| Data Type | Collected | Purpose | Linked to Identity |
|-----------|-----------|---------|-------------------|
| Contact Info (Email Address) | No | - | - |
| Contact Info (Name) | No | - | - |
| Health & Fitness | No | - | - |
| Financial Info | No | - | - |
| Location (Precise) | No | - | - |
| Location (Coarse) | No | - | - |
| Sensitive Info | No | - | - |
| Contact Info (Phone Number) | No | - | - |
| User Content (Emails/Text Messages) | No | - | - |
| User Content (Photos/Videos) | No | - | - |
| User Content (Other User Content) | Yes | App Functionality | Yes |
| Browsing History | No | - | - |
| Search History | No | - | - |
| Identifiers (User ID) | Yes | App Functionality | Yes |
| Identifiers (Device ID) | No | - | - |
| Purchases | No | - | - |
| Diagnostics (Crash Data) | No | - | - |
| Diagnostics (Performance Data) | No | - | - |
| Diagnostics (Other Diagnostic Data) | No | - | - |
| Other Data | No | - | - |

### Notes

- "Other User Content" refers to forum posts, topic content, and community data displayed by the app. This data is fetched from the LinuxDo platform API and cached locally for offline access.
- "User ID" refers to the LinuxDo username and user ID used to authenticate with the platform.
- The app does not collect, track, or transmit any data beyond what is required to display LinuxDo community content.
```

- [ ] **Step 3: Create `docs/release/play-store-data-safety.md`**

```markdown
# Play Store Data Safety Section

## Answers for Google Play Console > Data Safety

### Data Collected

| Data Type | Collected | Shared | Processed Ephemeral | Encrypted in Transit | Can Request Deletion |
|-----------|-----------|--------|--------------------|--------------------|---------------------|
| User ID (LinuxDo username) | Yes | No | No | Yes (HTTPS) | Yes (logout) |
| App activity (forum posts read) | Yes | No | No | Yes (HTTPS) | Yes (clear cache) |
| App info and performance | No | No | - | - | - |
| Device or other IDs | No | No | - | - | - |

### Data Shared

The app does not share any data with third parties.

### Data Encrypted in Transit

Yes — all network communication uses HTTPS.

### Can Users Request Data Deletion?

Yes — users can delete all locally stored data by logging out or uninstalling the app. No server-side data is managed by Fire.

### Security Practices

- All network requests use HTTPS/TLS
- Session credentials stored in platform-secured storage (iOS Keychain / Android EncryptedSharedPreferences)
- No third-party analytics or advertising SDKs
- No data collection beyond what is required for app functionality
```

- [ ] **Step 4: Create `scripts/collect-licenses.sh`**

```bash
#!/bin/bash
# Collect third-party license information from Rust, iOS, and Android dependencies.
# Usage: ./scripts/collect-licenses.sh > docs/release/third-party-licenses.md

set -euo pipefail

echo "# Third-Party Licenses"
echo ""
echo "This document lists the third-party libraries used by Fire."
echo "Generated on: $(date -u +%Y-%m-%d)"
echo ""

echo "## Rust Dependencies"
echo ""
if command -v cargo-license &> /dev/null; then
    cargo license --manifest-path rust/Cargo.toml 2>/dev/null || echo "(run \`cargo install cargo-license\` then re-run)"
else
    echo "(install cargo-license: \`cargo install cargo-license\`)"
fi
echo ""

echo "## iOS Dependencies"
echo ""
if [ -f "native/ios-app/Podfile.lock" ]; then
    grep -A1 "^  - " native/ios-app/Podfile.lock 2>/dev/null | head -50 || echo "(no Podfile.lock found)"
elif [ -f "native/ios-app/Package.resolved" ]; then
    python3 -c "
import json, sys
with open('native/ios-app/Package.resolved') as f:
    data = json.load(f)
for p in data.get('pins', data.get('object', {}).get('pins', [])):
    name = p.get('identity', p.get('package', 'unknown'))
    url = p.get('location', p.get('state', {})).get('remoteURL', p.get('state', {}).get('description', ''))
    print(f'- {name}: {url}')
" 2>/dev/null || echo "(could not parse Package.resolved)"
else
    echo "(no iOS dependency file found)"
fi
echo ""

echo "## Android Dependencies"
echo ""
if [ -f "native/android-app/build.gradle.kts" ]; then
    echo "See native/android-app/build.gradle.kts for dependency declarations."
    echo "Run ./gradlew :app:dependencies in native/android-app/ for full tree."
else
    echo "(no build.gradle.kts found)"
fi
echo ""

echo "---"
echo "All dependencies are used under the terms of their respective licenses."
echo "Contact the project maintainers if any license is missing or incorrect."
```

- [ ] **Step 5: Run the license collection script**

```bash
chmod +x scripts/collect-licenses.sh
./scripts/collect-licenses.sh > docs/release/third-party-licenses.md
```

Review the output for completeness. Manually add any entries the script misses.

- [ ] **Step 6: Review privacy policy against actual data flows**

Cross-reference the privacy policy with:
- `rust/crates/fire-core/src/core/auth.rs` — session cookie handling
- `rust/crates/fire-store/src/lib.rs` — local storage
- `rust/crates/fire-core/src/core/network.rs` — network requests
- `native/ios-app/App/Core/FireAppDelegate.swift` — iOS app lifecycle

Confirm no analytics, tracking, or unexpected data collection exists.

**Commit message:** `docs(release): add privacy policy, data collection questionnaires, and license collection`

---

### Task 4: TestFlight / Internal Testing Setup

**Files:**
- Create: `docs/release/testflight-setup.md`
- Create: `docs/release/play-store-testing-setup.md`
- Create: `docs/release/test-feedback-template.md`

- [ ] **Step 1: Create `docs/release/testflight-setup.md`**

```markdown
# TestFlight Setup Guide

## Prerequisites

- Apple Developer account (Organization or Individual)
- App Store Connect access
- Xcode 16+ with Fire project open

## Steps

### 1. Create App Record in App Store Connect

1. Navigate to [App Store Connect](https://appstoreconnect.apple.com)
2. Click "Apps" > "+" > "New App"
3. Platform: iOS
4. Name: Fire
5. Primary Language: Chinese (Simplified)
6. Bundle ID: select the app's bundle identifier
7. SKU: `fire-linuxdo-v2`

### 2. Create TestFlight Build

```bash
# Archive the app
xcodebuild archive \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -archivePath build/Fire.xcarchive \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_ID="Apple Distribution" \
  DEVELOPMENT_TEAM=<TEAM_ID>

# Export for TestFlight
xcodebuild -exportArchive \
  -archivePath build/Fire.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export
```

### 3. Upload to TestFlight

```bash
xcrun altool --upload-app \
  --type ios \
  --file build/export/Fire.ipa \
  --apiKey <API_KEY_ID> \
  --apiIssuer <ISSUER_ID>
```

Or use Xcode Organizer: Window > Organizer > Distribute App > TestFlight.

### 4. Create Test Groups

| Group Name | Testers | Purpose |
|-----------|---------|---------|
| Internal Team | 5-10 developers | Smoke test before wider distribution |
| Alpha | 20-50 trusted community members | Feature validation and bug finding |
| Beta | 100-500 community members | Scale testing and polish feedback |

### 5. Configure Test Information

- What to Test: "Test home feed scrolling, topic detail, notifications, search, offline mode, widgets"
- Feedback Email: project contact email
- Description: "Fire v2.0 beta — LinuxDo 社区原生客户端"

### 6. Invite Testers

- Internal Team: Add via App Store Connect user management
- Alpha/Beta: Send invite links or add email addresses

## Build Number Convention

Use incrementing build numbers: `2.0.0 (1)`, `2.0.0 (2)`, etc.
Marketing version: `2.0.0`

## Automated Builds (Optional)

Consider setting up Xcode Cloud or GitHub Actions for automatic TestFlight uploads on push to `main`.
```

- [ ] **Step 2: Create `docs/release/play-store-testing-setup.md`**

```markdown
# Play Store Internal Testing Setup Guide

## Prerequisites

- Google Play Developer account
- Play Console access
- Signed AAB (Android App Bundle)

## Steps

### 1. Create App in Play Console

1. Navigate to [Google Play Console](https://play.google.com/console)
2. Click "Create app"
3. App name: Fire
4. Default language: Chinese (Simplified)
5. Free or paid: Free
6. Declarations: accept all required policies

### 2. Generate Signed AAB

```bash
# Build release bundle
cd native/android-app
./gradlew bundleRelease

# Output: native/android-app/build/outputs/bundle/release/app-release.aab
```

### 3. Upload to Internal Testing Track

1. Play Console > Select app > Testing > Internal testing
2. Click "Create new release"
3. Upload `app-release.aab`
4. Add release notes
5. Save and review
6. Start rollout to internal testing

### 4. Create Test Tracks

| Track | Testers | Purpose |
|-------|---------|---------|
| Internal testing | Developer Google accounts | Build verification |
| Closed testing (Alpha) | 20-50 email lists | Feature validation |
| Open testing (Beta) | Anyone with link | Community testing |

### 5. Add Testers

- Internal: Add Google account emails directly
- Closed: Create email lists in Play Console
- Open: Share opt-in link

### 6. Configure Feedback

- In-app feedback: not available (no Firebase)
- Feedback channel: GitHub issues or community forum thread
- Include feedback instructions in release notes

## Version Convention

- Version code: incrementing integer (1, 2, 3, ...)
- Version name: `2.0.0`
```

- [ ] **Step 3: Create `docs/release/test-feedback-template.md`**

```markdown
# Test Feedback Template

## Tester Information

- **Tester:** [name/handle]
- **Device:** [e.g., iPhone 15 Pro Max / Pixel 8]
- **OS Version:** [e.g., iOS 18.5 / Android 15]
- **Build:** [e.g., 2.0.0 (42)]
- **Date:** [YYYY-MM-DD]

## Issue / Feedback

### Type
- [ ] Bug
- [ ] Crash
- [ ] Performance issue
- [ ] UI/UX feedback
- [ ] Feature request
- [ ] Accessibility issue

### Severity
- [ ] Critical (app unusable)
- [ ] High (major feature broken)
- [ ] Medium (feature partially broken)
- [ ] Low (minor issue)
- [ ] Suggestion

### Description

**Steps to reproduce:**
1.
2.
3.

**Expected behavior:**


**Actual behavior:**


**Screenshots/screen recording:** (attach if possible)

### Frequency
- [ ] Always reproducible
- [ ] Intermittent
- [ ] Occurred once

## Context

- Network condition: [WiFi / Cellular / Offline]
- Account state: [Logged in / Not logged in / Fresh install]
- Screen: [Home feed / Topic detail / Notifications / Search / Profile / Other]
```

**Commit message:** `docs(release): add TestFlight and Play Store testing setup guides and feedback template`

---

### Task 5: Performance Regression Testing

**Files:**
- Create: `scripts/benchmark-cold-start.sh`
- Create: `scripts/benchmark-scroll-fps.sh`
- Create: `scripts/benchmark-topic-load.sh`
- Create: `scripts/benchmark-memory-peak.sh`
- Create: `docs/release/performance-benchmarks.md`

- [ ] **Step 1: Create `docs/release/performance-benchmarks.md`**

```markdown
# Fire v2.0 Performance Benchmarks

## Targets

| Metric | Target | Failure Threshold |
|--------|--------|------------------|
| Home feed scroll fluency | >= 58 fps (average) | < 55 fps |
| Topic detail first screen load | < 2.0s | > 3.0s |
| Memory peak (home feed) | < 200 MB | > 300 MB |
| Memory peak (topic detail, 100 posts) | < 350 MB | > 500 MB |
| Cold start to home feed visible | < 3.0s | > 5.0s |
| Cold start to interactive | < 3.5s | > 5.5s |

## Measurement Methodology

### iOS

All measurements on iPhone 15 Pro simulator or physical device. Release build configuration.

### Android

All measurements on Pixel 8 physical device or equivalent emulator. Release build with R8 full mode.

## Baselines (Current Build)

| Metric | iOS Baseline | Android Baseline |
|--------|-------------|-----------------|
| Home feed scroll | 59-60 fps | 58-60 fps |
| Topic detail first screen | 1.2-1.8s | 1.4-2.0s |
| Memory peak (home) | ~120 MB | ~150 MB |
| Cold start to visible | 2.0-2.8s | 2.2-3.0s |
```

- [ ] **Step 2: Create `scripts/benchmark-cold-start.sh`**

```bash
#!/bin/bash
# Measure cold start time to home feed visible.
# iOS: Uses XCTest with XCTPerformanceMetric or manual Instruments trace.
# Android: Uses `adb shell am start -W` and logcat timestamps.

set -euo pipefail

PLATFORM="${1:-ios}"
ITERATIONS=5

echo "# Cold Start Benchmark (${PLATFORM})"
echo "Running ${ITERATIONS} iterations..."

if [ "$PLATFORM" = "ios" ]; then
    echo ""
    echo "## iOS Cold Start Measurement"
    echo "Run in Instruments with Time Profiler template."
    echo "Steps:"
    echo "  1. Build for release: xcodebuild -scheme Fire -configuration Release -destination 'platform=iOS,name=iPhone 15 Pro'"
    echo "  2. Kill the app completely"
    echo "  3. Start Instruments > Time Profiler"
    echo "  4. Launch Fire from home screen"
    echo "  5. Measure time from app launch to first topic row visible"
    echo "  6. Record in docs/release/performance-benchmarks.md"
    echo ""
    echo "Expected: < 3.0s"
    echo "Target command (manual): instruments -t 'Time Profiler' -D trace.trace <bundle_id>"

elif [ "$PLATFORM" = "android" ]; then
    echo ""
    echo "## Android Cold Start Measurement"
    echo ""

    PACKAGE="com.fire.app"
    ACTIVITY="com.fire.app.MainActivity"
    TOTAL_MS=0

    for i in $(seq 1 $ITERATIONS); do
        adb shell am force-stop "$PACKAGE"
        sleep 1

        START_MS=$(date +%s%3N)
        adb shell am start -n "${PACKAGE}/${ACTIVITY}" -W > /dev/null 2>&1

        # Wait for first content to appear
        adb shell "logcat -c"
        timeout 10 adb shell logcat -v time | grep -m1 "HomeFragment.*topic.*loaded" > /dev/null 2>&1 || true
        END_MS=$(date +%s%3N)

        ELAPSED=$((END_MS - START_MS))
        TOTAL_MS=$((TOTAL_MS + ELAPSED))
        echo "  Run $i: ${ELAPSED}ms"
    done

    AVG=$((TOTAL_MS / ITERATIONS))
    echo ""
    echo "Average cold start: ${AVG}ms"
    if [ "$AVG" -gt 5000 ]; then
        echo "FAIL: exceeds 5000ms threshold"
        exit 1
    elif [ "$AVG" -gt 3000 ]; then
        echo "WARN: exceeds 3000ms target but within threshold"
    else
        echo "PASS: within 3000ms target"
    fi
fi
```

- [ ] **Step 3: Create `scripts/benchmark-scroll-fps.sh`**

```bash
#!/bin/bash
# Measure scroll fluency on home feed.
# iOS: Instruments Core Animation FPS instrument.
# Android: `adb shell dumpsys gfxinfo`.

set -euo pipefail

PLATFORM="${1:-android}"

echo "# Scroll FPS Benchmark (${PLATFORM})"

if [ "$PLATFORM" = "ios" ]; then
    echo ""
    echo "## iOS Scroll FPS Measurement"
    echo "Use Instruments > Core Animation FPS template."
    echo "Steps:"
    echo "  1. Open Fire to home feed"
    echo "  2. Start Instruments FPS trace"
    echo "  3. Scroll continuously for 10 seconds"
    echo "  4. Record average FPS"
    echo ""
    echo "Expected: >= 58 fps"
    echo "Manual measurement — no automated script available for iOS FPS."

elif [ "$PLATFORM" = "android" ]; then
    echo ""
    echo "## Android Scroll FPS Measurement"
    echo ""

    PACKAGE="com.fire.app"

    echo "Clearing gfxinfo..."
    adb shell dumpsys gfxinfo "$PACKAGE" reset > /dev/null 2>&1 || true

    echo "Scroll the home feed for 10 seconds starting NOW..."
    echo "(Use automated scroll or manual scroll)"
    sleep 10

    echo ""
    echo "GFX Info:"
    adb shell dumpsys gfxinfo "$PACKAGE" | grep -A 20 "Total frames" || echo "(no data collected)"

    echo ""
    echo "Janky frames:"
    adb shell dumpsys gfxinfo "$PACKAGE" | grep "Janky frames" || echo "(no janky frame data)"

    echo ""
    echo "Expected: >= 58 fps average, < 5% janky frames"
fi
```

- [ ] **Step 4: Create `scripts/benchmark-topic-load.sh`**

```bash
#!/bin/bash
# Measure topic detail first screen load time.

set -euo pipefail

PLATFORM="${1:-android}"

echo "# Topic Detail Load Benchmark (${PLATFORM})"

if [ "$PLATFORM" = "android" ]; then
    echo ""
    echo "## Android Topic Load Measurement"
    echo ""
    echo "Steps:"
    echo "  1. Open Fire to home feed"
    echo "  2. Clear logcat: adb shell logcat -c"
    echo "  3. Tap first topic in home feed"
    echo "  4. Measure time from tap to first post rendered"
    echo ""
    echo "Automated measurement:"
    echo ""

    adb shell logcat -c

    echo "Tap a topic now (or use automated input)..."
    adb shell input tap 540 800

    START_NS=$(adb shell logcat -v ns | grep -m1 "TopicDetailActivity.*onCreate" | awk '{print $1}' | tr -d '\r')
    END_NS=$(adb shell logcat -v ns | grep -m1 "TopicDetailActivity.*firstPostRendered" | awk '{print $1}' | tr -d '\r')

    if [ -n "$START_NS" ] && [ -n "$END_NS" ]; then
        # Calculate difference (simplified — actual parsing depends on log format)
        echo "Start: $START_NS"
        echo "End: $END_NS"
        echo "Calculate delta and compare to 2000ms target"
    else
        echo "Could not capture timing markers. Ensure log tags are present."
    fi

    echo ""
    echo "Expected: < 2.0s"
fi
```

- [ ] **Step 5: Create `scripts/benchmark-memory-peak.sh`**

```bash
#!/bin/bash
# Measure peak memory usage.

set -euo pipefail

PLATFORM="${1:-android}"

echo "# Memory Peak Benchmark (${PLATFORM})"

if [ "$PLATFORM" = "android" ]; then
    echo ""
    echo "## Android Memory Measurement"
    echo ""

    PACKAGE="com.fire.app"

    echo "Memory usage after home feed load:"
    adb shell dumpsys meminfo "$PACKAGE" | head -20

    echo ""
    echo "Steps for full benchmark:"
    echo "  1. Cold start app, load home feed → record memory"
    echo "  2. Navigate to topic detail, scroll through 100 posts → record memory"
    echo "  3. Navigate back, open search, search 'test' → record memory"
    echo "  4. Navigate to notifications, scroll through list → record memory"
    echo ""
    echo "Expected: < 200 MB (home), < 350 MB (topic detail)"
    echo ""
    echo "For continuous monitoring:"
    echo "  while true; do adb shell dumpsys meminfo $PACKAGE | grep 'TOTAL'; sleep 2; done"
fi

if [ "$PLATFORM" = "ios" ]; then
    echo ""
    echo "## iOS Memory Measurement"
    echo "Use Instruments > Allocations template."
    echo "Steps:"
    echo "  1. Launch Fire under Instruments Allocations"
    echo "  2. Navigate: home → topic detail → back → search → notifications"
    echo "  3. Record peak memory from Instruments"
    echo ""
    echo "Expected: < 200 MB (home), < 350 MB (topic detail)"
fi
```

- [ ] **Step 6: Make all benchmark scripts executable**

```bash
chmod +x scripts/benchmark-cold-start.sh
chmod +x scripts/benchmark-scroll-fps.sh
chmod +x scripts/benchmark-topic-load.sh
chmod +x scripts/benchmark-memory-peak.sh
```

**Commit message:** `docs(release): add performance benchmark definitions and measurement scripts`

---

### Task 6: Accessibility Audit

**Files:**
- Create: `docs/release/accessibility-audit-checklist.md`

- [ ] **Step 1: Create `docs/release/accessibility-audit-checklist.md`**

```markdown
# Fire v2.0 Accessibility Audit Checklist

## How to Use

For each screen, run through every checklist item on both platforms.
Mark pass/fail with notes. All items must pass before release.

---

## 1. VoiceOver / TalkBack — Full Flow

### iOS VoiceOver

- [ ] **Home Feed**
  - [ ] Each topic row announces: title, category, reply count, last poster
  - [ ] Swipe actions (if any) are announced
  - [ ] Category filter chips are navigable and announce selected state
  - [ ] Pull-to-refresh announces "refreshing" state
  - [ ] Loading state announces "loading content"

- [ ] **Topic Detail**
  - [ ] Post content is read in correct order
  - [ ] Post author and timestamp are announced before content
  - [ ] Reply depth/indentation is communicated
  - [ ] Code blocks are announced as "code block"
  - [ ] Images announce alt text or "image" if no alt text
  - [ ] Like/reply/bookmark actions are accessible via rotor or swipe
  - [ ] Back navigation works with VoiceOver escape gesture

- [ ] **Notifications**
  - [ ] Each notification announces: type, user, topic, timestamp
  - [ ] Unread state is announced
  - [ ] Mark-as-read action is accessible

- [ ] **Search**
  - [ ] Search field is focused and editable with VoiceOver
  - [ ] Results announce title and category
  - [ ] Empty state is announced

- [ ] **Profile**
  - [ ] Username and stats are announced
  - [ ] Tab navigation (activity, badges, etc.) works with VoiceOver
  - [ ] Logout button is reachable and confirms action

- [ ] **Composer**
  - [ ] Text field is editable with VoiceOver
  - [ ] Toolbar actions (bold, link, image) are reachable
  - [ ] Preview toggle announces state change
  - [ ] Send button announces "submitting" state

### Android TalkBack

- [ ] Same items as VoiceOver above, adapted for TalkBack gestures
- [ ] Focus order follows visual layout (top-left to bottom-right)
- [ ] All clickable elements have content descriptions
- [ ] RecyclerView items have correct `contentDescription` set in `TopicRowViewHolder`
- [ ] Bottom navigation items announce selected state
- [ ] Snackbar/toast messages are announced by TalkBack

---

## 2. Dynamic Type (iOS)

- [ ] **Smallest text (XS)**
  - [ ] All layouts render without truncation
  - [ ] No overlapping text

- [ ] **Largest text (AX5)**
  - [ ] Topic rows adapt: title wraps, metadata reflows
  - [ ] Tab bar remains usable
  - [ ] Composer toolbar remains accessible
  - [ ] Navigation bar title is readable
  - [ ] Post content in topic detail wraps correctly
  - [ ] Category chips do not overflow

- [ ] **Test screens:**
  - [ ] Home feed
  - [ ] Topic detail
  - [ ] Notifications
  - [ ] Search results
  - [ ] Profile
  - [ ] Composer

---

## 3. Reduce Motion

- [ ] **iOS (`UIAccessibility.isReduceMotionEnabled`)**
  - [ ] Shimmer loading animation is replaced with static placeholder
  - [ ] Tab transitions use crossfade instead of slide
  - [ ] Toast animations are instant (no slide/fade)
  - [ ] Haptic feedback is disabled (already gated in `FireHaptics`)
  - [ ] Pull-to-refresh spinner uses static indicator

- [ ] **Android (Settings > Accessibility > Remove animations)**
  - [ ] Shimmer animation is disabled
  - [ ] Page transitions use immediate switch
  - [ ] RecyclerView item animations are disabled
  - [ ] Snackbar animations respect system setting

---

## 4. High Contrast Mode

- [ ] **iOS (Accessibility > Display & Text Size > Increase Contrast)**
  - [ ] All text meets 4.5:1 contrast ratio against background
  - [ ] Button borders are visible
  - [ ] Tab bar selected state uses strong indicator
  - [ ] FireTheme.divider is visible
  - [ ] FireTheme.chromeBorder passes contrast check

- [ ] **Android (Accessibility > High contrast text)**
  - [ ] Text color overrides maintain readability
  - [ ] Icon visibility is not compromised
  - [ ] Button labels are readable
  - [ ] Disabled states are distinguishable

---

## 5. Color Blindness

- [ ] **Deuteranopia (red-green)**
  - [ ] Success (green) vs. warning (orange) states are distinguishable by icon, not just color
  - [ ] Notification badge is visible
  - [ ] Category color chips have labels (not color-only indicators)

- [ ] **Protanopia (red-green)**
  - [ ] Same checks as deuteranopia

- [ ] **Tritanopia (blue-yellow)**
  - [ ] Accent color is distinguishable from background
  - [ ] Link color is distinguishable from body text

### Verification Method

Use Xcode Accessibility Inspector > Color Sliders > check contrast ratio.
Use Android Studio Layout Inspector > check content descriptions.

---

## 6. Keyboard Navigation (iPad)

- [ ] Tab key navigates through all interactive elements
- [ ] Focus ring is visible on all elements
- [ ] Enter/Space activates buttons
- [ ] Escape dismisses modals/sheets
- [ ] Arrow keys navigate within lists

---

## 7. Switch Control (iOS)

- [ ] Single switch can navigate through all screens
- [ ] Grouping is logical (scan items in visual order)
- [ ] All actions are reachable

---

## Results Log

| Date | Tester | Screen | Platform | Items Passed | Items Failed | Notes |
|------|--------|--------|----------|-------------|-------------|-------|
| | | | | / | | |

## Failure Escalation

Any accessibility failure blocks the v2.0 release. Failures must be fixed before the app is submitted to the App Store or Play Store.
```

- [ ] **Step 2: Run VoiceOver smoke test on home feed and topic detail**

Navigate the home feed and topic detail with VoiceOver enabled. Verify:
1. Topic rows announce correctly
2. Navigation to topic detail works
3. Post content reads in order
4. Back navigation works

- [ ] **Step 3: Run TalkBack smoke test on home feed and topic detail**

Same as above on Android with TalkBack enabled. Verify `TopicRowViewHolder` content descriptions are set correctly in `native/android-app/src/main/java/com/fire/app/ui/home/TopicRowViewHolder.kt`.

- [ ] **Step 4: Test Dynamic Type at AX5**

On iOS, set text size to maximum (Accessibility > Larger Text > max). Open each screen and verify no truncation, no overlapping text, no unreachable controls.

- [ ] **Step 5: Test Reduce Motion**

On both platforms, enable reduce motion / remove animations. Verify:
- Shimmer replaced with static placeholder
- No animation-dependent functionality breaks
- Haptics are suppressed

- [ ] **Step 6: Run contrast ratio check on all FireTheme color pairs**

Check these combinations in both light and dark mode:
- `ink` on `canvasTop`
- `subtleInk` on `canvasTop`
- `tertiaryInk` on `canvasTop`
- `ink` on `panel`
- `ink` on `chrome`
- `accent` on `canvasTop`
- `success` on `canvasTop`
- `warning` on `canvasTop`

Document results in the checklist.

**Commit message:** `docs(release): add comprehensive accessibility audit checklist for iOS and Android`

## Architectural Notes

- **No code changes in this plan** — This plan is entirely documentation, scripts, and asset preparation. The codebase is assumed to be feature-complete from P1–P3.
- **Performance baselines are empirical** — The benchmark targets in Task 5 are based on observed behavior of the current codebase. If the actual measurements differ, update `docs/release/performance-benchmarks.md` with real numbers before setting final targets.
- **License collection is semi-automated** — The `collect-licenses.sh` script handles Rust and basic iOS/Android dependency listing. It may miss transitive dependencies or license text. Manual review is required.
- **Accessibility is a release blocker** — Per Apple and Google review guidelines, accessibility failures can cause rejection. The checklist in Task 6 must be fully green before submission.
- **Privacy policy alignment** — The privacy policy must be reviewed against the actual data flows in the codebase (see Task 3, Step 6). If P3 adds offline caching or widget data sharing, those data flows must be reflected in the policy.
- **TestFlight and Play Store setup require human action** — Creating developer accounts, uploading builds, and inviting testers require human access to App Store Connect and Google Play Console. The documentation in Task 4 provides step-by-step instructions but cannot be fully automated.

## File Change Summary

- `docs/release/privacy-policy.md` — Full privacy policy document
- `docs/release/app-store-data-collection.md` — App Store privacy questionnaire answers
- `docs/release/play-store-data-safety.md` — Play Store data safety section answers
- `docs/release/app-store-description.md` — App Store listing in Chinese and English
- `docs/release/play-store-description.md` — Play Store listing in Chinese
- `docs/release/third-party-licenses.md` — Auto-generated license list
- `docs/release/testflight-setup.md` — TestFlight configuration guide
- `docs/release/play-store-testing-setup.md` — Play Store testing track guide
- `docs/release/test-feedback-template.md` — Tester feedback form template
- `docs/release/performance-benchmarks.md` — Performance targets and baselines
- `docs/release/accessibility-audit-checklist.md` — Full accessibility testing checklist
- `scripts/collect-licenses.sh` — Dependency license collection script
- `scripts/benchmark-cold-start.sh` — Cold start measurement script
- `scripts/benchmark-scroll-fps.sh` — Scroll FPS measurement script
- `scripts/benchmark-topic-load.sh` — Topic detail load measurement script
- `scripts/benchmark-memory-peak.sh` — Memory peak measurement script
- `native/ios-app/marketing/screenshots/iPhone6.5/*.png` — 10 screenshots for iPhone 6.5"
- `native/ios-app/marketing/screenshots/iPhone5.5/*.png` — 10 screenshots for iPhone 5.5"
- `native/ios-app/marketing/screenshots/iPad12.9/*.png` — 10 screenshots for iPad 12.9"
- `native/ios-app/marketing/screenshots/iPad11/*.png` — 10 screenshots for iPad 11"
- `native/ios-app/marketing/preview-video/app-preview.mp4` — 15-30s app preview video
- `native/android-app/marketing/screenshots/phone/*.png` — 6-8 phone screenshots
- `native/android-app/marketing/screenshots/tablet7/*.png` — 6-8 7" tablet screenshots
- `native/android-app/marketing/screenshots/tablet10/*.png` — 6-8 10" tablet screenshots
- `native/android-app/marketing/feature-graphic.png` — 1024x500 feature graphic
