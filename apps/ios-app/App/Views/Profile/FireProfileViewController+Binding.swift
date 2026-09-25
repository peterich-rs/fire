import Combine
import SnapKit
import SwiftUI
import UIKit

@MainActor
extension FireProfileViewController {
    func bind() {
        profileViewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
                self?.tableView.refreshControl?.endRefreshing()
            }
            .store(in: &cancellables)

        navigationState.$selectedTab
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tab in
                guard let self else { return }
                self.isActive = tab == 2
                if self.isActive {
                    self.profileViewModel.syncWithCurrentSession()
                }
            }
            .store(in: &cancellables)
    }

    @objc
    func handleRefresh() {
        Task { [weak self] in
            await self?.profileViewModel.refreshAll()
            self?.tableView.refreshControl?.endRefreshing()
        }
    }
}
