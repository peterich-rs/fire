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

require_no_pattern() {
  local label="$1"
  local file_glob="$2"
  local pattern="$3"

  if rg -q "$pattern" $file_glob; then
    fail "$label: forbidden pattern found: $pattern"
    rg -n "$pattern" $file_glob >&2 || true
  else
    pass "$label: forbidden pattern absent"
  fi
}

require_line_count_below() {
  local label="$1"
  local file="$2"
  local maximum="$3"
  local line_count

  if [[ ! -f "$file" ]]; then
    fail "$label: missing required file $file"
    return
  fi

  line_count="$(wc -l < "$file" | tr -d '[:space:]')"
  if [[ "$line_count" =~ ^[0-9]+$ ]] && (( line_count < maximum )); then
    pass "$label: $file has $line_count line(s), below $maximum"
  else
    fail "$label: $file has $line_count line(s), expected below $maximum"
  fi
}

echo "==> P1 implementation evidence"
require_pattern "P1 theme radius tokens" "apps/ios-app/App/Core/FireTheme.swift" "static let cornerRadius: CGFloat = 20"
require_pattern "P1 theme medium radius token" "apps/ios-app/App/Core/FireTheme.swift" "static let mediumCornerRadius: CGFloat = 14"
require_pattern "P1 theme small radius token" "apps/ios-app/App/Core/FireTheme.swift" "static let smallCornerRadius: CGFloat = 10"
require_pattern "P1 theme canvas token" "apps/ios-app/App/Core/FireTheme.swift" "static var canvas: Color"
require_pattern "P1 theme surface token" "apps/ios-app/App/Core/FireTheme.swift" "static var surface: Color"
require_no_pattern "P1 scoped hardcoded radius cleanup" "apps/ios-app/App/Core/FireComponents.swift apps/ios-app/App/Views/Composer/FireComposerView.swift apps/ios-app/App/Views/Other/FireOnboardingView.swift apps/ios-app/App/Views/Search/FireSearchView.swift apps/ios-app/App/Views/Home/FireTopicRow.swift apps/ios-app/App/Views/Home/FireFilteredTopicListView.swift" "cornerRadius:\\s*(10|12|16|18)\\b|\\.cornerRadius\\((10|12|16|18)\\b"
require_no_pattern "P1 scoped dark-mode hardcoding cleanup" "apps/ios-app/App/Views/Composer/FireComposerView.swift apps/ios-app/App/Views/Other/FireOnboardingView.swift apps/ios-app/App/Views/Search/FireSearchView.swift apps/ios-app/App/Core/FireComponents.swift" "Color\\.black\\.opacity|Color\\.black|Color\\.white|Color\\(\\.systemGroupedBackground\\)|Color\\(\\.secondarySystemBackground\\)"
require_pattern "P1 reusable empty state component" "apps/ios-app/App/Core/FireComponents.swift" "struct FireEmptyFeedState"
require_pattern "P1 filtered list empty state usage" "apps/ios-app/App/Views/Home/FireFilteredTopicListView.swift" "FireEmptyFeedState\\("
require_pattern "P1 notification empty state usage" "apps/ios-app/App/Views/Notifications/FireNotificationsViewController.swift" "title: \"暂无通知\""
require_pattern "P1 shimmer path" "apps/ios-app/App/Core/FireShimmerModifier.swift" "func fireShimmer\\(\\)"
require_pattern "P1 topic row accessibility label" "apps/ios-app/App/Views/Home/FireTopicRow.swift" "\\.accessibilityLabel\\("
require_pattern "P1 home create accessibility label" "apps/ios-app/App/Views/Home/FireHomeView.swift" "accessibilityLabel[[:space:]]*=[[:space:]]*\"创建新话题\"|\\.accessibilityLabel\\(\"创建新话题\"\\)"
require_pattern "P1 home search accessibility label" "apps/ios-app/App/Views/Home/FireHomeView.swift" "accessibilityLabel[[:space:]]*=[[:space:]]*\"搜索\"|\\.accessibilityLabel\\(\"搜索\"\\)"
require_pattern "P1 paginated store base" "apps/ios-app/App/Stores/FirePaginatedStore.swift" "class FirePaginatedStore<Item>: ObservableObject"
require_pattern "P1 search store pagination" "apps/ios-app/App/Stores/FireSearchStore.swift" "FirePaginatedStore<SearchResultState>"
require_pattern "P1 notification store pagination" "apps/ios-app/App/Stores/FireNotificationStore.swift" "FirePaginatedStore<NotificationItemState>"
require_file "P1 Android drafts fragment" "apps/android-app/src/main/java/com/fire/app/ui/drafts/DraftsFragment.kt"
require_pattern "P1 Android drafts session bridge" "apps/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt" "fetchDrafts\\("
require_file "P1 Android FCM service" "apps/android-app/src/main/java/com/fire/app/push/FireFirebaseMessagingService.kt"
require_pattern "P1 Android FCM token handling" "apps/android-app/src/main/java/com/fire/app/push/FireFirebaseMessagingService.kt" "override fun onNewToken"
require_pattern "P1 Android FCM message handling" "apps/android-app/src/main/java/com/fire/app/push/FireFirebaseMessagingService.kt" "override fun onMessageReceived"
require_pattern "P1 Android push local notification dispatcher" "apps/android-app/src/main/java/com/fire/app/push/FirePushNotificationDispatcher.kt" "NotificationManagerCompat\\.from\\(context\\)\\.notify"
require_line_count_below "P1 FireAppViewModel size" "apps/ios-app/App/ViewModels/FireAppViewModel.swift" 1500

