import SwiftUI

struct FireOnboardingView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @State private var copiedErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [FireTheme.accent, FireTheme.accentSoft],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    VStack(spacing: 8) {
                        Text("Fire")
                            .font(.largeTitle.weight(.bold))

                        Text("LinuxDo 原生客户端")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    if let errorMessage = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.subheadline)

                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Spacer(minLength: 0)

                            Button {
                                viewModel.dismissError()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                        )
                    }

                    Button {
                        viewModel.openLogin()
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isPreparingLogin {
                                ProgressView()
                                    .tint(.white)
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "person.badge.key")
                            }
                            Text(viewModel.isPreparingLogin ? "准备中…" : "登录 LinuxDo")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(FireTheme.accent)
                        )
                    }
                    .disabled(viewModel.isPreparingLogin)

                    Button("恢复已有会话") {
                        viewModel.loadInitialState()
                    }
                    .font(.subheadline)
                    .foregroundStyle(FireTheme.accent)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        FireDiagnosticsView(viewModel: viewModel)
                    } label: {
                        Image(systemName: "ant")
                    }
                }
            }
        }
    }
}
