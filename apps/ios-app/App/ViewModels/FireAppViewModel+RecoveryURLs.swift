import Foundation

@MainActor
extension FireAppViewModel {
    var siteRootRecoveryURL: URL? {
        let trimmed = session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawURL = trimmed.isEmpty ? "https://linux.do/" : trimmed
        if rawURL.hasSuffix("/") {
            return URL(string: rawURL)
        }
        return URL(string: "\(rawURL)/")
    }

    func cloudflareRecoveryTopicListURL(query: TopicListQueryState) -> URL {
        Self.cloudflareRecoveryTopicListURL(
            baseURL: session.bootstrap.baseUrl,
            query: query
        )
    }

    func cloudflareRecoveryTopicURL(topicId: UInt64, topicSlug: String?) -> URL {
        Self.cloudflareRecoveryTopicURL(
            baseURL: session.bootstrap.baseUrl,
            topicId: topicId,
            topicSlug: topicSlug
        )
    }

    nonisolated static func cloudflareRecoveryTopicURL(
        baseURL: String,
        topicId: UInt64,
        topicSlug: String?
    ) -> URL {
        let trimmedSlug = topicSlug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var topicURL = normalizedRecoveryRootURL(baseURL: baseURL).appendingPathComponent("t")
        if !trimmedSlug.isEmpty {
            topicURL.appendPathComponent(trimmedSlug)
        }
        topicURL.appendPathComponent(String(topicId))
        return topicURL
    }

    nonisolated static func cloudflareRecoveryTopicListURL(
        baseURL: String,
        query: TopicListQueryState
    ) -> URL {
        var topicListURL = normalizedRecoveryRootURL(baseURL: baseURL)
        let filter = topicListFilterName(query.kind)
        let categorySlug = normalizedTopicListSegment(query.categorySlug)
        let tag = normalizedTopicListSegment(query.tag)

        if let categorySlug {
            topicListURL.appendPathComponent("c")
            if let parentCategorySlug = normalizedTopicListSegment(query.parentCategorySlug) {
                topicListURL.appendPathComponent(parentCategorySlug)
            }
            topicListURL.appendPathComponent(categorySlug)
            if let categoryID = query.categoryId {
                topicListURL.appendPathComponent(String(categoryID))
                topicListURL.appendPathComponent("l")
                topicListURL.appendPathComponent(filter)
            }
        } else if let tag {
            topicListURL.appendPathComponent("tag")
            topicListURL.appendPathComponent(tag)
            topicListURL.appendPathComponent("l")
            topicListURL.appendPathComponent(filter)
        } else {
            switch query.kind {
            case .privateMessagesInbox:
                topicListURL.appendPathComponent("my")
                topicListURL.appendPathComponent("messages")
            case .privateMessagesSent:
                topicListURL.appendPathComponent("my")
                topicListURL.appendPathComponent("messages")
                topicListURL.appendPathComponent("sent")
            default:
                topicListURL.appendPathComponent(query.topicIds.isEmpty ? filter : "latest")
            }
        }

        var queryItems: [URLQueryItem] = []
        if let page = query.page, page > 0 {
            queryItems.append(URLQueryItem(name: "page", value: String(page)))
        }
        let queryTags = topicListRecoveryQueryTags(
            categorySlug: categorySlug,
            primaryTag: tag,
            additionalTags: query.additionalTags
        )
        queryItems.append(contentsOf: queryTags.map { URLQueryItem(name: "tags[]", value: $0) })
        if query.matchAllTags, queryTags.count > 1 {
            queryItems.append(URLQueryItem(name: "match_all_tags", value: "true"))
        }

        return appendingQueryItems(queryItems, to: topicListURL)
    }

    private nonisolated static func normalizedRecoveryRootURL(baseURL: String) -> URL {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawBaseURL = trimmedBaseURL.isEmpty ? "https://linux.do/" : trimmedBaseURL
        let normalizedBaseURL = rawBaseURL.hasSuffix("/") ? rawBaseURL : "\(rawBaseURL)/"
        return URL(string: normalizedBaseURL) ?? URL(string: "https://linux.do/")!
    }

    private nonisolated static func normalizedTopicListSegment(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func topicListFilterName(_ kind: TopicListKindState) -> String {
        switch kind {
        case .latest:
            return "latest"
        case .new:
            return "new"
        case .unread:
            return "unread"
        case .unseen:
            return "unseen"
        case .hot:
            return "hot"
        case .top:
            return "top"
        case .privateMessagesInbox:
            return "private-messages"
        case .privateMessagesSent:
            return "private-messages-sent"
        }
    }

    private nonisolated static func topicListRecoveryQueryTags(
        categorySlug: String?,
        primaryTag: String?,
        additionalTags: [String]
    ) -> [String] {
        var tags: [String] = []
        if categorySlug != nil, let primaryTag {
            tags.append(primaryTag)
        }
        tags.append(contentsOf: additionalTags.compactMap(normalizedTopicListSegment))
        return tags
    }

    private nonisolated static func appendingQueryItems(
        _ queryItems: [URLQueryItem],
        to url: URL
    ) -> URL {
        guard !queryItems.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.queryItems = (components.queryItems ?? []) + queryItems
        return components.url ?? url
    }
}
