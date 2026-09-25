import Foundation
@testable import Fire

func firePresentationFixture(
    _ html: String,
    baseURLString: String = "https://linux.do"
) -> RenderDocumentHandle {
    presentCookedHtml(rawHtml: html, baseUrl: baseURLString)
        ?? presentCookedHtml(rawHtml: "<p></p>", baseUrl: baseURLString)!
}

func fireRenderContentFixture(
    _ html: String,
    baseURLString: String = "https://linux.do"
) -> FireTopicPostRenderContent {
    FireTopicPresentation.renderContent(
        from: firePresentationFixture(html, baseURLString: baseURLString),
        sourceToken: html
    )
}

func fireImageAttachmentFixture(
    _ html: String,
    baseURLString: String = "https://linux.do"
) -> [FireCookedImage] {
    FireTopicPresentation.imageAttachments(
        from: firePresentationFixture(html, baseURLString: baseURLString)
    )
}
