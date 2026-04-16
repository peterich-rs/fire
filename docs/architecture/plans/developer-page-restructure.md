# Developer Page Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flatten the developer tools two-level hierarchy into a single-level page with 6 NavigationLink items, while decomposing the 2033-line `FireDiagnosticsView.swift` monolith into focused files.

**Architecture:** Extract the `FireDiagnosticsViewModel` and all sub-views from `FireDiagnosticsView.swift` into separate files under a new `App/DeveloperTools/` directory. The new `FireDeveloperToolsView` owns the ViewModel as `@StateObject` and passes it to child views. No Rust or UniFFI changes.

**Tech Stack:** SwiftUI, UIKit (UIViewRepresentable), existing Rust UniFFI bindings via `FireAppViewModel`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `native/ios-app/App/DeveloperTools/FireDiagnosticsViewModel.swift` | Create | ViewModel + data models (TextWindow, PagedTextDocument, ShareRequest) extracted from lines 5-605 |
| `native/ios-app/App/DeveloperTools/FireDiagnosticsShared.swift` | Create | Shared presentation helpers, UIViewRepresentable text view, activity share sheet, miniStat helper |
| `native/ios-app/App/DeveloperTools/FireAccountStatusView.swift` | Create | Account status detail page (session info section from old FireDeveloperToolsView) |
| `native/ios-app/App/DeveloperTools/FireNetworkDiagnosticsView.swift` | Create | Network traces list + row component |
| `native/ios-app/App/DeveloperTools/FireNetworkTraceDetailView.swift` | Create | 4-tab network request detail (Overview/Request/Response/Timeline) |
| `native/ios-app/App/DeveloperTools/FireLogDiagnosticsView.swift` | Create | Log files list + log viewer |
| `native/ios-app/App/DeveloperTools/FireAPMDiagnosticsView.swift` | Create | APM real-time metrics + event list detail page |
| `native/ios-app/App/DeveloperTools/FirePushDiagnosticsView.swift` | Create | Push notification diagnostics detail page |
| `native/ios-app/App/DeveloperTools/FireExportDiagnosticsView.swift` | Create | Export & share functionality (Rust snapshot + APM bundle) |
| `native/ios-app/App/DeveloperTools/FireDeveloperToolsView.swift` | Create | New top-level page with 6 NavigationLinks + action buttons |
| `native/ios-app/App/FireDeveloperToolsView.swift` | Delete | Replaced by DeveloperTools/FireDeveloperToolsView.swift |
| `native/ios-app/App/FireDiagnosticsView.swift` | Delete | All content redistributed to DeveloperTools/ |
| `native/ios-app/App/FireOnboardingView.swift` | Modify | Swap NavigationLink destination (line 118) |

---

### Task 1: Extract ViewModel and data models

**Files:**
- Create: `native/ios-app/App/DeveloperTools/FireDiagnosticsViewModel.swift`

- [ ] **Step 1: Create the DeveloperTools directory**

```bash
mkdir -p native/ios-app/App/DeveloperTools
```

- [ ] **Step 2: Create FireDiagnosticsViewModel.swift**

Create `native/ios-app/App/DeveloperTools/FireDiagnosticsViewModel.swift` with the exact content from `FireDiagnosticsView.swift` lines 1-605, but with:
- `import Foundation` and `import SwiftUI` at the top
- Remove `private` from `FireDiagnosticsTextWindow` (it is already not private, but confirm)
- Remove `private` from `FireDiagnosticsPagedTextDocument` (it is already not private, but confirm)
- Remove `private` from `FireDiagnosticsShareRequest` (it is already not private, but confirm)
- Remove `private` from `FireDiagnosticsViewModel` (it is already not private, but confirm)

The file content is lines 1-605 of `FireDiagnosticsView.swift` exactly as-is. These types are already `internal` access level, so no access modifier changes are needed.

