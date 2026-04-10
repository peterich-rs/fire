import SwiftUI

@MainActor
final class FireProfileViewModel: ObservableObject {
    @Published private(set) var profile: UserProfileState?
    @Published private(set) var summary: UserSummaryState?
    @Published private(set) var actions: [UserActionState] = []
    @Published private(set) var isLoadingProfile = false
    @Published private(set) var isLoadingActions = false
    @Published private(set) var selectedTab: ProfileTab = .all
    @Published private(set) var actionsOffset: Int = 0
    @Published private(set) var hasMoreActions = true
    @Published var errorMessage: String?

    enum ProfileTab: String, CaseIterable {
        case all
        case topics
        case replies
        case liked

        var actionFilter: String {
            switch self {
            case .all:     return "4,5"
            case .topics:  return "4"
            case .replies: return "5"
            case .liked:   return "2"
            }
        }

        var title: String {
            switch self {
            case .all:     return "全部"
            case .topics:  return "话题"
            case .replies: return "回复"
            case .liked:   return "被赞"
            }
        }
    }

    private let appViewModel: FireAppViewModel
    private var loadedUsername: String?
    private var profileTask: Task<Void, Never>?
    private var actionsTask: Task<Void, Never>?
    private var profileRequestID: UInt64 = 0
    private var actionsRequestID: UInt64 = 0

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    var currentUsername: String? {
        appViewModel.session.bootstrap.currentUsername
    }

    deinit {
        profileTask?.cancel()
        actionsTask?.cancel()
    }

    func syncWithCurrentSession() {
        let username = normalizedCurrentUsername()
        guard loadedUsername != username else { return }

        resetState(for: username)
        guard username != nil else { return }
        loadProfile(force: true)
    }

    func loadProfile(force: Bool = false) {
        guard let username = normalizedCurrentUsername() else {
            resetState(for: nil)
            return
        }
        guard force || loadedUsername != username || profile == nil || summary == nil else { return }

        profileTask?.cancel()
        profileRequestID &+= 1
        let requestID = profileRequestID

        loadedUsername = username
        isLoadingProfile = true
        errorMessage = nil

        profileTask = Task { [weak self] in
            guard let self else { return }

            do {
                async let profileResult = self.appViewModel.fetchUserProfile(username: username)
                async let summaryResult = self.appViewModel.fetchUserSummary(username: username)
                let (fetchedProfile, fetchedSummary) = try await (profileResult, summaryResult)
                try Task.checkCancellation()
                guard requestID == self.profileRequestID, self.loadedUsername == username else { return }
                self.profile = fetchedProfile
                self.summary = fetchedSummary
                self.isLoadingProfile = false
                self.loadActions(reset: true)
            } catch is CancellationError {
                guard requestID == self.profileRequestID else { return }
                self.isLoadingProfile = false
            } catch {
                guard requestID == self.profileRequestID, self.loadedUsername == username else { return }
                self.isLoadingProfile = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func loadActions(reset: Bool) {
        guard let username = normalizedCurrentUsername(), loadedUsername == username else { return }

        if reset {
            actionsTask?.cancel()
            actionsOffset = 0
            hasMoreActions = true
            actions = []
        } else if isLoadingActions {
            return
        }

        guard hasMoreActions else { return }

        isLoadingActions = true
        errorMessage = nil
        let currentOffset = actionsOffset
        let filter = selectedTab.actionFilter
        actionsRequestID &+= 1
        let requestID = actionsRequestID

        actionsTask = Task { [weak self] in
            guard let self else { return }

            do {
                let fetched = try await self.appViewModel.fetchUserActions(
                    username: username,
                    offset: currentOffset > 0 ? UInt32(currentOffset) : nil,
                    filter: filter
                )
                try Task.checkCancellation()
                guard requestID == self.actionsRequestID,
                      self.loadedUsername == username,
                      filter == self.selectedTab.actionFilter else {
                    return
                }
                if reset {
                    self.actions = fetched
                } else {
                    self.actions.append(contentsOf: fetched)
                }
                self.actionsOffset = self.actions.count
                self.hasMoreActions = !fetched.isEmpty
                self.isLoadingActions = false
            } catch is CancellationError {
                guard requestID == self.actionsRequestID else { return }
                self.isLoadingActions = false
            } catch {
                guard requestID == self.actionsRequestID, self.loadedUsername == username else { return }
                self.isLoadingActions = false
                if self.actions.isEmpty {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func selectTab(_ tab: ProfileTab) {
        guard tab != selectedTab else { return }
        selectedTab = tab
        loadActions(reset: true)
    }

    func refreshAll() async {
        guard let username = normalizedCurrentUsername(), loadedUsername == username else { return }

        do {
            async let profileResult = appViewModel.fetchUserProfile(username: username)
            async let summaryResult = appViewModel.fetchUserSummary(username: username)
            let (fetchedProfile, fetchedSummary) = try await (profileResult, summaryResult)
            guard loadedUsername == username else { return }
            self.profile = fetchedProfile
            self.summary = fetchedSummary
            self.errorMessage = nil
            loadActions(reset: true)
        } catch is CancellationError {
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func retry() {
        loadProfile(force: true)
    }

    private func normalizedCurrentUsername() -> String? {
        guard let username = currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty else {
            return nil
        }

        return username
    }

    private func resetState(for username: String?) {
        profileTask?.cancel()
        actionsTask?.cancel()
        loadedUsername = username
        profileRequestID &+= 1
        actionsRequestID &+= 1
        profile = nil
        summary = nil
        actions = []
        isLoadingProfile = false
        isLoadingActions = false
        selectedTab = .all
        actionsOffset = 0
        hasMoreActions = true
        errorMessage = nil
    }
}
