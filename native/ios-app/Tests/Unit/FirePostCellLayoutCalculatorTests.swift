import UIKit
import XCTest
@testable import Fire

final class FirePostCellLayoutCalculatorTests: XCTestCase {
    func testCalculateAlignsContentColumnAndDividerWithReplyRowContract() {
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: 320,
            contentSizeCategory: UIContentSizeCategory.large.rawValue
        )
        let key = FirePostCellLayoutKey(
            postID: 42,
            depth: 1,
            showsThreadLine: true,
            showsDivider: true,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: "text",
            imageSignature: [],
            pollSignature: [],
            hasReactions: false,
            replyShortcutCount: nil,
            textExpansionState: .disabled,
            acceptedAnswer: false,
            trait: trait
        )

        let layout = FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: 40,
            imageSizes: [],
            trait: trait
        )

        XCTAssertEqual(layout.avatarFrame.origin.x, 16, accuracy: 0.01)
        XCTAssertEqual(layout.avatarFrame.origin.y, 0, accuracy: 0.01)
        XCTAssertEqual(layout.avatarFrame.width, 32, accuracy: 0.01)
        XCTAssertEqual(layout.metaFrame.minY, 8, accuracy: 0.01)
        XCTAssertEqual(layout.textFrame?.minY ?? -.greatestFiniteMagnitude, 36, accuracy: 0.01)
        XCTAssertEqual(layout.dividerFrame?.minX ?? -.greatestFiniteMagnitude, 16, accuracy: 0.01)
        XCTAssertEqual(layout.dividerFrame?.width ?? -.greatestFiniteMagnitude, 288, accuracy: 0.01)
        XCTAssertEqual(layout.totalHeight, 84.5, accuracy: 0.01)
        XCTAssertEqual(layout.threadLineFrame?.minY ?? -.greatestFiniteMagnitude, 38, accuracy: 0.01)
    }

    func testMeasureRichTextHeightGrowsAsAvailableWidthShrinks() {
        let attributedText = NSAttributedString(
            string: String(repeating: "Fire native reply row ", count: 12),
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
            ]
        )

        let wideHeight = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: attributedText,
            containerWidth: 240,
            contentSizeCategory: .large
        )
        let narrowHeight = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: attributedText,
            containerWidth: 120,
            contentSizeCategory: .large
        )

        XCTAssertNotNil(wideHeight)
        XCTAssertNotNil(narrowHeight)
        XCTAssertGreaterThan(narrowHeight ?? 0, wideHeight ?? 0)
    }

    func testAvailableContentWidthAccountsForIndentAvatarAndOuterPadding() {
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: 360,
            contentSizeCategory: UIContentSizeCategory.large.rawValue
        )
        let key = FirePostCellLayoutKey(
            postID: 7,
            depth: 3,
            showsThreadLine: false,
            showsDivider: false,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: "text",
            imageSignature: [],
            pollSignature: [],
            hasReactions: false,
            replyShortcutCount: nil,
            textExpansionState: .disabled,
            acceptedAnswer: false,
            trait: trait
        )

        let availableWidth = FirePostCellLayoutCalculator.availableContentWidth(
            for: key,
            trait: trait
        )

        XCTAssertEqual(availableWidth, 256, accuracy: 0.01)
    }

    func testCollapsedTextAddsInlineExpansionTokenAndCapsHeight() {
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: 320,
            contentSizeCategory: UIContentSizeCategory.large.rawValue
        )
        let key = FirePostCellLayoutKey(
            postID: 88,
            depth: 1,
            showsThreadLine: false,
            showsDivider: false,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: "text",
            imageSignature: [],
            pollSignature: [],
            hasReactions: true,
            replyShortcutCount: 3,
            textExpansionState: FirePostTextExpansionState(isCollapsible: true, isExpanded: false),
            acceptedAnswer: false,
            trait: trait
        )

        let collapsedHeight = FirePostCellLayoutCalculator.collapsedTextHeight(
            contentSizeCategory: .large
        )
        let layout = FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: collapsedHeight + 80,
            imageSizes: [],
            trait: trait
        )

        XCTAssertEqual(layout.textFrame?.height ?? 0, collapsedHeight, accuracy: 0.01)
        XCTAssertNotNil(layout.textExpansionFrame)
        XCTAssertNotNil(layout.replyShortcutFrame)
        XCTAssertNotNil(layout.reactionsFrame)
        XCTAssertEqual(layout.textExpansionFrame, layout.textFrame)
        XCTAssertEqual(
            layout.replyShortcutFrame?.minY ?? 0,
            (layout.textFrame?.maxY ?? 0) + FirePostCellLayoutCalculator.replyShortcutTopSpacing,
            accuracy: 0.01
        )
        XCTAssertEqual(layout.replyShortcutFrame?.minY ?? 0, layout.reactionsFrame?.minY ?? 1, accuracy: 0.01)
    }

    func testPollFramesSitBetweenMediaAndActionRow() {
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: 320,
            contentSizeCategory: UIContentSizeCategory.large.rawValue
        )
        let key = FirePostCellLayoutKey(
            postID: 99,
            depth: 1,
            showsThreadLine: false,
            showsDivider: false,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: "text",
            imageSignature: ["image"],
            pollSignature: ["poll"],
            hasReactions: true,
            replyShortcutCount: nil,
            textExpansionState: .disabled,
            acceptedAnswer: false,
            trait: trait
        )

        let layout = FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: 40,
            imageSizes: [CGSize(width: 180, height: 80)],
            pollHeights: [120],
            trait: trait
        )

        XCTAssertEqual(layout.pollFrames.count, 1)
        XCTAssertGreaterThan(layout.pollFrames[0].minY, layout.imageFrames[0].maxY)
        XCTAssertGreaterThan(layout.reactionsFrame?.minY ?? 0, layout.pollFrames[0].maxY)
    }

    func testPollPreferredHeightGrowsForLongOptionText() {
        let shortPoll = FirePostPollRenderModel(
            id: 1,
            name: "poll",
            title: "投票",
            kind: "regular",
            status: "open",
            voters: 2,
            userVotes: [],
            options: [
                FirePostPollOptionRenderModel(id: "a", title: "A", votes: 1, isSelected: false),
            ]
        )
        let longPoll = FirePostPollRenderModel(
            id: 1,
            name: "poll",
            title: "投票",
            kind: "regular",
            status: "open",
            voters: 2,
            userVotes: [],
            options: [
                FirePostPollOptionRenderModel(
                    id: "a",
                    title: String(repeating: "Fire native poll option ", count: 8),
                    votes: 1,
                    isSelected: false
                ),
            ]
        )

        let shortHeight = FirePostPollView.preferredHeight(
            for: shortPoll,
            availableWidth: 220,
            contentSizeCategory: .large
        )
        let longHeight = FirePostPollView.preferredHeight(
            for: longPoll,
            availableWidth: 220,
            contentSizeCategory: .large
        )

        XCTAssertGreaterThan(longHeight, shortHeight)
    }

    func testEstimatedCollapsedTextHeightStillTriggersExpansionControl() {
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: 320,
            contentSizeCategory: UIContentSizeCategory.large.rawValue
        )
        let key = FirePostCellLayoutKey(
            postID: 89,
            depth: 1,
            showsThreadLine: false,
            showsDivider: false,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: "text",
            imageSignature: [],
            pollSignature: [],
            hasReactions: false,
            replyShortcutCount: nil,
            textExpansionState: FirePostTextExpansionState(isCollapsible: true, isExpanded: false),
            acceptedAnswer: false,
            trait: trait
        )
        let availableWidth = FirePostCellLayoutCalculator.availableContentWidth(
            for: key,
            trait: trait
        )
        let estimatedHeight = FirePostCellLayoutCalculator.estimatedRichTextHeight(
            plainText: String(repeating: "Fire native reply row ", count: 20),
            hasAttributedText: true,
            containerWidth: availableWidth,
            contentSizeCategory: .large,
            textExpansionState: key.textExpansionState
        )
        let layout = FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: estimatedHeight,
            imageSizes: [],
            trait: trait
        )

        XCTAssertNotNil(layout.textExpansionFrame)
        XCTAssertEqual(
            layout.textFrame?.height ?? 0,
            FirePostCellLayoutCalculator.collapsedTextHeight(contentSizeCategory: .large),
            accuracy: 0.01
        )
    }

    func testCollapsedTextSuppressesMediaUntilExpanded() {
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: 320,
            contentSizeCategory: UIContentSizeCategory.large.rawValue
        )
        let key = FirePostCellLayoutKey(
            postID: 90,
            depth: 1,
            showsThreadLine: false,
            showsDivider: false,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: "text",
            imageSignature: ["image"],
            pollSignature: ["poll"],
            hasReactions: true,
            replyShortcutCount: nil,
            textExpansionState: FirePostTextExpansionState(isCollapsible: true, isExpanded: false),
            acceptedAnswer: false,
            trait: trait
        )
        let collapsedHeight = FirePostCellLayoutCalculator.collapsedTextHeight(contentSizeCategory: .large)

        let layout = FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: collapsedHeight + 20,
            imageSizes: [CGSize(width: 180, height: 120)],
            pollHeights: [120],
            trait: trait
        )

        XCTAssertNotNil(layout.textExpansionFrame)
        XCTAssertTrue(layout.imageFrames.isEmpty)
        XCTAssertTrue(layout.pollFrames.isEmpty)
        XCTAssertEqual(
            layout.reactionsFrame?.minY ?? 0,
            (layout.textFrame?.maxY ?? 0) + FirePostCellLayoutCalculator.replyShortcutTopSpacing,
            accuracy: 0.01
        )
    }

    func testCommentImageRenderSizeIsScaledDown() throws {
        let image = FireCookedImage(
            url: try XCTUnwrap(URL(string: "https://linux.do/uploads/default/original/1x/sample.png")),
            altText: nil,
            width: 776,
            height: 1206
        )

        let rootSize = FirePostCellLayoutCalculator.imageRenderSize(
            for: image,
            availableWidth: 320,
            depth: 0
        )
        let commentSize = FirePostCellLayoutCalculator.imageRenderSize(
            for: image,
            availableWidth: 320,
            depth: 1
        )

        XCTAssertEqual(rootSize.width, 320, accuracy: 0.01)
        XCTAssertLessThan(commentSize.width, rootSize.width)
        XCTAssertLessThanOrEqual(commentSize.height, FirePostCellLayoutCalculator.commentImageMaxHeight)
    }
}
