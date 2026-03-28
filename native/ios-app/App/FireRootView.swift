import SwiftUI

struct FireRootView: View {
    @StateObject private var viewModel = FireAppViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Session") {
                    LabeledContent("Phase", value: viewModel.session.loginPhase.title)
                    LabeledContent("Has Login", value: boolText(viewModel.session.hasLoginSession))
                    LabeledContent(
                        "Username",
                        value: viewModel.session.bootstrap.currentUsername ?? "-"
                    )
                    LabeledContent(
                        "Bootstrap Ready",
                        value: boolText(viewModel.session.bootstrap.hasPreloadedData)
                    )
                    LabeledContent(
                        "Has CSRF",
                        value: boolText(viewModel.session.cookies.csrfToken != nil)
                    )
                }

                Section("Actions") {
                    Button("Restore Session") {
                        viewModel.loadInitialState()
                    }
                    Button {
                        viewModel.openLogin()
                    } label: {
                        if viewModel.isPreparingLogin {
                            Text("Preparing Login...")
                        } else {
                            Text("Open Login")
                        }
                    }
                    .disabled(viewModel.isPreparingLogin)
                    Button("Refresh Bootstrap") {
                        viewModel.refreshBootstrap()
                    }
                    Button("Logout", role: .destructive) {
                        viewModel.logout()
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section("Last Error") {
                        Text(errorMessage)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Fire Native")
        }
        .fullScreenCover(isPresented: $viewModel.isPresentingLogin) {
            FireLoginScreen(viewModel: viewModel)
        }
        .task {
            viewModel.loadInitialState()
        }
    }

    private func boolText(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
}
