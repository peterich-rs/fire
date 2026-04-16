import SwiftUI
import UIKit

// MARK: - Request Trace Detail (Tabbed -- Postman style)

struct FireRequestTraceDetailView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel
    let traceID: UInt64

    @State private var selectedTab: DetailTab = .overview
    @State private var showCopiedToast = false

    enum DetailTab: String, CaseIterable {
        case overview = "概要"
        case request = "Request"
        case response = "Response"
        case timeline = "Timeline"
    }

    private var bodyDocument: FireDiagnosticsPagedTextDocument? {
        viewModel.traceBodyDocument(traceID: traceID)
    }

    var body: some View {
        Group {
            if let detail = viewModel.requestTraceDetail(traceID: traceID) {
                VStack(spacing: 0) {
                    requestSummaryBar(detail: detail)

                    Picker("Tab", selection: $selectedTab) {
                        ForEach(DetailTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    Divider()

                    ScrollView {
                        switch selectedTab {
                        case .overview:
                            overviewContent(detail: detail)
                        case .request:
                            requestContent(detail: detail)
                        case .response:
                            responseContent(detail: detail)
                        case .timeline:
                            timelineContent(detail: detail)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            copyToClipboard(
                                fullHTTPText(
                                    detail: detail,
                                    bodyText: bodyDocument?.renderedText ?? detail.responseBody
                                )
                            )
                        } label: {
                            Label("复制全部", systemImage: "doc.on.doc")
                        }
                    }
                }
            } else {
                ProgressView("加载请求详情…")
                    .task {
                        viewModel.loadTraceDetail(traceID: traceID)
                    }
            }
        }
        .navigationTitle("请求详情")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                Text("已复制")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(.label).opacity(0.85), in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(duration: 0.3), value: showCopiedToast)
    }

    // MARK: - Copy Helper

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        guard !showCopiedToast else { return }
        withAnimation { showCopiedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { showCopiedToast = false }
        }
    }

    // MARK: - Full Request Copy

    private func fullHTTPText(
        detail: NetworkTraceDetailState,
        bodyText: String?
    ) -> String {
        var lines: [String] = []

        lines.append("\(detail.summary.method) \(detail.summary.url) HTTP/1.1")

        if !detail.requestHeaders.isEmpty {
            for h in detail.requestHeaders {
                lines.append("\(h.name): \(h.value)")
            }
        }

        lines.append("")

        if let statusCode = detail.summary.statusCode {
            lines.append("HTTP/1.1 \(statusCode)")
        }

        if !detail.responseHeaders.isEmpty {
            for h in detail.responseHeaders {
                lines.append("\(h.name): \(h.value)")
            }
        }

        if let bodyText, !bodyText.isEmpty {
            lines.append("")
            lines.append(bodyText)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Summary Bar (always visible at top)

    private func requestSummaryBar(detail: NetworkTraceDetailState) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(detail.summary.method)
                    .font(.subheadline.monospaced().weight(.bold))
                    .foregroundStyle(methodColor(detail.summary.method))

                if let statusCode = detail.summary.statusCode {
                    Text("\(statusCode)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(statusCodeColor(statusCode))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusCodeColor(statusCode).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                Spacer()

                if let durationMs = detail.summary.durationMs {
                    Label("\(durationMs)ms", systemImage: "clock")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(detail.summary.url)
                .font(.caption.monospaced())
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Overview Tab

    private func overviewContent(detail: NetworkTraceDetailState) -> some View {
        VStack(spacing: 0) {
            kvRow("Operation", detail.summary.operation)
            kvRow("Method", detail.summary.method)
            kvRow("URL", detail.summary.url, selectable: true)
            kvRow("Started", FireDiagnosticsPresentation.timestamp(detail.summary.startedAtUnixMs))

            if let finishedAtUnixMs = detail.summary.finishedAtUnixMs {
                kvRow("Finished", FireDiagnosticsPresentation.timestamp(finishedAtUnixMs))
            }

            if let durationMs = detail.summary.durationMs {
                kvRow("Duration", "\(durationMs) ms")
            }

            kvRow("Outcome", FireDiagnosticsPresentation.outcome(detail.summary))

            if let statusCode = detail.summary.statusCode {
                kvRow("Status", "HTTP \(statusCode)")
            }

            if let responseBodyBytes = detail.responseBodyBytes {
                kvRow("Body Size", FireDiagnosticsPresentation.byteSize(responseBodyBytes))
            }

            if let storedBytes = detail.responseBodyStoredBytes {
                kvRow("Preview Cache", FireDiagnosticsPresentation.byteSize(storedBytes))
            }

            if let contentType = detail.summary.responseContentType {
                kvRow("Content-Type", contentType)
            }

            if let callID = detail.summary.callId {
                kvRow("Call ID", "\(callID)")
            }

            if let errorMessage = detail.summary.errorMessage {
                kvRow("Error", errorMessage, valueColor: .red)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Request Tab

    private func requestContent(detail: NetworkTraceDetailState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                "Headers (\(detail.requestHeaders.count))",
                copyAction: detail.requestHeaders.isEmpty ? nil : {
                    copyToClipboard(
                        detail.requestHeaders
                            .map { "\($0.name): \($0.value)" }
                            .joined(separator: "\n")
                    )
                }
            )

            if detail.requestHeaders.isEmpty {
                emptyNote("无请求 headers")
            } else {
                headersBlock(detail.requestHeaders)
            }

            // Request body is not captured in the current model,
            // but the section is here for future support.
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Response Tab

    private func responseContent(detail: NetworkTraceDetailState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                "Headers (\(detail.responseHeaders.count))",
                copyAction: detail.responseHeaders.isEmpty ? nil : {
                    copyToClipboard(
                        detail.responseHeaders
                            .map { "\($0.name): \($0.value)" }
                            .joined(separator: "\n")
                    )
                }
            )

            if detail.responseHeaders.isEmpty {
                emptyNote("无响应 headers")
            } else {
                headersBlock(detail.responseHeaders)
            }

            sectionHeader(
                "Body",
                copyAction: {
                    guard let body = bodyDocument?.renderedText ?? detail.responseBody, !body.isEmpty else { return }
                    copyToClipboard(body)
                }
            )

            if let document = bodyDocument {
                VStack(alignment: .leading, spacing: 8) {
                    if detail.responseBodyStorageTruncated {
                        Label("响应 body 仅保留前 256 KB 缓存预览，无法回看原始尾部。", systemImage: "scissors")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if detail.responseBodyPageAvailable {
                        Label("当前仅内联首屏预览，可继续按需加载。", systemImage: "text.append")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        if let storedBytes = detail.responseBodyStoredBytes {
                            Text("已加载 \(FireDiagnosticsPresentation.byteSize(document.loadedBytes)) / \(FireDiagnosticsPresentation.byteSize(storedBytes))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if bodyDocument?.hasLoadedAdditionalPages == true {
                            Button("回到首屏") {
                                viewModel.resetTraceBodyPreview(traceID: traceID)
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                    }

                    HStack(spacing: 8) {
                        if document.newerCursor != nil {
                            Button("加载更多") {
                                viewModel.loadNewerTraceBodyPage(traceID: traceID)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if detail.responseBodyPageAvailable || detail.responseBodyStorageTruncated {
                            Button(detail.responseBodyStorageTruncated ? "查看缓存尾部" : "查看尾部") {
                                viewModel.showTraceBodyTail(traceID: traceID)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if document.olderCursor != nil {
                            Button("向前加载") {
                                viewModel.loadOlderTraceBodyPage(traceID: traceID)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if viewModel.isLoadingTraceBodyPage(traceID: traceID) {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    FireDiagnosticsTextView(text: document.renderedText)
                        .frame(minHeight: 220, maxHeight: 360)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            } else {
                emptyNote("未捕获到响应 body")
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Timeline Tab

    private func timelineContent(detail: NetworkTraceDetailState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if detail.events.isEmpty {
                ContentUnavailableView(
                    "无执行链",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    description: Text("该请求没有记录执行事件。")
                )
            } else {
                ForEach(
                    fireIdentifiedValues(detail.events) { $0.fireStableBaseID }
                ) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(item.index == 0 ? Color.accentColor : Color(.tertiaryLabel))
                                .frame(width: 8, height: 8)

                            if item.index < detail.events.count - 1 {
                                Rectangle()
                                    .fill(Color(.separator))
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 8)
                        .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.value.phase)
                                    .font(.caption.monospaced().weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(FireDiagnosticsPresentation.timestamp(item.value.timestampUnixMs))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Text(item.value.summary)
                                .font(.subheadline)

                            if let details = item.value.details, !details.isEmpty {
                                Text(details)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    if item.index < detail.events.count - 1 {
                        Divider()
                            .padding(.leading, 20)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Reusable Parts

    private func kvRow(_ key: String, _ value: String, selectable: Bool = false, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(key)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)

                if selectable {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(valueColor)
                        .textSelection(.enabled)
                } else {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(valueColor)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    copyToClipboard(value)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
            }

            Divider()
        }
    }

    private func headersBlock(_ headers: [NetworkTraceHeaderState]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(fireIdentifiedValues(headers) { $0.fireStableBaseID }) { item in
                (Text("\(item.value.name): ")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.secondary)
                + Text(item.value.value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary))
                .textSelection(.enabled)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu {
                    Button {
                        copyToClipboard("\(item.value.name): \(item.value.value)")
                    } label: {
                        Label("复制 Header", systemImage: "doc.on.doc")
                    }
                    Button {
                        copyToClipboard(item.value.value)
                    } label: {
                        Label("复制值", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        copyToClipboard(item.value.name)
                    } label: {
                        Label("复制名称", systemImage: "character.cursor.ibeam")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func sectionHeader(_ title: String, copyAction: (() -> Void)? = nil) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if let copyAction {
                Button(action: copyAction) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.vertical, 8)
    }

    // MARK: - Color Helpers

    private func methodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .secondary
        }
    }

    private func statusCodeColor(_ code: UInt16) -> Color {
        if code < 300 { return .green }
        if code < 400 { return .orange }
        return .red
    }
}
