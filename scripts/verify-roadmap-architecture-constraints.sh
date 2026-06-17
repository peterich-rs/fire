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

require_no_ios_primary_app_source_pattern() {
  local label="$1"
  local pattern="$2"

  if rg -q \
    -g '*.swift' \
    -g '!native/ios-app/App/Widgets/**' \
    -g '!native/ios-app/App/DeveloperTools/**' \
    "$pattern" native/ios-app/App
  then
    fail "$label: forbidden pattern found: $pattern"
    rg -n \
      -g '*.swift' \
      -g '!native/ios-app/App/Widgets/**' \
      -g '!native/ios-app/App/DeveloperTools/**' \
      "$pattern" native/ios-app/App >&2 || true
  else
    pass "$label: forbidden pattern absent from primary iOS app source"
  fi
}

require_no_ios_primary_app_source_pattern_except_motion_helper() {
  local label="$1"
  local pattern="$2"

  if rg -q \
    -g '*.swift' \
    -g '!native/ios-app/App/Widgets/**' \
    -g '!native/ios-app/App/DeveloperTools/**' \
    -g '!native/ios-app/App/FireMotion/FireMotionEffects.swift' \
    "$pattern" native/ios-app/App
  then
    fail "$label: forbidden pattern found: $pattern"
    rg -n \
      -g '*.swift' \
      -g '!native/ios-app/App/Widgets/**' \
      -g '!native/ios-app/App/DeveloperTools/**' \
      -g '!native/ios-app/App/FireMotion/FireMotionEffects.swift' \
      "$pattern" native/ios-app/App >&2 || true
  else
    pass "$label: forbidden pattern absent from primary iOS app source outside motion helper"
  fi
}

