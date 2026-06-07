import Foundation
@testable import Fire

func fireRenderDocumentFixture(
    _ html: String,
    baseURLString: String = "https://linux.do"
) -> RenderDocumentState {
    renderCookedHtml(rawHtml: html, baseUrl: baseURLString)
}

func fireRenderContentFixture(
    _ html: String,
    baseURLString: String = "https://linux.do"
) -> FireTopicPostRenderContent {
    FireTopicPresentation.renderContent(
        from: fireRenderDocumentFixture(html, baseURLString: baseURLString),
        sourceToken: html
    )
}

func fireImageAttachmentFixture(
    _ html: String,
    baseURLString: String = "https://linux.do"
) -> [FireCookedImage] {
    FireTopicPresentation.imageAttachments(
        from: fireRenderDocumentFixture(html, baseURLString: baseURLString)
    )
}
