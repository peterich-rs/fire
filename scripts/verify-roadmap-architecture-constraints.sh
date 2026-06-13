#!/usr/bin/env bash
set -euo pipefail

failure_count=0
checked_count=0

fail() {
  failure_count=$((failure_count + 1))
  printf 'FAIL: %s\n' "$*" >&2
}

pass() {
  checked_count=$((checked_count + 1))
  printf 'PASS: %s\n' "$*"
}

require_file() {
  local label="$1"
  local file="$2"

  if [[ -f "$file" ]]; then
    pass "$label: found $file"
  else
    fail "$label: missing required file $file"
  fi
}

require_dir() {
  local label="$1"
  local dir="$2"

  if [[ -d "$dir" ]]; then
    pass "$label: found $dir"
  else
    fail "$label: missing required directory $dir"
  fi
}

require_pattern() {
  local label="$1"
  local file="$2"
  local pattern="$3"

  if [[ ! -f "$file" ]]; then
    fail "$label: missing required file $file"
    return
  fi

  if rg -q "$pattern" "$file"; then
    pass "$label: pattern found in $file"
  else
    fail "$label: pattern not found in $file: $pattern"
  fi
}

require_pattern_count() {
  local label="$1"
  local file="$2"
  local pattern="$3"
  local expected_count="$4"
  local actual_count

  if [[ ! -f "$file" ]]; then
    fail "$label: missing required file $file"
    return
  fi

  actual_count="$(rg -c "$pattern" "$file" || true)"
  if [[ "$actual_count" == "$expected_count" ]]; then
    pass "$label: found $actual_count occurrence(s) in $file"
  else
    fail "$label: expected $expected_count occurrence(s), found $actual_count in $file: $pattern"
  fi
}

require_no_pattern() {
  local label="$1"
  local file="$2"
  local pattern="$3"

  if [[ ! -f "$file" ]]; then
    fail "$label: missing required file $file"
    return
  fi

  if rg -q "$pattern" "$file"; then
    fail "$label: forbidden pattern found in $file: $pattern"
    rg -n "$pattern" "$file" >&2 || true
  else
    pass "$label: forbidden pattern absent from $file"
  fi
}

require_no_source_reference_imports() {
  local label="$1"
  local pattern="$2"

  if rg -q \
    -g '*.swift' \
    -g '*.kt' \
    -g '*.java' \
    -g '*.rs' \
    -g '!native/ios-app/LocalPackages/**' \
    -g '!rust/target/**' \
    -g '!third_party/**' \
    "$pattern" native rust
  then
    fail "$label: forbidden reference dependency found: $pattern"
    rg -n \
      -g '*.swift' \
      -g '*.kt' \
      -g '*.java' \
      -g '*.rs' \
      -g '!native/ios-app/LocalPackages/**' \
      -g '!rust/target/**' \
      -g '!third_party/**' \
      "$pattern" native rust >&2 || true
  else
    pass "$label: no production source imports or depends on reference code"
  fi
}

require_no_ios_app_source_pattern() {
  local label="$1"
  local pattern="$2"

  if rg -q -g '*.swift' "$pattern" native/ios-app/App; then
    fail "$label: forbidden pattern found: $pattern"
    rg -n -g '*.swift' "$pattern" native/ios-app/App >&2 || true
  else
    pass "$label: forbidden pattern absent from iOS app source"
  fi
}

echo "==> Platform minimums"
require_pattern_count "iOS app/widget/test deployment targets" "native/ios-app/project.yml" 'deploymentTarget: "16\.0"' 3
require_pattern "iOS architecture document minimum" "docs/architecture/fire-native-architecture.md" '\| Minimum version \| iOS 16 \|'
require_pattern "Android min SDK" "native/android-app/build.gradle.kts" 'minSdk = 26'
require_pattern "Android target SDK" "native/android-app/build.gradle.kts" 'targetSdk = 35'
require_pattern "Android compile SDK" "native/android-app/build.gradle.kts" 'compileSdk = 35'
require_pattern "Android architecture document minimum" "docs/architecture/fire-native-architecture.md" '\| Minimum version \| API 26 \(Android 8\.0\) \|'
require_pattern "Android architecture document target" "docs/architecture/fire-native-architecture.md" '\| Target version \| API 35 \|'

echo
echo "==> iOS 16 source compatibility guardrails"
require_no_ios_app_source_pattern "iOS app source avoids iOS 17 SwiftUI sensoryFeedback" 'sensoryFeedback'
require_no_ios_app_source_pattern "iOS app source avoids iOS 17 two-parameter onChange closures" '\.onChange\(of:[^\n]+\) \{ _,'
require_no_ios_app_source_pattern "iOS app source avoids iOS 17 navigationDestination item overload" '\.navigationDestination\(item:'
require_no_ios_app_source_pattern "iOS app source avoids iOS 17 ContentUnavailableView" 'ContentUnavailableView'
require_no_ios_app_source_pattern "iOS app source avoids iOS 17 transaction value overload" '\.transaction\(value:'

