import XCTest
@testable import Fire

final class FireComposerStepGatingTests: XCTestCase {

    private func category(minimumRequiredTags: UInt32 = 0) -> TopicCategoryState {
        TopicCategoryState(
            id: 4, name: "资源分享", slug: "resource", parentCategoryId: nil,
            colorHex: nil, textColorHex: nil, topicTemplate: nil,
            minimumRequiredTags: minimumRequiredTags,
            requiredTagGroups: [],
            allowedTags: [], permission: nil, notificationLevel: nil
        )
    }

    func testMetaStepRequiresTitleCategoryAndMinimumTags() {
        XCTAssertFalse(FireComposerValidation.metaStepReady(
            trimmedTitle: "", categoryId: nil,
            selectedTagCount: 0, category: nil,
            minimumTitleLength: 1))
        XCTAssertFalse(FireComposerValidation.metaStepReady(
            trimmedTitle: "ok", categoryId: 4,
            selectedTagCount: 1,
            category: category(minimumRequiredTags: 2),
            minimumTitleLength: 1))
        XCTAssertTrue(FireComposerValidation.metaStepReady(
            trimmedTitle: "ok", categoryId: 4,
            selectedTagCount: 2,
            category: category(minimumRequiredTags: 2),
            minimumTitleLength: 1))
    }

    func testMetaStepAllowsWhenNoMinimumTagsRequired() {
        XCTAssertTrue(FireComposerValidation.metaStepReady(
            trimmedTitle: "ok", categoryId: 4,
            selectedTagCount: 0,
            category: category(minimumRequiredTags: 0),
            minimumTitleLength: 1))
    }
}
