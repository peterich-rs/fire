import SwiftUI

// MARK: - Log Files List

struct FireLogFilesListView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel

    var body: some View {
        List {
            if viewModel.logFiles.isEmpty {
                ContentUnavailableView(
                    "暂无日志",
                    systemImage: "doc.text",
                    description: Text("尚未生成任何日志文件。")
                )
            } else {
                ForEach(viewModel.logFiles, id: \.relativePath) { file in
                    NavigationLink {
                        FireDiagnosticsLogView(viewModel: viewModel, relativePath: file.relativePath)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.fileName)
                                    .font(.subheadline.weight(.medium))

                                Text(FireDiagnosticsPresentation.timestamp(file.modifiedAtUnixMs))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(FireDiagnosticsPresentation.byteSize(file.sizeBytes))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("日志文件")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Log Detail View

struct FireDiagnosticsLogView: View {
    @ObservedObject var viewModel: FireDiagnosticsViewModel
    let relativePath: String

    private var fileSummary: LogFileSummaryState? {
        viewModel.logFiles.first { $0.relativePath == relativePath }
    }

    var body: some View {
        Group {
            if let document = viewModel.logDocument(relativePath: relativePath) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fileSummary?.fileName ?? relativePath)
                                .font(.headline)

                            if let fileSummary {
                                Text(FireDiagnosticsPresentation.byteSize(fileSummary.sizeBytes))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text("最新在上，滚动到底部自动加载更早内容")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if document.hasMultipleWindows {
                            Button("回到最新") {
                                viewModel.resetLogFile(relativePath: relativePath)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if document.renderedLines == [""] {
                        Text("暂无日志内容。")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(12)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Text("已加载 \(FireDiagnosticsPresentation.byteSize(document.loadedBytes)) / \(FireDiagnosticsPresentation.byteSize(document.totalBytes))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(document.identifiedRenderedLines) { item in
                                    Text(item.value.isEmpty ? " " : item.value)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                if viewModel.isLoadingLogPage(relativePath: relativePath) {
                                    ProgressView()
                                        .padding(.vertical, 8)
                                } else if document.olderCursor != nil {
                                    Color.clear
                                        .frame(height: 1)
                                        .onAppear {
                                            viewModel.loadOlderLogPage(relativePath: relativePath)
                                        }
                                }
                            }
                            .padding(12)
                            .textSelection(.enabled)
                        }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ProgressView("加载日志…")
                    .task {
                        viewModel.loadLogFile(relativePath: relativePath)
                    }
            }
        }
        .navigationTitle("日志")
        .navigationBarTitleDisplayMode(.inline)
    }
}