echo
echo "==> Platform-owned browser, cookie, and store boundaries"
require_pattern "iOS WebView login coordinator owns WKWebView" "native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift" 'WKWebView'
require_pattern "iOS platform cookie extraction" "native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift" 'WKHTTPCookieStore|HTTPCookieStorage'
require_pattern "iOS Cloudflare challenge coordinator" "native/ios-app/Sources/FireAppSession/FireCloudflareChallengeCoordinator.swift" 'WKWebView'
require_pattern "iOS keychain cookie storage" "native/ios-app/Sources/FireAppSession/FireAuthCookieKeychainStore.swift" 'kSecClassGenericPassword|SecItem'
require_pattern "Android WebView login coordinator owns WebView" "native/android-app/src/main/java/com/fire/app/session/FireWebViewLoginCoordinator.kt" 'android\.webkit\.WebView'
require_pattern "Android platform cookie extraction" "native/android-app/src/main/java/com/fire/app/session/FireWebViewLoginCoordinator.kt" 'CookieManager\.getInstance\(\)'
require_pattern "Android Cloudflare activity registered" "native/android-app/src/main/AndroidManifest.xml" 'FireCloudflareChallengeActivity'
require_pattern "Android backup disabled" "native/android-app/src/main/AndroidManifest.xml" 'android:allowBackup="false"'
require_pattern "Android backup rules explicit" "native/android-app/src/main/AndroidManifest.xml" 'android:dataExtractionRules="@xml/data_extraction_rules"'
require_pattern "Android backup content explicit" "native/android-app/src/main/AndroidManifest.xml" 'android:fullBackupContent="@xml/backup_rules"'
require_pattern "Android keystore credential store" "native/android-app/src/main/java/com/fire/app/session/FireCredentialStore.kt" 'AndroidKeyStore'

echo
echo "==> Rust-owned core and UniFFI orchestration"
require_pattern "Rust core owns openwire dependency" "Cargo.toml" 'openwire = \{ version = "0\.1\.1"'
require_pattern "Rust core owns xlog dependency" "Cargo.toml" 'mars-xlog = \{ version = "0\.1\.0-preview\.2"'
require_pattern "fire-core depends on openwire through workspace" "rust/crates/fire-core/Cargo.toml" 'openwire\.workspace = true'
require_pattern "fire-core depends on xlog through workspace" "rust/crates/fire-core/Cargo.toml" 'mars-xlog\.workspace = true'
require_pattern "Rust session core exists" "rust/crates/fire-core/src/core/session.rs" 'impl FireCore'
require_pattern "Rust topics core owns topic APIs" "rust/crates/fire-core/src/core/topics.rs" 'fetch_topic_detail_page|fetch_topic_list'
require_pattern "Rust notifications core owns notification APIs" "rust/crates/fire-core/src/core/notifications.rs" 'fetch_notifications'
require_pattern "Rust MessageBus core exists" "rust/crates/fire-core/src/core/messagebus.rs" 'MessageBus'
require_pattern "UniFFI top-level state observer boundary" "rust/crates/fire-uniffi/src/lib.rs" 'trait StateObserver'
require_pattern "UniFFI state observer registration" "rust/crates/fire-uniffi/src/lib.rs" 'register_state_observer'
require_pattern "iOS session store bridges to FireAppCore" "native/ios-app/Sources/FireAppSession/FireSessionStore.swift" 'FireAppCore'
require_pattern "Android session store bridges to FireAppCore" "native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt" 'FireAppCore'

echo
echo "==> iOS topic-detail native runtime path"
require_pattern "Topic detail host is only SwiftUI bridge" "native/ios-app/App/TopicDetail/Host/FireTopicDetailControllerHost.swift" 'This is the only SwiftUI surface that remains in the topic-detail path'
require_pattern "Topic detail controller is UIKit" "native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift" 'final class FireTopicDetailViewController: UIViewController'
require_pattern "Topic detail controller uses native search bar" "native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift" 'FireTopicSearchBar'
require_pattern "Topic detail feed uses ASCollectionNode" "native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedController.swift" 'ASCollectionNode'
require_pattern "Topic detail feed produces post cell nodes" "native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedController.swift" 'FirePostCellNode'
require_pattern "Topic detail post row is Texture cell" "native/ios-app/App/ListKit/TopicDetail/FirePostCellNode.swift" 'final class FirePostCellNode: ASCellNode'
require_pattern "Topic detail post row uses UIKit" "native/ios-app/App/ListKit/TopicDetail/FirePostCellNode.swift" 'import UIKit'
require_no_pattern "Topic detail controller avoids SwiftUI row fallback" "native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift" '^import SwiftUI|UIHostingController|UIViewControllerRepresentable'
require_no_pattern "Topic detail feed avoids SwiftUI row fallback" "native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedController.swift" '^import SwiftUI|UIHostingController|UIViewControllerRepresentable'
require_no_pattern "Topic detail post cell avoids SwiftUI row fallback" "native/ios-app/App/ListKit/TopicDetail/FirePostCellNode.swift" '^import SwiftUI|UIHostingController|UIViewControllerRepresentable'

echo
echo "==> Reference and infrastructure boundaries"
require_dir "FluxDO reference submodule checkout" "references/fluxdo"
require_pattern "FluxDO submodule registered" ".gitmodules" '\[submodule "references/fluxdo"\]'
require_pattern "FluxDO submodule is non-recursive" ".gitmodules" 'fetchRecurseSubmodules = false'
require_no_source_reference_imports "Reference project is not used by production source" 'references/fluxdo|fluxdo'
require_dir "Openwire infrastructure checkout" "third_party/openwire"
require_file "Openwire infrastructure license" "third_party/openwire/LICENSE"
require_pattern "xlog-rs submodule registered" ".gitmodules" '\[submodule "third_party/xlog-rs"\]'
require_pattern "xlog-rs submodule path registered" ".gitmodules" 'path = third_party/xlog-rs'
require_dir "xlog-rs infrastructure gitlink path" "third_party/xlog-rs"

if [[ "$failure_count" -gt 0 ]]; then
  printf 'Roadmap architecture constraints verification failed: %d failure(s), %d check(s) passed\n' "$failure_count" "$checked_count" >&2
  exit 1
fi

printf 'Roadmap architecture constraints verification passed: %d check(s).\n' "$checked_count"