echo
echo "==> P2 implementation evidence"
require_file "P2 Rust LDC core" "crates/fire-core/src/core/ldc.rs"
require_file "P2 Rust CDK core" "crates/fire-core/src/core/cdk.rs"
require_pattern "P2 UniFFI LDC authorization" "crates/fire-uniffi-ldc/src/lib.rs" "ldc_authorization_url"
require_pattern "P2 UniFFI CDK authorization" "crates/fire-uniffi-ldc/src/lib.rs" "cdk_authorization_url"
require_file "P2 iOS LDC view" "apps/ios-app/App/Views/Profile/FireLDCView.swift"
require_file "P2 iOS CDK view" "apps/ios-app/App/Views/Profile/FireCDKView.swift"
require_file "P2 Android LDC fragment" "apps/android-app/src/main/java/com/fire/app/ui/ldc/LDCFragment.kt"
require_file "P2 Android CDK fragment" "apps/android-app/src/main/java/com/fire/app/ui/ldc/CDKFragment.kt"
require_pattern "P2 Rust topic thread model" "crates/fire-models/src/topic_detail.rs" "pub struct TopicThread"
require_pattern "P2 Android topic tree projection" "apps/android-app/src/main/java/com/fire/app/ui/topicdetail/TopicDetailViewModel.kt" "TopicDetailPostRows\\.projectRows"
require_pattern "P2 iOS topic search controller" "apps/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift" "FireTopicSearchBar"
require_pattern "P2 Android topic search overlay" "apps/android-app/src/main/res/layout/activity_topic_detail.xml" "TopicSearchOverlay"
require_pattern "P2 iOS Markdown toolbar" "apps/ios-app/App/Views/Composer/FireComposerView.swift" "struct FireMarkdownToolbar"
require_pattern "P2 Android Markdown toolbar" "apps/android-app/src/main/java/com/fire/app/ui/composer/MarkdownToolbarView.kt" "class MarkdownToolbarView"
require_pattern "P2 iOS quote insertion" "apps/ios-app/App/Views/Composer/FireComposerView.swift" "enum FireQuoteMarkdown"
require_pattern "P2 Android quote insertion test" "apps/android-app/src/test/java/com/fire/app/ui/composer/MarkdownInsertionTest.kt" "quoteMarkdown_buildsDiscourseQuoteBlockFromPlainText"
require_pattern "P2 iOS topic notification level" "apps/ios-app/Sources/FireAppSession/FireSessionStore.swift" "setTopicNotificationLevel"
require_pattern "P2 Android topic notification level" "apps/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt" "setTopicNotificationLevel"

echo
echo "==> P3 implementation evidence"
require_pattern "P3 iOS widget bundle" "apps/ios-app/App/Widgets/FireWidgetBundle.swift" "FireMediumWidget\\(\\)"
require_pattern "P3 iOS large widget" "apps/ios-app/App/Widgets/FireWidgetBundle.swift" "FireLargeWidget\\(\\)"
require_pattern "P3 Android unread widget" "apps/android-app/src/main/java/com/fire/app/widget/FireUnreadWidgetProvider.kt" "AppWidgetProvider"
require_pattern "P3 Android topic-list widget" "apps/android-app/src/main/java/com/fire/app/widget/FireTopicListWidgetProvider.kt" "AppWidgetProvider"
require_pattern "P3 Android widgets registered" "apps/android-app/src/main/AndroidManifest.xml" "FireTopicListWidgetProvider"
require_pattern "P3 iOS haptics layer" "apps/ios-app/App/FireMotion/FireMotionEffects.swift" "enum FireMotionHaptics"
require_pattern "P3 iOS post-row haptics" "apps/ios-app/App/ListKit/TopicDetail/FirePostCellNode.swift" "FireMotionHaptics"
require_pattern "P3 iOS toast component" "apps/ios-app/App/Core/FireComponents.swift" "struct FireToast"
require_pattern "P3 Android toast component" "apps/android-app/src/main/java/com/fire/app/core/ui/FireToast.kt" "object FireToast"
require_pattern "P3 Rust topic cache write" "crates/fire-store/src/lib.rs" "topic_list_cache_write"
require_pattern "P3 Rust notification cache write" "crates/fire-store/src/lib.rs" "notification_list_cache_write"
require_pattern "P3 Rust topic cache read-through" "crates/fire-core/src/core/topics.rs" "topic_list_cache_read"
require_pattern "P3 Rust notification cache read-through" "crates/fire-core/src/core/notifications.rs" "notification_list_cache_read"
require_pattern "P3 iOS home offline state" "apps/ios-app/App/Stores/FireHomeFeedStore.swift" "isOffline = response\\.isCached"
require_pattern "P3 iOS notification offline state" "apps/ios-app/App/Stores/FireNotificationStore.swift" "isOffline = result\\.isCached"
require_pattern "P3 Android home offline state" "apps/android-app/src/main/java/com/fire/app/ui/home/HomeViewModel.kt" "_isOffline\\.value = isCached"
require_pattern "P3 Android offline banner" "apps/android-app/src/main/res/layout/view_offline_banner.xml" "offline_cache_banner"

if [[ "$failure_count" -gt 0 ]]; then
  printf 'Roadmap implementation evidence verification failed: %d failure(s), %d check(s) passed\n' "$failure_count" "$checked_count" >&2
  exit 1
fi

printf 'Roadmap implementation evidence verification passed: %d check(s).\n' "$checked_count"