```swift
import Foundation
import SwiftUI

struct FireDiagnosticsTextWindow: Equatable {
    // ... exact content from lines 5-45
}

struct FireDiagnosticsPagedTextDocument: Equatable {
    // ... exact content from lines 47-132
}

struct FireDiagnosticsShareRequest: Identifiable, Equatable {
    // ... exact content from lines 134-138
}

@MainActor
final class FireDiagnosticsViewModel: ObservableObject {
    // ... exact content from lines 140-605
}
```

- [ ] **Step 3: Verify the project builds**

```bash
cd native/ios-app && xcodebuild -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5
```

Expected: Build succeeds (duplicate symbol warnings are OK at this stage since the old file still exists).

- [ ] **Step 4: Commit**

```bash
git add native/ios-app/App/DeveloperTools/FireDiagnosticsViewModel.swift
git commit -m "refactor(ios): extract FireDiagnosticsViewModel to DeveloperTools/"
```

---

### Task 2: Extract shared presentation utilities

**Files:**
- Create: `native/ios-app/App/DeveloperTools/FireDiagnosticsShared.swift`

- [ ] **Step 1: Create FireDiagnosticsShared.swift**

Create `native/ios-app/App/DeveloperTools/FireDiagnosticsShared.swift` with content extracted from `FireDiagnosticsView.swift`:
- `FireDiagnosticsPresentation` (lines 1975-2016) -- remove `private` access modifier
- `FireDiagnosticsTextView` (lines 1943-1971) -- remove `private` access modifier
- `FireActivityShareSheet` (lines 2018-2033) -- remove `private` access modifier
- New `FireDiagnosticsMiniStat` view extracted from the `miniStat` function (line 1027-1037) -- made into a standalone `View` struct

```swift
import SwiftUI
import UIKit

// MARK: - Presentation Helpers

enum FireDiagnosticsPresentation {
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    static func timestamp(_ unixMilliseconds: UInt64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixMilliseconds) / 1000)
        return timestampFormatter.string(from: date)
    }

    static func byteSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func compactURL(_ rawValue: String) -> String {
        guard let url = URL(string: rawValue) else {
            return rawValue
        }

        let path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            return "\(path)?\(query)"
        }
        return path
    }

    static func outcome(_ trace: NetworkTraceSummaryState) -> String {
        switch trace.outcome {
        case .inProgress:
            return "进行中"
        case .succeeded:
            return "成功"
        case .failed:
            return "失败"
        case .cancelled:
            return "已取消"
        }
    }
}

// MARK: - Mini Stat View

struct FireDiagnosticsMiniStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Text View (UIViewRepresentable)

struct FireDiagnosticsTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = true
        textView.backgroundColor = .clear
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.text = text
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            uiView.setContentOffset(.zero, animated: false)
        }
    }
}

// MARK: - Activity Share Sheet

struct FireActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let subject: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.setValue(subject, forKey: "subject")
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
```

- [ ] **Step 2: Verify the project builds**

```bash
cd native/ios-app && xcodebuild -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5
```

Expected: Build succeeds. Duplicate symbols may exist for now.

- [ ] **Step 3: Commit**

```bash
git add native/ios-app/App/DeveloperTools/FireDiagnosticsShared.swift
git commit -m "refactor(ios): extract shared diagnostics utilities to DeveloperTools/"
```

---

### Task 3: Extract Account Status view

**Files:**
- Create: `native/ios-app/App/DeveloperTools/FireAccountStatusView.swift`

- [ ] **Step 1: Create FireAccountStatusView.swift**

Extract the `sessionSection` content from the old `FireDeveloperToolsView.swift` (lines 33-104) into a standalone view:

