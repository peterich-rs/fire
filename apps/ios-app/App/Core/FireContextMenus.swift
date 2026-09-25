import SwiftUI
import UIKit

struct FireTopicContextMenu: View {
    let row: FireTopicRowPresentation
    let shareURL: URL
    var onOpen: (() -> Void)?
    var onBookmark: (() -> Void)?
    var onMute: (() -> Void)?

    private var isBookmarked: Bool {
        row.topic.bookmarkId != nil
    }

    var body: some View {
        if let onOpen {
            Button(action: onOpen) {
                Label("打开话题", systemImage: "arrow.up.right")
            }
        }

        if let onBookmark {
            Button(action: onBookmark) {
                Label(isBookmarked ? "编辑书签" : "添加书签", systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
            }
        }

        ShareLink(item: shareURL) {
            Label("分享话题", systemImage: "square.and.arrow.up")
        }

        Button {
            UIPasteboard.general.string = shareURL.absoluteString
        } label: {
            Label("复制链接", systemImage: "doc.on.doc")
        }

        if let onMute {
            Button(action: onMute) {
                Label("静音话题", systemImage: "bell.slash")
            }
        }
    }
}

struct FireNotificationContextMenu: View {
    let item: NotificationItemState
    let shareURL: URL?
    var onOpen: (() -> Void)?
    var onMarkRead: (() -> Void)?

    var body: some View {
        if let onOpen {
            Button(action: onOpen) {
                Label("跳转到通知", systemImage: "arrow.up.right")
            }
        }

        if !item.read, let onMarkRead {
            Button(action: onMarkRead) {
                Label("标记为已读", systemImage: "envelope.open")
            }
        }

        Button {
            UIPasteboard.general.string = item.displayDescription
        } label: {
            Label("复制通知内容", systemImage: "doc.on.doc")
        }

        if let shareURL {
            ShareLink(item: shareURL) {
                Label("分享链接", systemImage: "square.and.arrow.up")
            }

            Button {
                UIPasteboard.general.string = shareURL.absoluteString
            } label: {
                Label("复制链接", systemImage: "link")
            }
        }
    }
}

extension FireTopicRowPresentation {
    func fireTopicURL(baseURL: String) -> URL {
        FireAppViewModel.cloudflareRecoveryTopicURL(
            baseURL: baseURL,
            topicId: topic.id,
            topicSlug: topic.slug
        )
    }

    func fireBookmarkEditorContext() -> FireBookmarkEditorContext {
        FireBookmarkEditorContext(
            bookmarkID: topic.bookmarkId,
            bookmarkableID: topic.id,
            bookmarkableType: topic.bookmarkableType ?? "Topic",
            topicID: topic.id,
            postNumber: topic.bookmarkedPostNumber,
            title: topic.title,
            initialName: topic.bookmarkName,
            initialReminderAt: topic.bookmarkReminderAt,
            allowsDelete: topic.bookmarkId != nil
        )
    }
}

extension NotificationItemState {
    func fireShareURL(baseURL: String) -> URL? {
        guard let route = appRoute else {
            return nil
        }

        switch route {
        case .topic(let payload):
            var url = FireAppViewModel.cloudflareRecoveryTopicURL(
                baseURL: baseURL,
                topicId: payload.topicId,
                topicSlug: payload.preview?.slug ?? slug
            )
            if let postNumber = payload.postNumber, postNumber > 0 {
                url.appendPathComponent(String(postNumber))
            }
            return url
        case .profile(let username):
            return FireContextMenuURLBuilder.rootURL(baseURL: baseURL)
                .appendingPathComponent("u")
                .appendingPathComponent(username)
        case .badge(let id, let slug):
            var url = FireContextMenuURLBuilder.rootURL(baseURL: baseURL)
                .appendingPathComponent("badges")
                .appendingPathComponent(String(id))
            if let slug, !slug.isEmpty {
                url.appendPathComponent(slug)
            }
            return url
        case .profileTab, .notifications, .search:
            return nil
        }
    }
}

private enum FireContextMenuURLBuilder {
    static func rootURL(baseURL: String) -> URL {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawBaseURL = trimmedBaseURL.isEmpty ? "https://linux.do/" : trimmedBaseURL
        let normalizedBaseURL = rawBaseURL.hasSuffix("/") ? rawBaseURL : "\(rawBaseURL)/"
        return URL(string: normalizedBaseURL) ?? URL(string: "https://linux.do/")!
    }
}