require_ios_lazy_cell_registrations_prepared() {
  local label="$1"
  local failed=0
  local file
  local registration
  local registrations

  while IFS= read -r file; do
    registrations=()
    while IFS= read -r registration; do
      registrations+=("$registration")
    done < <(
      rg -o 'lazy var [[:alnum:]_]+CellRegistration' "$file" |
        awk '{ print $3 }' |
        sort -u || true
    )
    if [[ "${#registrations[@]}" -eq 0 ]]; then
      continue
    fi

    if ! rg -q 'func prepareCellRegistrations\(' "$file"; then
      fail "$label: $file declares lazy UICollectionView cell registrations without prepareCellRegistrations()"
      failed=1
      continue
    fi

    for registration in "${registrations[@]}"; do
      if ! rg -q "_ = ${registration}" "$file"; then
        fail "$label: $file does not prepare $registration before diffable cell provider dequeue"
        failed=1
      fi
    done
  done < <(
    rg -l 'lazy var [[:alnum:]_]+CellRegistration' \
      -g '*.swift' \
      native/ios-app/App || true
  )

  if [[ "$failed" -eq 0 ]]; then
    pass "$label: lazy UICollectionView cell registrations are prepared before provider dequeue"
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
require_no_ios_primary_app_source_pattern "iOS primary app source avoids iOS 17 SwiftUI sensoryFeedback" 'sensoryFeedback'
require_no_ios_primary_app_source_pattern "iOS primary app source avoids iOS 17 two-parameter onChange closures" '\.onChange\(of:[^\n]+\) \{[[:space:]]*[^,{}]+,[^{}]+ in'
require_no_ios_primary_app_source_pattern "iOS primary app source avoids iOS 17 navigationDestination item overload" '\.navigationDestination\(item:'
require_no_ios_primary_app_source_pattern "iOS primary app source avoids iOS 17 ContentUnavailableView" 'ContentUnavailableView'
require_no_ios_primary_app_source_pattern "iOS primary app source avoids iOS 17 transaction value overload" '\.transaction\(value:'
require_no_ios_primary_app_source_pattern "iOS primary app source avoids direct WidgetKit containerBackground outside widgets" 'containerBackground\(for:[[:space:]]*\.widget'
require_no_ios_primary_app_source_pattern_except_motion_helper "iOS primary app source avoids direct SwiftUI symbolEffect outside guarded motion helper" 'symbolEffect'
require_no_ios_primary_app_source_pattern_except_motion_helper "iOS primary app source avoids direct SwiftUI contentTransition outside guarded motion helper" 'contentTransition'
require_pattern "iOS motion helper gates symbolEffect/contentTransition" "native/ios-app/App/FireMotion/FireMotionEffects.swift" '#available\(iOS 17, \*\)'
require_pattern "WidgetKit container background is availability-gated" "native/ios-app/App/Widgets/FireWidgetViews.swift" '#available\(iOSApplicationExtension 17\.0, \*\)'

echo
echo "==> iOS UIKit root shell"
require_pattern "iOS app delegate is UIKit main entry" "native/ios-app/App/Core/FireAppDelegate.swift" '@main'
require_pattern "iOS app delegate connects scene delegate" "native/ios-app/App/Core/FireAppDelegate.swift" 'FireSceneDelegate'
require_pattern "iOS scene delegate owns UIWindow" "native/ios-app/App/Core/FireSceneDelegate.swift" 'UIWindow'
require_pattern "iOS root coordinator owns route dispatch" "native/ios-app/App/Core/FireRootCoordinator.swift" 'static func dispatch\(_ route: FireAppRoute\)'
require_pattern "iOS root coordinator drives launch/main two-state root" "native/ios-app/App/Core/FireRootCoordinator.swift" 'case launch'
require_pattern "iOS onboarding owns login orchestration" "native/ios-app/App/Views/Other/FireOnboardingView.swift" 'func performLogin\(\) async'
require_pattern "iOS root coordinator owns topic presentation" "native/ios-app/App/Core/FireRootCoordinator.swift" 'syncTopicPresentation'
require_pattern "iOS root coordinator uses UIKit onboarding controller" "native/ios-app/App/Core/FireRootCoordinator.swift" 'FireOnboardingViewController'
require_no_pattern "iOS root coordinator avoids SwiftUI hosting" "native/ios-app/App/Core/FireRootCoordinator.swift" 'import SwiftUI|UIHostingController'
require_pattern "iOS main tab shell is UIKit" "native/ios-app/App/Core/FireMainTabBarController.swift" 'UITabBarController'
require_pattern "iOS main tab shell wraps tabs in navigation controllers" "native/ios-app/App/Core/FireMainTabBarController.swift" 'UINavigationController'
require_no_pattern "iOS SwiftUI App entry removed" "native/ios-app/App/FireApp.swift" '@main|WindowGroup|@UIApplicationDelegateAdaptor|struct FireApp: App'
require_no_pattern "iOS SwiftUI root TabView removed" "native/ios-app/App/Views/Other/FireTabRoot.swift" 'struct FireTabRoot: View|TabView|fullScreenCover|@Environment\(\\.scenePhase\)'
require_pattern "iOS onboarding root is UIKit" "native/ios-app/App/Views/Other/FireOnboardingView.swift" 'final class FireOnboardingViewController: UIViewController'
require_no_pattern "iOS onboarding SwiftUI root removed" "native/ios-app/App/Views/Other/FireOnboardingView.swift" 'struct FireOnboardingView:[[:space:]]*View|NavigationStack|@Environment'

echo
echo "==> Platform-owned browser, cookie, and store boundaries"
require_pattern "iOS WebView login coordinator owns WKWebView" "native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift" 'WKWebView'
require_pattern "iOS onboarding presents captcha login dialog" "native/ios-app/App/Views/Other/FireOnboardingView.swift" 'FireCaptchaLoginDialogController'
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
echo "==> iOS UIKit-first ListKit runtime"
require_pattern "ListKit exposes UIKit-first list controller" "native/ios-app/App/ListKit/FireDiffableListController.swift" 'class FireListViewController<SectionID: Hashable, ItemID: Hashable>: UIViewController'
require_pattern "ListKit controller accepts UIKit cell providers" "native/ios-app/App/ListKit/FireDiffableListController.swift" 'typealias FireListCellProvider'
require_pattern "ListKit SwiftUI adapter subclasses UIKit runtime" "native/ios-app/App/ListKit/FireDiffableListController.swift" 'FireDiffableListController<SectionID: Hashable, ItemID: Hashable, RowContent: View>:[[:space:]]*$'
require_pattern "ListKit SwiftUI adapter is the hosted-cell owner" "native/ios-app/App/ListKit/FireDiffableListController.swift" 'UIHostingConfiguration'
require_ios_lazy_cell_registrations_prepared "UIKit list cell registration lifecycle"
require_pattern "Collection host remains a bridge adapter" "native/ios-app/App/ListKit/FireCollectionHost.swift" 'UIViewControllerRepresentable'
require_pattern "Home tab routes through UIKit controller" "native/ios-app/App/Core/FireMainTabBarController.swift" 'rootViewController: FireHomeViewController'
require_pattern "Home page has UIKit controller" "native/ios-app/App/Views/Home/FireHomeView.swift" 'final class FireHomeViewController: UIViewController'
require_pattern "Home controller uses UIKit-first list runtime" "native/ios-app/App/Views/Home/FireHomeView.swift" 'FireListViewController<FireHomeCollectionSection, FireHomeCollectionItem>'
require_no_pattern "Home deleted SwiftUI page" "native/ios-app/App/Views/Home/FireHomeView.swift" 'struct FireHomeView:[[:space:]]*View|NavigationStack[[:space:]]*\{[[:space:]]*FireHome'
if [[ -e "native/ios-app/App/ListKit/Home/FireHomeCollectionView.swift" ]]; then
  fail "Home deleted SwiftUI collection bridge: native/ios-app/App/ListKit/Home/FireHomeCollectionView.swift still exists"
else
  pass "Home deleted SwiftUI collection bridge: old bridge file absent"
fi
require_pattern "Bookmarks page has UIKit controller" "native/ios-app/App/Views/Bookmarks/FireBookmarksViewController.swift" 'final class FireBookmarksViewController: UIViewController'
require_pattern "Bookmarks controller uses UIKit-first list runtime" "native/ios-app/App/Views/Bookmarks/FireBookmarksViewController.swift" 'FireListViewController<FireBookmarksCollectionSection, FireBookmarksCollectionItem>'
require_pattern "Profile routes bookmarks through UIKit host" "native/ios-app/App/Views/Profile/FireProfileView.swift" 'FireBookmarksControllerHost'
require_no_pattern "Bookmarks deleted SwiftUI page" "native/ios-app/App/Views/Bookmarks/FireBookmarksView.swift" 'struct FireBookmarksView:[[:space:]]*View'
require_pattern "Read history page has UIKit controller" "native/ios-app/App/Views/Other/FireReadHistoryViewController.swift" 'final class FireReadHistoryViewController: UIViewController'
require_pattern "Read history controller uses UIKit-first list runtime" "native/ios-app/App/Views/Other/FireReadHistoryViewController.swift" 'FireListViewController<FireReadHistoryCollectionSection, FireReadHistoryCollectionItem>'
require_pattern "Profile routes read history through UIKit host" "native/ios-app/App/Views/Profile/FireProfileView.swift" 'FireReadHistoryControllerHost'
require_no_pattern "Read history deleted SwiftUI page" "native/ios-app/App/Views/Other/FireReadHistoryView.swift" 'struct FireReadHistoryView:[[:space:]]*View'
require_pattern "Notifications tab routes through UIKit controller" "native/ios-app/App/Core/FireMainTabBarController.swift" 'rootViewController: FireNotificationsViewController'
require_pattern "Notifications page has UIKit controller" "native/ios-app/App/Views/Notifications/FireNotificationsViewController.swift" 'final class FireNotificationsViewController: UIViewController'
require_pattern "Notifications controller uses UIKit-first list runtime" "native/ios-app/App/Views/Notifications/FireNotificationsViewController.swift" 'FireListViewController<FireNotificationsCollectionSection, FireNotificationsCollectionItem>'
require_pattern "Notification history page has UIKit controller" "native/ios-app/App/Views/Notifications/FireNotificationsViewController.swift" 'final class FireNotificationHistoryViewController: UIViewController'
require_pattern "Notification history controller uses UIKit-first list runtime" "native/ios-app/App/Views/Notifications/FireNotificationsViewController.swift" 'FireListViewController<[[:space:]]*FireNotificationHistoryCollectionSection'
require_no_pattern "Notifications deleted SwiftUI page" "native/ios-app/App/Views/Notifications/FireNotificationPresentation.swift" 'struct FireNotificationsView:[[:space:]]*View|struct FireNotificationHistoryView:[[:space:]]*View|FireNotificationRow'
require_pattern "Drafts page has UIKit controller" "native/ios-app/App/Views/Other/FireDraftsView.swift" 'final class FireDraftsViewController: UIViewController'
require_pattern "Drafts controller uses UIKit-first list runtime" "native/ios-app/App/Views/Other/FireDraftsView.swift" 'FireListViewController<FireDraftsCollectionSection, FireDraftsCollectionItem>'
require_pattern "Profile routes drafts through UIKit host" "native/ios-app/App/Views/Profile/FireProfileView.swift" 'FireDraftsControllerHost'
require_no_pattern "Drafts deleted SwiftUI page" "native/ios-app/App/Views/Other/FireDraftsView.swift" 'struct FireDraftsView:[[:space:]]*View'
require_pattern "Messages page has UIKit controller" "native/ios-app/App/Views/Messages/FirePrivateMessagesView.swift" 'final class FirePrivateMessagesViewController: UIViewController'
require_pattern "Messages controller uses UIKit-first list runtime" "native/ios-app/App/Views/Messages/FirePrivateMessagesView.swift" 'FireListViewController<'
require_pattern "Profile routes messages through UIKit host" "native/ios-app/App/Views/Profile/FireProfileView.swift" 'FirePrivateMessagesControllerHost'
require_no_pattern "Messages deleted SwiftUI page" "native/ios-app/App/Views/Messages/FirePrivateMessagesView.swift" 'struct FirePrivateMessagesView:[[:space:]]*View|List[[:space:]]*\{'
require_pattern "Search page has UIKit controller" "native/ios-app/App/Views/Search/FireSearchView.swift" 'final class FireSearchViewController: UIViewController'
require_pattern "Search controller uses UIKit-first list runtime" "native/ios-app/App/Views/Search/FireSearchView.swift" 'FireListViewController<FireSearchCollectionSection, FireSearchCollectionItem>'
require_pattern "Home routes search through UIKit controller" "native/ios-app/App/Views/Home/FireHomeView.swift" 'FireSearchViewController'
require_no_pattern "Search deleted SwiftUI page" "native/ios-app/App/Views/Search/FireSearchView.swift" 'struct FireSearchView:[[:space:]]*View|FireSearchPostRow:[[:space:]]*View|FireSearchUserRow:[[:space:]]*View|List[[:space:]]*\{'
require_pattern "Composer page has UIKit controller" "native/ios-app/App/Views/Composer/FireComposerView.swift" 'final class FireComposerViewController: UIViewController'
require_pattern "Composer UIKit controller owns native text input" "native/ios-app/App/Views/Composer/FireComposerView.swift" 'private let bodyTextView = UITextView\(\)'
require_pattern "Composer UIKit controller owns platform photo picker" "native/ios-app/App/Views/Composer/FireComposerView.swift" 'PHPickerViewController'
require_no_pattern "Composer deleted legacy SwiftUI page" "native/ios-app/App/Views/Composer/FireComposerView.swift" 'struct FireComposerView:[[:space:]]*View'
require_pattern "Home routes composer through UIKit controller" "native/ios-app/App/Views/Home/FireHomeView.swift" 'FireComposerViewController'
require_pattern "Messages routes composer through UIKit controller" "native/ios-app/App/Views/Messages/FirePrivateMessagesView.swift" 'FireComposerViewController'
require_pattern "Drafts routes composer through UIKit controller" "native/ios-app/App/Views/Other/FireDraftsView.swift" 'FireComposerViewController'
require_pattern "Topic detail routes composer through UIKit controller" "native/ios-app/App/TopicDetail/Controller/FireTopicDetailModalRouter.swift" 'FireComposerViewController'
require_pattern "Profile routes composer through UIKit runtime host" "native/ios-app/App/Views/Profile/FirePublicProfileView.swift" 'FireComposerControllerHost'
require_no_pattern "Home composer caller avoids SwiftUI composer page" "native/ios-app/App/Views/Home/FireHomeView.swift" 'FireComposerView\('
require_no_pattern "Messages composer caller avoids SwiftUI composer page" "native/ios-app/App/Views/Messages/FirePrivateMessagesView.swift" 'FireComposerView\('
require_no_pattern "Drafts composer caller avoids SwiftUI composer page" "native/ios-app/App/Views/Other/FireDraftsView.swift" 'FireComposerView\('
require_no_pattern "Profile composer caller avoids SwiftUI composer page" "native/ios-app/App/Views/Profile/FirePublicProfileView.swift" 'FireComposerView\('
require_no_pattern "Topic detail composer caller avoids SwiftUI composer page" "native/ios-app/App/TopicDetail/Controller/FireTopicDetailModalRouter.swift" 'FireComposerView\('

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