```swift
import SwiftUI

struct FireAccountStatusView: View {
    @ObservedObject var viewModel: FireAppViewModel

    private var isLoggedIn: Bool {
        viewModel.session.readiness.canReadAuthenticatedApi
    }

    private var sessionStatusColor: Color {
        if viewModel.session.readiness.hasCurrentUser {
            return .green
        }
        if isLoggedIn {
            return .orange
        }
        return .red
    }

    var body: some View {
        List {
            Section("会话信息") {
                LabeledContent("账号") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(sessionStatusColor)
                            .frame(width: 8, height: 8)
                        Text(viewModel.session.bootstrap.currentUsername ?? (isLoggedIn ? "等待同步" : "未登录"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("登录阶段", value: viewModel.session.profileStatusTitle)

                LabeledContent("Base URL", value: viewModel.session.bootstrap.baseUrl)

                LabeledContent("Bootstrap") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.session.bootstrap.hasPreloadedData ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(viewModel.session.bootstrap.hasPreloadedData ? "就绪" : "等待中")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("站点元数据") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.session.bootstrap.hasSiteMetadata ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(viewModel.session.bootstrap.hasSiteMetadata ? "就绪" : "缺失")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("站点设置") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.session.bootstrap.hasSiteSettings ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(viewModel.session.bootstrap.hasSiteSettings ? "就绪" : "缺失")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("CSRF") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.session.cookies.csrfToken != nil ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(viewModel.session.cookies.csrfToken != nil ? "就绪" : "缺失")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("API 权限") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.session.readiness.canReadAuthenticatedApi ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(viewModel.session.readiness.canReadAuthenticatedApi ? "可用" : "不可用")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("账户状态")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 2: Verify the project builds**

```bash
cd native/ios-app && xcodebuild -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add native/ios-app/App/DeveloperTools/FireAccountStatusView.swift
git commit -m "refactor(ios): extract FireAccountStatusView to DeveloperTools/"
```

---

### Task 4: Extract Network diagnostics views

**Files:**
- Create: `native/ios-app/App/DeveloperTools/FireNetworkDiagnosticsView.swift`
- Create: `native/ios-app/App/DeveloperTools/FireNetworkTraceDetailView.swift`

- [ ] **Step 1: Create FireNetworkDiagnosticsView.swift**

Extract from `FireDiagnosticsView.swift` lines 1148-1263. Remove `private` access. This contains `FireNetworkTracesListView` and `FireRequestTraceRow`.

```swift
import SwiftUI

