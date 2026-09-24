import UIKit

extension FireComposerViewController {
    func addTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !selectedTags.contains(trimmed) else { return }
        selectedTags.append(trimmed)
        tagInput = ""
        tagResults = []
        errorMessage = nil
        scheduleAutosave()
        render()
    }

    func addRecipient(_ user: UserMentionUserState) {
        let trimmed = user.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !selectedRecipients.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            recipientQuery = ""
            recipientResults = []
            render()
            return
        }
        selectedRecipients.append(trimmed)
        recipientQuery = ""
        recipientResults = []
        errorMessage = nil
        scheduleAutosave()
        render()
    }

    func removeRecipient(_ username: String) {
        selectedRecipients.removeAll { $0.caseInsensitiveCompare(username) == .orderedSame }
        scheduleAutosave()
    }

    func updateMentionSearch() {
        mentionSearchTask?.cancel()
        mentionContext = mentionContext(in: bodyText, selection: bodySelection)
        guard let mentionContext, !mentionContext.term.isEmpty else {
            mentionUsers = []
            mentionGroups = []
            render()
            return
        }

        mentionSearchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let result = try await viewModel.searchService.searchUsers(
                    term: mentionContext.term,
                    includeGroups: !route.isPrivateMessage,
                    limit: 8,
                    topicID: route.topicID,
                    categoryID: selectedCategoryID ?? route.fallbackCategoryID
                )
                guard !Task.isCancelled else { return }
                mentionUsers = result.users
                mentionGroups = result.groups
                render()
            } catch {
                guard !Task.isCancelled else { return }
                mentionUsers = []
                mentionGroups = []
                render()
            }
        }
    }

    func performRecipientSearch(query: String) {
        recipientSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            recipientResults = []
            render()
            return
        }

        recipientSearchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let result = try await viewModel.searchService.searchUsers(
                    term: trimmed,
                    includeGroups: false,
                    limit: 8,
                    topicID: nil,
                    categoryID: nil
                )
                guard !Task.isCancelled else { return }
                recipientResults = result.users.filter { user in
                    !selectedRecipients.contains {
                        $0.caseInsensitiveCompare(user.username) == .orderedSame
                    }
                }
                render()
            } catch {
                guard !Task.isCancelled else { return }
                recipientResults = []
                render()
            }
        }
    }

    func performTagSearch(query: String) {
        tagSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            tagResults = []
            render()
            return
        }

        tagSearchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let result = try await viewModel.searchService.searchTags(
                    query: trimmed,
                    filterForInput: true,
                    limit: 12,
                    categoryID: selectedCategoryID,
                    selectedTags: selectedTags
                )
                guard !Task.isCancelled else { return }
                let allowedTags = Set(selectedCategory?.allowedTags ?? [])
                if allowedTags.isEmpty {
                    tagResults = result.results
                } else {
                    tagResults = result.results.filter { allowedTags.contains($0.name) }
                }
                render()
            } catch {
                guard !Task.isCancelled else { return }
                tagResults = []
                render()
            }
        }
    }

    func insertMention(_ mention: String) {
        replaceText(in: mentionContext?.replacementRange ?? bodySelection, with: "\(mention) ")
        mentionContext = nil
        mentionUsers = []
        mentionGroups = []
        render()
    }

    func mentionContext(in text: String, selection: NSRange) -> FireComposerMentionContext? {
        guard selection.length == 0 else { return nil }
        let source = text as NSString
        guard selection.location <= source.length else { return nil }
        let prefix = source.substring(to: selection.location)
        let regex = try? NSRegularExpression(pattern: "(?:^|\\s)@([A-Za-z0-9_-]{1,32})$")
        let range = NSRange(location: 0, length: (prefix as NSString).length)
        guard let match = regex?.firstMatch(in: prefix, range: range) else { return nil }
        let termRange = match.range(at: 1)
        guard termRange.location != NSNotFound else { return nil }
        let term = (prefix as NSString).substring(with: termRange)
        let replacementRange = NSRange(
            location: termRange.location - 1,
            length: selection.location - termRange.location + 1
        )
        return FireComposerMentionContext(replacementRange: replacementRange, term: term)
    }

}