struct FireNetworkTracesListView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel

    var body: some View {
        List {
            if viewModel.requestTraces.isEmpty {
                ContentUnavailableView(
                    "暂无请求记录",
                    systemImage: "network.slash",
                    description: Text("尚未捕获到任何网络请求。")
                )
            } else {
                ForEach(viewModel.requestTraces, id: \.id) { trace in
                    NavigationLink {
                        FireRequestTraceDetailView(viewModel: viewModel, traceID: trace.id)
                    } label: {
                        FireRequestTraceRow(trace: trace)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("网络请求")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FireRequestTraceRow: View {
    let trace: NetworkTraceSummaryState

    // ... exact content from lines 1180-1262 of FireDiagnosticsView.swift
    // (statusColor, errorColor, methodColor computed properties, body, outcomeIcon)
}
```

Copy lines 1177-1263 exactly, removing the `private` keyword from both struct declarations.

- [ ] **Step 2: Create FireNetworkTraceDetailView.swift**

Extract from `FireDiagnosticsView.swift` lines 1267-1801. Remove `private` access.

```swift
import SwiftUI

struct FireRequestTraceDetailView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel
    let traceID: UInt64

    // ... exact content from lines 1271-1801 of FireDiagnosticsView.swift
    // (selectedTab state, DetailTab enum, bodyDocument, body,
    //  copyToClipboard, fullHTTPText, requestSummaryBar,
    //  overviewContent, requestContent, responseContent, timelineContent,
    //  kvRow, headersBlock, sectionHeader, emptyNote, methodColor, statusCodeColor)
}
```

Copy lines 1267-1801 exactly, removing the `private` keyword from the struct declaration. All internal methods and properties remain `private` within the struct.

- [ ] **Step 3: Verify the project builds**

```bash
cd native/ios-app && xcodebuild -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add native/ios-app/App/DeveloperTools/FireNetworkDiagnosticsView.swift native/ios-app/App/DeveloperTools/FireNetworkTraceDetailView.swift
git commit -m "refactor(ios): extract network diagnostics views to DeveloperTools/"
```

---

### Task 5: Extract Log diagnostics views

**Files:**
- Create: `native/ios-app/App/DeveloperTools/FireLogDiagnosticsView.swift`

- [ ] **Step 1: Create FireLogDiagnosticsView.swift**

Extract from `FireDiagnosticsView.swift` lines 1805-1941. Remove `private` access from both structs.

```swift
import SwiftUI

struct FireLogFilesListView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel

    var body: some View {
        // ... exact content from lines 1808-1845
    }
}

struct FireDiagnosticsLogView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel
    let relativePath: String

    // ... exact content from lines 1854-1940
}
```

Copy lines 1805-1941 exactly, removing `private` from both `FireLogFilesListView` and `FireDiagnosticsLogView` struct declarations.

- [ ] **Step 2: Verify the project builds**

```bash
cd native/ios-app && xcodebuild -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add native/ios-app/App/DeveloperTools/FireLogDiagnosticsView.swift
git commit -m "refactor(ios): extract log diagnostics views to DeveloperTools/"
```

---

### Task 6: Extract APM diagnostics view

**Files:**
- Create: `native/ios-app/App/DeveloperTools/FireAPMDiagnosticsView.swift`

- [ ] **Step 1: Create FireAPMDiagnosticsView.swift**

Extract from the `apmCard` property in `FireDiagnosticsView.swift` (lines 886-946) into a standalone detail page. Replace the inline `miniStat` calls with `FireDiagnosticsMiniStat`.

```swift
import SwiftUI

struct FireAPMDiagnosticsView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel

    var body: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    FireDiagnosticsMiniStat(
                        value: viewModel.apmSummary.currentSample?.cpuPercent.map {
                            String(format: "%.1f%%", $0)
                        } ?? "N/A",
                        label: "CPU",
                        color: .primary
                    )
                    FireDiagnosticsMiniStat(
                        value: viewModel.apmSummary.currentSample?.physicalFootprintBytes.map {
                            FireDiagnosticsPresentation.byteSize($0)
                        } ?? "N/A",
                        label: "Footprint",
                        color: .secondary
                    )
                    FireDiagnosticsMiniStat(
                        value: "\(viewModel.apmSummary.recentCrashes.count)",
                        label: "Crash",
                        color: viewModel.apmSummary.recentCrashes.isEmpty ? .secondary : .red
                    )
                    FireDiagnosticsMiniStat(
                        value: "\(viewModel.apmSummary.recentStalls.count)",
                        label: "卡顿",
                        color: viewModel.apmSummary.recentStalls.isEmpty ? .secondary : .orange
                    )
                }
            }

            Section("最近事件") {
                if viewModel.apmSummary.recentEvents.isEmpty {
                    Text("暂无 APM 事件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.apmSummary.recentEvents) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.caption.weight(.semibold))
                            if let subtitle = event.subtitle {
                                Text(subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(FireDiagnosticsPresentation.timestamp(event.timestampUnixMs))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("APM")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 2: Verify the project builds**

```bash
cd native/ios-app && xcodebuild -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add native/ios-app/App/DeveloperTools/FireAPMDiagnosticsView.swift
git commit -m "refactor(ios): extract APM diagnostics view to DeveloperTools/"
```

---

### Task 7: Extract Push diagnostics view

**Files:**
- Create: `native/ios-app/App/DeveloperTools/FirePushDiagnosticsView.swift`

- [ ] **Step 1: Create FirePushDiagnosticsView.swift**

Extract from the `pushCard` property in `FireDiagnosticsView.swift` (lines 948-1025) plus the `pushActionTitle` helper (lines 1121-1129) into a standalone detail page. Replace `miniStat` calls with `FireDiagnosticsMiniStat`.

```swift
import SwiftUI

struct FirePushDiagnosticsView: View {
    @ObservedObject var pushCoordinator: FirePushRegistrationCoordinator

    var body: some View {
        let diagnostics = pushCoordinator.diagnostics

        List {
            Section {
                Text("当前阶段只申请系统通知权限并在本地保存 APNs token；不会把 token 上传到 LinuxDo 后端。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 0) {
                    FireDiagnosticsMiniStat(
                        value: diagnostics.authorizationStatusTitle,
                        label: "权限",
                        color: diagnostics.authorizationStatus == .denied ? .red : .primary
                    )
                    FireDiagnosticsMiniStat(
                        value: diagnostics.registrationStateTitle,
                        label: "注册状态",
                        color: diagnostics.registrationState == .failed ? .red : .secondary
                    )
                }
            }

            if let deviceToken = diagnostics.deviceTokenHex, !deviceToken.isEmpty {
                Section("Device Token") {
                    Text(deviceToken)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            if let errorMessage = diagnostics.lastErrorMessage, !errorMessage.isEmpty {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        Task {
                            await pushCoordinator.ensurePushRegistration()
                        }
                    } label: {
                        Label(pushActionTitle(for: diagnostics), systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("刷新状态") {
                        Task {
                            await pushCoordinator.refreshAuthorizationStatus()
                        }
                    }
                    .buttonStyle(.bordered)
                }

                if diagnostics.authorizationStatus == .denied {
                    Text("如需继续验证 APNs 注册，请先在系统设置里重新开启通知权限。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let updatedAt = diagnostics.lastUpdatedAtUnixMs {
                Section {
                    Text("最近更新：\(FireDiagnosticsPresentation.timestamp(updatedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("推送诊断")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pushActionTitle(for diagnostics: FirePushRegistrationDiagnostics) -> String {
        switch diagnostics.authorizationStatus {
        case .notDetermined:
            return "请求权限"
        case .denied:
            return "重新检测"
        default:
            return "重新注册"
        }
    }
}
```

- [ ] **Step 2: Verify the project builds**

```bash
cd native/ios-app && xcodebuild -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add native/ios-app/App/DeveloperTools/FirePushDiagnosticsView.swift
git commit -m "refactor(ios): extract push diagnostics view to DeveloperTools/"
```

---

### Task 8: Extract Export diagnostics view

**Files:**
- Create: `native/ios-app/App/DeveloperTools/FireExportDiagnosticsView.swift`

- [ ] **Step 1: Create FireExportDiagnosticsView.swift**

Extract from `supportBundleCard` (lines 755-838), `supportBundleMetadata` (lines 840-858), `fullAPMSupportBundleMetadata` (lines 861-883), `exportFormatBadge` (lines 1039-1049), `exportActionTile` (lines 1051-1119), and `scenePhaseLabel` (lines 1132-1143) into a standalone detail page. This view owns the `.sheet(item:)` for share presentation and reads `@Environment(\.scenePhase)`.

```swift
import SwiftUI

struct FireExportDiagnosticsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: FireDiagnosticsViewModel

    var body: some View {
        List {
            Section {
                // Session ID
                if let diagnosticSessionID = viewModel.diagnosticSessionID {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session ID")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(diagnosticSessionID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Rust 诊断快照") {
                exportActionTile(
                    title: "Rust 诊断快照",
                    subtitle: "JSON，包含当前会话、最近日志和网络请求摘要，适合快速留档或单独转交。",
                    formatLabel: "JSON",
                    accent: .gray,
                    primaryProminent: false,
                    isBusy: viewModel.isExportingSupportBundle,
                    primaryTitle: viewModel.isExportingSupportBundle ? "导出中…" : "导出 JSON",
                    primarySystemImage: "doc.badge.arrow.up",
                    onPrimaryTap: {
                        viewModel.exportSupportBundle(
                            scenePhase: scenePhaseLabel(scenePhase)
                        )
                    },
                    secondaryTitle: viewModel.supportBundleURL() == nil ? nil : "分享上次导出",
                    onSecondaryTap: {
                        viewModel.presentSupportBundleShare()
                    }
                ) {
                    supportBundleMetadata
                }
            }

            Section("完整 APM 采集包") {
                exportActionTile(
                    title: "完整 APM 采集包",
                    subtitle: "ZIP，附带 crash、MetricKit、runtime breadcrumbs 以及临时生成的 Rust 诊断快照，适合完整排障。",
                    formatLabel: "ZIP",
                    accent: .teal,
                    primaryProminent: true,
                    isBusy: viewModel.isExportingFullAPMSupportBundle,
                    primaryTitle: viewModel.isExportingFullAPMSupportBundle ? "生成中…" : "生成并分享 ZIP",
                    primarySystemImage: "archivebox",
                    onPrimaryTap: {
                        viewModel.exportFullAPMSupportBundle(
                            scenePhase: scenePhaseLabel(scenePhase)
                        )
                    },
                    secondaryTitle: viewModel.fullAPMSupportBundleURL() == nil ? nil : "再次分享",
                    onSecondaryTap: {
                        viewModel.presentFullAPMSupportBundleShare()
                    }
                ) {
                    fullAPMSupportBundleMetadata
                }

                Label("完整 APM ZIP 最多保留最近 3 份，并在 24 小时后自动过期清理；打包临时目录会在导出结束后立即删除。", systemImage: "trash.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("导出与分享")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $viewModel.shareRequest) { request in
            FireActivityShareSheet(
                activityItems: [request.url],
                subject: request.title
            )
        }
    }

    // MARK: - Metadata Views

    @ViewBuilder
    private var supportBundleMetadata: some View {
        if let export = viewModel.latestSupportBundle {
            VStack(alignment: .leading, spacing: 4) {
                Text("最近导出：\(FireDiagnosticsPresentation.timestamp(export.createdAtUnixMs)) · \(FireDiagnosticsPresentation.byteSize(export.sizeBytes))")
                    .font(.caption.weight(.medium))
                Text(export.fileName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                Text(export.relativePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } else {
            Text("输出单个 JSON 文件，不会触发额外的目录打包。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var fullAPMSupportBundleMetadata: some View {
        if viewModel.isExportingFullAPMSupportBundle {
            Text("正在汇总采集目录并生成 ZIP，完成后会直接拉起系统分享。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let export = viewModel.latestFullAPMSupportBundle {
            VStack(alignment: .leading, spacing: 4) {
                Text("ZIP 已就绪：\(FireDiagnosticsPresentation.timestamp(export.createdAtUnixMs)) · \(FireDiagnosticsPresentation.byteSize(export.sizeBytes))")
                    .font(.caption.weight(.medium))
                Text(export.fileName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                Text(export.absoluteURL.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } else {
            Text("导出时会先临时组包，再写入单个 ZIP 文件；中间目录不会长期留在本地。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Reusable Components

    private func exportFormatBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }

    private func exportActionTile<Metadata: View>(
        title: String,
        subtitle: String,
        formatLabel: String,
        accent: Color,
        primaryProminent: Bool,
        isBusy: Bool,
        primaryTitle: String,
        primarySystemImage: String,
        onPrimaryTap: @escaping () -> Void,
        secondaryTitle: String?,
        onSecondaryTap: @escaping () -> Void = {},
        @ViewBuilder metadata: () -> Metadata
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                exportFormatBadge(formatLabel, color: accent)
            }

            HStack(spacing: 10) {
                if primaryProminent {
                    Button(action: onPrimaryTap) {
                        Label(primaryTitle, systemImage: primarySystemImage)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
                } else {
                    Button(action: onPrimaryTap) {
                        Label(primaryTitle, systemImage: primarySystemImage)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                }

                if let secondaryTitle {
                    Button(action: onSecondaryTap) {
                        Label(secondaryTitle, systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            metadata()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }

    private func scenePhaseLabel(_ phase: ScenePhase) -> String {
        switch phase {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .background:
            return "background"
        @unknown default:
            return "unknown"
        }
    }
}
```

- [ ] **Step 2: Verify the project builds**

```bash
cd native/ios-app && xcodebuild -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add native/ios-app/App/DeveloperTools/FireExportDiagnosticsView.swift
git commit -m "refactor(ios): extract export diagnostics view to DeveloperTools/"
```

---

### Task 9: Build new top-level FireDeveloperToolsView

**Files:**
- Create: `native/ios-app/App/DeveloperTools/FireDeveloperToolsView.swift`

- [ ] **Step 1: Create the new FireDeveloperToolsView.swift**

This is the new first-level page. It creates the `FireDiagnosticsViewModel` as `@StateObject` and presents 6 NavigationLinks with summary previews.

```swift
import SwiftUI

struct FireDeveloperToolsView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @StateObject private var diagnosticsViewModel: FireDiagnosticsViewModel
    @StateObject private var pushRegistrationCoordinator = FirePushRegistrationCoordinator.shared

    init(viewModel: FireAppViewModel) {
        self.viewModel = viewModel
        _diagnosticsViewModel = StateObject(
            wrappedValue: FireDiagnosticsViewModel(appViewModel: viewModel)
        )
    }

    private var isLoggedIn: Bool {
        viewModel.session.readiness.canReadAuthenticatedApi
    }

    private var sessionStatusColor: Color {
        if viewModel.session.readiness.hasCurrentUser {
            return .green
        }
        if isLoggedIn {
            return .orange
        }
        return .red
    }

    var body: some View {
        List {
            if let errorMessage = diagnosticsViewModel.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                NavigationLink {
                    FireAccountStatusView(viewModel: viewModel)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("账户状态")
                            Text(viewModel.session.profileStatusTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.circle")
                            .foregroundStyle(sessionStatusColor)
                    }
                }

                NavigationLink {
                    FireNetworkTracesListView(viewModel: diagnosticsViewModel)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("网络状态")
                            HStack(spacing: 6) {
                                Text("\(diagnosticsViewModel.requestTraces.count) 请求")
                                if diagnosticsViewModel.failedCount > 0 {
                                    Text("· \(diagnosticsViewModel.failedCount) 失败")
                                        .foregroundStyle(.red)
                                }
                                if let avgMs = diagnosticsViewModel.averageDurationMs {
                                    Text("· \(avgMs)ms")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "network")
                    }
                }

                NavigationLink {
                    FireLogFilesListView(viewModel: diagnosticsViewModel)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("日志")
                            Text("\(diagnosticsViewModel.logFiles.count) 文件 · \(FireDiagnosticsPresentation.byteSize(diagnosticsViewModel.totalLogSizeBytes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc.text")
                    }
                }

                NavigationLink {
                    FireAPMDiagnosticsView(viewModel: diagnosticsViewModel)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("APM")
                            HStack(spacing: 6) {
                                Text("CPU \(diagnosticsViewModel.apmSummary.currentSample?.cpuPercent.map { String(format: "%.0f%%", $0) } ?? "N/A")")
                                Text("· \(diagnosticsViewModel.apmSummary.currentSample?.physicalFootprintBytes.map { FireDiagnosticsPresentation.byteSize($0) } ?? "N/A")")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "chart.bar")
                    }
                }

                NavigationLink {
                    FirePushDiagnosticsView(pushCoordinator: pushRegistrationCoordinator)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("推送诊断")
                            Text("\(pushRegistrationCoordinator.diagnostics.authorizationStatusTitle) · \(pushRegistrationCoordinator.diagnostics.registrationStateTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bell")
                    }
                }

                NavigationLink {
                    FireExportDiagnosticsView(viewModel: diagnosticsViewModel)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("导出与分享")
                            if let sessionID = diagnosticsViewModel.diagnosticSessionID {
                                Text(String(sessionID.prefix(12)) + "...")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }

            Section {
                Button {
                    viewModel.refreshBootstrap()
                } label: {
                    Label("刷新 Bootstrap", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(viewModel.isLoggingOut)

                Button {
                    viewModel.loadInitialState()
                } label: {
                    Label("恢复会话", systemImage: "arrow.counterclockwise")
                }
                .disabled(viewModel.isLoggingOut)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("开发者工具")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            diagnosticsViewModel.refresh()
            await pushRegistrationCoordinator.refreshAuthorizationStatus()
        }
        .refreshable {
            diagnosticsViewModel.refresh()
            await pushRegistrationCoordinator.refreshAuthorizationStatus()
        }
    }
}
```

- [ ] **Step 2: Verify the project builds**

At this stage both the old and new `FireDeveloperToolsView` exist. The old one in `App/` and the new one in `App/DeveloperTools/`. There will be a duplicate type error. This is expected -- we will delete the old files in the next task.

- [ ] **Step 3: Commit (do not build yet -- old files still present)**

```bash
git add native/ios-app/App/DeveloperTools/FireDeveloperToolsView.swift
git commit -m "refactor(ios): create new FireDeveloperToolsView with 6 NavigationLinks"
```

---

### Task 10: Delete old files and update entry points

**Files:**
- Delete: `native/ios-app/App/FireDeveloperToolsView.swift`
- Delete: `native/ios-app/App/FireDiagnosticsView.swift`
- Modify: `native/ios-app/App/FireOnboardingView.swift` (line 118)

- [ ] **Step 1: Delete the old FireDeveloperToolsView.swift**

```bash
rm native/ios-app/App/FireDeveloperToolsView.swift
```

- [ ] **Step 2: Delete the old FireDiagnosticsView.swift**

```bash
rm native/ios-app/App/FireDiagnosticsView.swift
```

- [ ] **Step 3: Update FireOnboardingView.swift**

Change line 118 from:

```swift
                        FireDiagnosticsView(viewModel: viewModel)
```

to:

```swift
                        FireDeveloperToolsView(viewModel: viewModel)
```

This changes the unauthenticated entry point (ant icon) to navigate to the new flattened developer tools page instead of the deleted diagnostics dashboard.

- [ ] **Step 4: Verify the project builds cleanly**

```bash
cd native/ios-app && xcodebuild -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED with no errors. If there are "missing type" errors, check that all references to `FireDiagnosticsView` have been updated.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(ios): remove old diagnostics monolith, update entry points

- Delete FireDeveloperToolsView.swift (replaced by DeveloperTools/)
- Delete FireDiagnosticsView.swift (2033 lines decomposed into 10 files)
- Update FireOnboardingView to navigate to new FireDeveloperToolsView"
```

---

### Task 11: Final verification

- [ ] **Step 1: Clean build**

```bash
cd native/ios-app && xcodebuild clean build -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Verify file count**

```bash
ls -la native/ios-app/App/DeveloperTools/
```

Expected: 10 Swift files:
- `FireAccountStatusView.swift`
- `FireAPMDiagnosticsView.swift`
- `FireDeveloperToolsView.swift`
- `FireDiagnosticsShared.swift`
- `FireDiagnosticsViewModel.swift`
- `FireExportDiagnosticsView.swift`
- `FireLogDiagnosticsView.swift`
- `FireNetworkDiagnosticsView.swift`
- `FireNetworkTraceDetailView.swift`
- `FirePushDiagnosticsView.swift`

- [ ] **Step 3: Verify old files are gone**

```bash
ls native/ios-app/App/FireDiagnosticsView.swift native/ios-app/App/FireDeveloperToolsView.swift 2>&1
```

Expected: "No such file or directory" for both

- [ ] **Step 4: Verify no dangling references**

```bash
grep -r "FireDiagnosticsView" native/ios-app/App/ --include="*.swift" | grep -v "DeveloperTools/"
```

Expected: No output (no references to the old `FireDiagnosticsView` outside of `DeveloperTools/`)

- [ ] **Step 5: Run the app in simulator**

Launch the app in the iOS Simulator. Test:
1. Profile tab -> gear menu -> Developer Tools: 6 items visible with preview summaries
2. Tap each item: Account Status, Network, Logs, APM, Push Diagnostics, Export
3. Network detail: 4 tabs (Overview/Request/Response/Timeline) work
4. Log viewer: loads and paginates
5. Export: JSON and ZIP export work, share sheet opens
6. Onboarding: ant icon -> Developer Tools page (same 6 items)
