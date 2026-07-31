import AsyncDisplayKit
import UIKit
import XCTest
@testable import Fire

final class FirePostCellLayoutCalculatorTests: XCTestCase {
    func testCalculateKeepsReplyBodyInAvatarContentColumn() {
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
            boostSignature: [],
            hasReactions: false,
            textExpansionState: .disabled,
            acceptedAnswer: false,
            hasAuthorMetadata: false,
            trait: trait
        )

        let layout = FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: 40,
            imageSizes: [],
            trait: trait
        )
        let traitCollection = UITraitCollection(preferredContentSizeCategory: .large)
        let expectedMetaHeight = ceil(max(
            UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection).lineHeight,
            UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traitCollection).lineHeight,
            FirePostCellLayoutCalculator.menuButtonSize
        ))
        let expectedSecondaryLineHeight = ceil(UIFont.preferredFont(
            forTextStyle: .caption2,
            compatibleWith: traitCollection
        ).lineHeight)
        let expectedTextMinY = FirePostCellLayoutCalculator.contentVerticalPadding
            + expectedMetaHeight
            + FirePostCellLayoutCalculator.metaLineSpacing
            + expectedSecondaryLineHeight
            + FirePostCellLayoutCalculator.metaLineSpacing
        let expectedTotalHeight = expectedTextMinY
            + 40
            + FirePostCellLayoutCalculator.contentVerticalPadding
            + FirePostCellLayoutCalculator.dividerHeight

        XCTAssertEqual(layout.avatarFrame.origin.x, 16, accuracy: 0.01)
        XCTAssertEqual(layout.avatarFrame.origin.y, 0, accuracy: 0.01)
        XCTAssertEqual(layout.avatarFrame.width, 32, accuracy: 0.01)
        XCTAssertEqual(layout.metaFrame.minX, 58, accuracy: 0.01)
        XCTAssertEqual(layout.metaFrame.minY, 8, accuracy: 0.01)
        XCTAssertEqual(layout.textFrame?.minX ?? -.greatestFiniteMagnitude, 58, accuracy: 0.01)
        XCTAssertEqual(layout.textFrame?.width ?? -.greatestFiniteMagnitude, 246, accuracy: 0.01)
        XCTAssertEqual(layout.textFrame?.minY ?? -.greatestFiniteMagnitude, expectedTextMinY, accuracy: 0.01)
        XCTAssertEqual(layout.dividerFrame?.minX ?? -.greatestFiniteMagnitude, 16, accuracy: 0.01)
        XCTAssertEqual(layout.dividerFrame?.width ?? -.greatestFiniteMagnitude, 288, accuracy: 0.01)
        XCTAssertEqual(layout.totalHeight, expectedTotalHeight, accuracy: 0.01)
        XCTAssertEqual(layout.threadLineFrame?.minY ?? -.greatestFiniteMagnitude, 38, accuracy: 0.01)
    }

    func testCalculateLetsOriginalPostBodyUseFullRowWidthBelowHeader() {
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: 320,
            contentSizeCategory: UIContentSizeCategory.large.rawValue
        )
        let key = FirePostCellLayoutKey(
            postID: 43,
            depth: 0,
            showsThreadLine: false,
            showsDivider: false,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: "original",
            imageSignature: ["image"],
            pollSignature: [],
            boostSignature: [],
            hasReactions: false,
            textExpansionState: .disabled,
            acceptedAnswer: false,
            hasAuthorMetadata: false,
            trait: trait
        )

        let layout = FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: 40,
            imageSizes: [CGSize(width: 288, height: 162)],
            trait: trait
        )

        XCTAssertEqual(layout.avatarFrame.minX, 16, accuracy: 0.01)
        XCTAssertEqual(layout.metaFrame.minX, 58, accuracy: 0.01)
        XCTAssertEqual(layout.textFrame?.minX ?? -.greatestFiniteMagnitude, 16, accuracy: 0.01)
        XCTAssertEqual(layout.textFrame?.width ?? -.greatestFiniteMagnitude, 288, accuracy: 0.01)
        XCTAssertEqual(layout.imageFrames.first?.minX ?? -.greatestFiniteMagnitude, 16, accuracy: 0.01)
        XCTAssertEqual(layout.imageFrames.first?.width ?? -.greatestFiniteMagnitude, 288, accuracy: 0.01)
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

    func testAvailableContentWidthAccountsForIndentAvatarAndOuterPaddingInReplies() {
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
            boostSignature: [],
            hasReactions: false,
            textExpansionState: .disabled,
            acceptedAnswer: false,
            hasAuthorMetadata: false,
            trait: trait
        )

        let availableWidth = FirePostCellLayoutCalculator.availableContentWidth(
            for: key,
            trait: trait
        )

        XCTAssertEqual(availableWidth, 256, accuracy: 0.01)
    }

    func testAuthorMetadataDoesNotChangePrecomputedHeaderHeight() {
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: 320,
            contentSizeCategory: UIContentSizeCategory.large.rawValue
        )
        let baselineKey = FirePostCellLayoutKey(
            postID: 84,
            depth: 1,
            showsThreadLine: false,
            showsDivider: false,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: "text",
            imageSignature: [],
            pollSignature: [],
            boostSignature: [],
            hasReactions: false,
            textExpansionState: .disabled,
            acceptedAnswer: false,
            hasAuthorMetadata: false,
            trait: trait
        )
        let metadataKey = FirePostCellLayoutKey(
            postID: 84,
            depth: 1,
            showsThreadLine: false,
            showsDivider: false,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: "text",
            imageSignature: [],
            pollSignature: [],
            boostSignature: [],
            hasReactions: false,
            textExpansionState: .disabled,
            acceptedAnswer: false,
            hasAuthorMetadata: true,
            trait: trait
        )

        let baseline = FirePostCellLayoutCalculator.calculate(
            key: baselineKey,
            textHeight: 40,
            imageSizes: [],
            trait: trait
        )
        let withMetadata = FirePostCellLayoutCalculator.calculate(
            key: metadataKey,
            textHeight: 40,
            imageSizes: [],
            trait: trait
        )

        XCTAssertEqual(withMetadata.totalHeight, baseline.totalHeight, accuracy: 0.01)
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
            boostSignature: [],
            hasReactions: true,
            textExpansionState: FirePostTextExpansionState(isCollapsible: true, isExpanded: false),
            acceptedAnswer: false,
            hasAuthorMetadata: false,
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
        XCTAssertNotNil(layout.reactionsFrame)
        XCTAssertEqual(layout.textExpansionFrame, layout.textFrame)
        XCTAssertEqual(
            layout.reactionsFrame?.minY ?? 0,
            (layout.textFrame?.maxY ?? 0) + FirePostCellLayoutCalculator.actionRowTopSpacing,
            accuracy: 0.01
        )
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
            boostSignature: [],
            hasReactions: true,
            textExpansionState: .disabled,
            acceptedAnswer: false,
            hasAuthorMetadata: false,
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

    func testBoostFramesSitBetweenBodyAndActionRow() {
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: 320,
            contentSizeCategory: UIContentSizeCategory.large.rawValue
        )
        let key = FirePostCellLayoutKey(
            postID: 100,
            depth: 1,
            showsThreadLine: false,
            showsDivider: false,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: "text",
            imageSignature: [],
            pollSignature: [],
            boostSignature: ["boost-a", "boost-b"],
            hasReactions: true,
            textExpansionState: .disabled,
            acceptedAnswer: false,
            hasAuthorMetadata: false,
            trait: trait
        )

        let layout = FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: 40,
            imageSizes: [],
            boostLines: ["@carol: Hello :wave:", "@dave: Thanks for the detail"],
            trait: trait
        )

        XCTAssertEqual(layout.boostFrames.count, 1)
        XCTAssertGreaterThan(layout.boostFrames[0].minY, layout.textFrame?.maxY ?? 0)
        XCTAssertEqual(
            layout.boostFrames[0].height,
            FirePostCellLayoutCalculator.fixedBoostManualHeight,
            accuracy: 0.01
        )
        XCTAssertEqual(
            layout.reactionsFrame?.minY ?? 0,
            layout.boostFrames[0].maxY + FirePostCellLayoutCalculator.actionRowTopSpacing,
            accuracy: 0.01
        )
    }

    func testFixedBoostManualScrollerKeepsManyBoostsToTwoRows() {
        let trait = FirePostLayoutTraitSignature(contentWidthPixels: 360, contentSizeCategory: UIContentSizeCategory.large.rawValue)
        let key = FirePostCellLayoutKey(
            postID: 999,
            depth: 1,
            showsThreadLine: false,
            showsDivider: true,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: "many-boosts",
            imageSignature: [],
            pollSignature: [],
            boostSignature: (0..<8).map { "boost-\($0)" },
            hasReactions: true,
            textExpansionState: .disabled,
            acceptedAnswer: false,
            hasAuthorMetadata: false,
            trait: trait
        )

        let layout = FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: 40,
            imageSizes: [],
            boostLines: (0..<8).map { "@user\($0): boost text \($0)" },
            trait: trait
        )

        XCTAssertEqual(layout.boostFrames.count, 1)
        XCTAssertEqual(layout.boostFrames[0].height, FirePostCellLayoutCalculator.fixedBoostManualHeight, accuracy: 0.01)
    }

    func testFixedBoostManualScrollerUsesSingleRowHeightWhenBoostsFitOneRow() {
        let trait = FirePostLayoutTraitSignature(contentWidthPixels: 360, contentSizeCategory: UIContentSizeCategory.large.rawValue)
        let key = FirePostCellLayoutKey(
            postID: 998,
            depth: 1,
            showsThreadLine: false,
            showsDivider: true,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: "single-row-boosts",
            imageSignature: [],
            pollSignature: [],
            boostSignature: ["boost-a"],
            hasReactions: true,
            textExpansionState: .disabled,
            acceptedAnswer: false,
            hasAuthorMetadata: false,
            trait: trait
        )

        let layout = FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: 40,
            imageSizes: [],
            boostLines: ["Short boost"],
            trait: trait
        )

        XCTAssertEqual(layout.boostFrames.count, 1)
        XCTAssertEqual(
            layout.boostFrames[0].height,
            FirePostCellLayoutCalculator.fixedBoostManualHeight(forUsedRowCount: 1),
            accuracy: 0.01
        )
        XCTAssertEqual(
            layout.reactionsFrame?.minY ?? 0,
            layout.boostFrames[0].maxY + FirePostCellLayoutCalculator.actionRowTopSpacing,
            accuracy: 0.01
        )
    }

    func testManualBoostLayoutFillsFirstRowThenSecondBeforeHorizontalOverflow() {
        let layout = FirePostBoostManualLayout.placements(
            forChipWidths: [60, 70, 80, 90],
            pageWidth: 200,
            laneCount: 2
        )

        XCTAssertEqual(layout.placements.map(\.rowIndex), [0, 0, 1, 1])
        XCTAssertEqual(layout.placements.count, 4)
        XCTAssertEqual(layout.placements[0].x, 0, accuracy: 0.01)
        XCTAssertEqual(layout.placements[1].x, 68, accuracy: 0.01)
        XCTAssertEqual(layout.placements[2].x, 0, accuracy: 0.01)
        XCTAssertEqual(layout.placements[3].x, 88, accuracy: 0.01)
        XCTAssertEqual(layout.contentWidth, 200, accuracy: 0.01)
        XCTAssertEqual(layout.usedRowCount, 2)
    }

    func testManualBoostLayoutDoesNotBackfillFirstRowAfterMovingToSecondRow() {
        let layout = FirePostBoostManualLayout.placements(
            forChipWidths: [160, 50, 20],
            pageWidth: 200,
            laneCount: 2
        )

        XCTAssertEqual(layout.placements.map(\.rowIndex), [0, 1, 1])
        XCTAssertEqual(layout.placements[0].x, 0, accuracy: 0.01)
        XCTAssertEqual(layout.placements[1].x, 0, accuracy: 0.01)
        XCTAssertEqual(layout.placements[2].x, 58, accuracy: 0.01)
        XCTAssertEqual(layout.contentWidth, 200, accuracy: 0.01)
        XCTAssertEqual(layout.usedRowCount, 2)
    }

    func testManualBoostLayoutAddsOverflowAsNextTwoRowPage() {
        let layout = FirePostBoostManualLayout.placements(
            forChipWidths: [120, 70, 120, 70, 100],
            pageWidth: 200,
            laneCount: 2
        )

        XCTAssertEqual(layout.placements.map(\.rowIndex), [0, 0, 1, 1, 0])
        XCTAssertEqual(layout.placements[4].x, 208, accuracy: 0.01)
        XCTAssertGreaterThan(layout.contentWidth, 200)
        XCTAssertEqual(layout.usedRowCount, 2)
    }

    func testManualBoostLayoutReportsSingleUsedRowWhenEverythingFitsFirstRow() {
        let layout = FirePostBoostManualLayout.placements(
            forChipWidths: [40, 50],
            pageWidth: 200,
            laneCount: 2
        )

        XCTAssertEqual(layout.placements.map(\.rowIndex), [0, 0])
        XCTAssertEqual(layout.usedRowCount, 1)
    }

    func testBoostDisplayUsesBarrageOnlyForExpandedOriginalBodyText() {
        let boost = makeBoost(username: "carol", displayText: "Hello")
        let expanded = FirePostTextExpansionState.disabled
        let collapsed = FirePostTextExpansionState(isCollapsible: true, isExpanded: false)

        XCTAssertTrue(FirePostBoostDisplay.usesBodyBarrage(
            depth: 0,
            textExpansionState: expanded,
            hasBodyTextTarget: true
        ))
        XCTAssertFalse(FirePostBoostDisplay.usesBodyBarrage(
            depth: 1,
            textExpansionState: expanded,
            hasBodyTextTarget: true
        ))
        XCTAssertFalse(FirePostBoostDisplay.usesBodyBarrage(
            depth: 0,
            textExpansionState: collapsed,
            hasBodyTextTarget: true
        ))
        XCTAssertFalse(FirePostBoostDisplay.usesBodyBarrage(
            depth: 0,
            textExpansionState: expanded,
            hasBodyTextTarget: false
        ))
        XCTAssertTrue(FirePostBoostDisplay.fixedDisplayLines(
            for: [boost],
            depth: 0,
            textExpansionState: expanded,
            hasBodyTextTarget: true
        ).isEmpty)
        XCTAssertEqual(
            FirePostBoostDisplay.fixedDisplayLines(
                for: [boost],
                depth: 1,
                textExpansionState: expanded,
                hasBodyTextTarget: true
            ),
            ["Hello"]
        )
        XCTAssertEqual(
            FirePostBoostDisplay.fixedDisplayLines(
                for: [boost],
                depth: 0,
                textExpansionState: expanded,
                hasBodyTextTarget: false
            ),
            ["Hello"]
        )
    }

    func testBoostDisplayLineUsesOnlyBoostBody() {
        let boost = makeBoost(username: "carol", displayText: "  @carol: Thanks for the detail  ")

        XCTAssertEqual(FirePostBoostDisplay.displayLine(for: boost), "Thanks for the detail")
    }

    func testBoostDisplayContentStripsRichTextAttributionPrefix() {
        let boost = makeBoost(username: "carol", displayText: "@carol: Thanks for the detail")

        XCTAssertEqual(FirePostBoostDisplay.displayContent(for: boost).string, "Thanks for the detail")
    }

    func testBodyBarrageBatchSignatureUsesVisibleNormalizedBoostBody() {
        XCTAssertEqual(FirePostBoostDisplay.bodyBarrageVisibleLineLimit, 5)
        let visibleBoosts = (0..<FirePostBoostDisplay.bodyBarrageVisibleLineLimit).map { index in
            makeBoost(id: UInt64(index + 1), username: "user\(index)", displayText: "  Body \(index)  ")
        }
        let normalizedVisibleBoosts = (0..<FirePostBoostDisplay.bodyBarrageVisibleLineLimit).map { index in
            makeBoost(id: UInt64(index + 1), username: "user\(index)", displayText: "\nBody \(index)\t")
        }
        let signature = FirePostBoostDisplay.bodyBarrageBatchSignature(
            postID: 42,
            boosts: visibleBoosts
        )

        XCTAssertEqual(
            FirePostBoostDisplay.bodyBarrageLines(for: visibleBoosts),
            (0..<FirePostBoostDisplay.bodyBarrageVisibleLineLimit).map { "Body \($0)" }
        )
        XCTAssertEqual(
            signature,
            FirePostBoostDisplay.bodyBarrageBatchSignature(
                postID: 42,
                boosts: normalizedVisibleBoosts
            )
        )
        XCTAssertEqual(
            signature,
            FirePostBoostDisplay.bodyBarrageBatchSignature(
                postID: 42,
                boosts: visibleBoosts + [makeBoost(id: 99, username: "late", displayText: "Hidden extra")]
            )
        )
        XCTAssertNotEqual(
            signature,
            FirePostBoostDisplay.bodyBarrageBatchSignature(
                postID: 42,
                boosts: [makeBoost(id: 99, username: "late", displayText: "New visible")]
                    + visibleBoosts.dropLast()
            )
        )
        XCTAssertTrue(FirePostBoostDisplay.bodyBarrageLines(
            for: [makeBoost(id: 100, username: "blank", displayText: "  \n  ")]
        ).isEmpty)
        XCTAssertEqual(
            FirePostBoostDisplay.bodyBarrageBatchSignature(
                postID: 42,
                boosts: [makeBoost(id: 100, username: "blank", displayText: "  \n  ")]
            ),
            ""
        )
    }

    func testFixedBoostManualScrollerHeightIsCompact() {
        XCTAssertEqual(FirePostCellLayoutCalculator.fixedBoostManualRows, 2)
        XCTAssertEqual(
            FirePostCellLayoutCalculator.fixedBoostManualHeight(forUsedRowCount: 1),
            FirePostCellLayoutCalculator.fixedBoostManualRowHeight,
            accuracy: 0.01
        )
        XCTAssertEqual(FirePostCellLayoutCalculator.fixedBoostManualHeight, 54, accuracy: 0.01)
    }

    func testBoostBarrageTextTargetRequiresRenderedText() throws {
        let textContent = renderContent(
            plainText: "Hello",
            attributedText: NSAttributedString(string: "Hello")
        )
        let segmentedTextContent = renderContent(
            plainText: "Hello",
            attributedText: nil,
            segments: [.text(NSAttributedString(string: "Hello"))]
        )
        let image = FireCookedImage(
            url: try XCTUnwrap(URL(string: "https://linux.do/uploads/default/original/1x/example.png")),
            altText: nil,
            width: 120,
            height: 80
        )
        let imageOnlyContent = renderContent(
            plainText: "",
            attributedText: nil,
            imageAttachments: [image],
            segments: [.image(image)]
        )
        let emptyContent = renderContent(
            plainText: "",
            attributedText: nil
        )

        XCTAssertTrue(textContent.hasBoostBarrageTextTarget)
        XCTAssertTrue(segmentedTextContent.hasBoostBarrageTextTarget)
        XCTAssertFalse(imageOnlyContent.hasBoostBarrageTextTarget)
        XCTAssertFalse(emptyContent.hasBoostBarrageTextTarget)
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
            boostSignature: [],
            hasReactions: false,
            textExpansionState: FirePostTextExpansionState(isCollapsible: true, isExpanded: false),
            acceptedAnswer: false,
            hasAuthorMetadata: false,
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
            boostSignature: ["boost"],
            hasReactions: true,
            textExpansionState: FirePostTextExpansionState(isCollapsible: true, isExpanded: false),
            acceptedAnswer: false,
            hasAuthorMetadata: false,
            trait: trait
        )
        let collapsedHeight = FirePostCellLayoutCalculator.collapsedTextHeight(contentSizeCategory: .large)

        let layout = FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: collapsedHeight + 20,
            imageSizes: [CGSize(width: 180, height: 120)],
            pollHeights: [120],
            boostLines: ["@carol: This should be hidden while text is collapsed"],
            trait: trait
        )

        XCTAssertNotNil(layout.textExpansionFrame)
        XCTAssertTrue(layout.imageFrames.isEmpty)
        XCTAssertTrue(layout.pollFrames.isEmpty)
        XCTAssertTrue(layout.boostFrames.isEmpty)
        XCTAssertEqual(
            layout.reactionsFrame?.minY ?? 0,
            (layout.textFrame?.maxY ?? 0) + FirePostCellLayoutCalculator.actionRowTopSpacing,
            accuracy: 0.01
        )
    }

    func testTextureCellSuppressesAttachmentsOnlyWhenCollapsedTextOverflows() {
        let state = FirePostTextExpansionState(isCollapsible: true, isExpanded: false)
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let shortText = NSAttributedString(
            string: "Short reply",
            attributes: [.font: font]
        )
        let overflowingText = NSAttributedString(
            string: Array(repeating: "Overflowing reply line", count: 8).joined(separator: "\n"),
            attributes: [.font: font]
        )
        let avatarSize = FirePostCellLayoutCalculator.avatarSize(for: 1)
        let avatarSpacing = FirePostCellLayoutCalculator.avatarSpacing(for: 1)

        XCTAssertFalse(FirePostCellNode.shouldSuppressAttachmentsForCollapsedText(
            attributedText: shortText,
            textExpansionState: state,
            totalWidth: 320,
            depth: 1,
            avatarSize: avatarSize,
            avatarSpacing: avatarSpacing,
            contentSizeCategory: .large
        ))
        XCTAssertTrue(FirePostCellNode.shouldSuppressAttachmentsForCollapsedText(
            attributedText: overflowingText,
            textExpansionState: state,
            totalWidth: 320,
            depth: 1,
            avatarSize: avatarSize,
            avatarSpacing: avatarSpacing,
            contentSizeCategory: .large
        ))
    }

    func testTexturePostCellConstrainsLongRichTextToCollectionWidth() {
        let width: CGFloat = 320
        let longText = String(repeating: "LongMarkdownLineWithoutSpaces", count: 10)
        let renderContent = fireRenderContentFixture("<p>\(longText)</p>")
        let node = FirePostCellNode()
        node.configure(
            payload: FirePostCellRenderPayload(
                post: makePost(id: 321, postNumber: 1, username: "tester"),
                renderContent: renderContent,
                baseURLString: "https://linux.do",
                canWriteInteractions: true,
                isMutating: false,
                replyContext: nil,
                replyTargetPostNumber: nil,
                textExpansionState: .disabled,
                isSearchHighlighted: false,
                showsDivider: false,
                layoutWidth: width
            ),
            callbacks: noopCallbacks(),
            depth: 1,
            showsThreadLine: false,
            showsDivider: false
        )

        let layout = node.layoutThatFits(ASSizeRange(
            min: CGSize(width: width, height: 0),
            max: CGSize(width: width, height: .greatestFiniteMagnitude)
        ))

        XCTAssertLessThanOrEqual(layout.size.width, width + 0.5)
        XCTAssertGreaterThan(layout.size.height, 90)
    }

    func testTexturePostCellActionRowMatchesLayoutCalculatorHeight() {
        let width: CGFloat = 320
        let renderContent = fireRenderContentFixture("<p>Fire native detail row with reactions.</p>")
        let reactions = [
            TopicReactionState(id: "heart", kind: nil, count: 12, canUndo: true),
            TopicReactionState(id: "clap", kind: nil, count: 4, canUndo: true),
        ]
        let post = makePost(
            id: 654,
            postNumber: 2,
            username: "tester",
            reactions: reactions
        )
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: Int(width.rounded()),
            contentSizeCategory: UIContentSizeCategory.large.rawValue
        )
        let key = FirePostCellLayoutKey(
            postID: post.id,
            depth: 1,
            showsThreadLine: false,
            showsDivider: false,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: renderContent.signature.token,
            imageSignature: [],
            pollSignature: [],
            boostSignature: [],
            hasReactions: true,
            showsInlineActions: true,
            primaryActionSlotCount: 4,
            textExpansionState: .disabled,
            acceptedAnswer: false,
            hasAuthorMetadata: false,
            trait: trait
        )
        let textHeight = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: renderContent.attributedText,
            containerWidth: FirePostCellLayoutCalculator.availableContentWidth(for: key, trait: trait),
            contentSizeCategory: .large
        )
        let calculatedLayout = FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: textHeight,
            imageSizes: [],
            trait: trait
        )
        let node = FirePostCellNode()
        node.configure(
            payload: FirePostCellRenderPayload(
                post: post,
                renderContent: renderContent,
                baseURLString: "https://linux.do",
                canWriteInteractions: true,
                isMutating: false,
                replyContext: nil,
                replyTargetPostNumber: nil,
                textExpansionState: .disabled,
                isSearchHighlighted: false,
                showsDivider: false,
                layoutWidth: width,
                layout: calculatedLayout,
                layoutKey: key
            ),
            callbacks: noopCallbacks(),
            depth: 1,
            showsThreadLine: false,
            showsDivider: false
        )

        let measuredLayout = node.layoutThatFits(ASSizeRange(
            min: CGSize(width: width, height: 0),
            max: CGSize(width: width, height: .greatestFiniteMagnitude)
        ))

        XCTAssertEqual(measuredLayout.size.height, calculatedLayout.totalHeight, accuracy: 8.0)
    }

    func testTexturePostCellKeepsManualBoostFooterCompact() {
        let width: CGFloat = 320
        let boosts = [
            makeBoost(id: 1, username: "carol", displayText: "@carol: First boost"),
            makeBoost(id: 2, username: "dave", displayText: "@dave: Second boost"),
        ]
        let reactions = [
            TopicReactionState(id: "heart", kind: nil, count: 2, canUndo: true),
        ]
        let renderContent = fireRenderContentFixture("<p>Reply body</p>")
        let post = makePost(
            id: 701,
            postNumber: 8,
            username: "alice",
            reactions: reactions,
            boosts: boosts
        )
        let trait = FirePostLayoutTraitSignature(
            contentWidthPixels: Int(width.rounded()),
            contentSizeCategory: UIContentSizeCategory.large.rawValue
        )
        let key = FirePostCellLayoutKey(
            postID: post.id,
            depth: 1,
            showsThreadLine: false,
            showsDivider: false,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: renderContent.signature.token,
            imageSignature: [],
            pollSignature: [],
            boostSignature: boosts.map(FirePostBoostDisplay.contentSignature(for:)),
            hasReactions: true,
            // Match reply-row chrome: overflow actions are visible when writable.
            showsInlineActions: true,
            textExpansionState: .disabled,
            acceptedAnswer: false,
            hasAuthorMetadata: false,
            trait: trait
        )
        let textHeight = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: renderContent.attributedText,
            containerWidth: FirePostCellLayoutCalculator.availableContentWidth(for: key, trait: trait),
            contentSizeCategory: .large
        )
        let calculatedLayout = FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: textHeight,
            imageSizes: [],
            boostLines: FirePostBoostDisplay.fixedDisplayLines(
                for: boosts,
                depth: 1,
                textExpansionState: .disabled,
                hasBodyTextTarget: renderContent.hasBoostBarrageTextTarget
            ),
            trait: trait
        )
        let node = FirePostCellNode()
        node.configure(
            payload: FirePostCellRenderPayload(
                post: post,
                renderContent: renderContent,
                baseURLString: "https://linux.do",
                canWriteInteractions: true,
                isMutating: false,
                replyContext: nil,
                replyTargetPostNumber: nil,
                textExpansionState: .disabled,
                isSearchHighlighted: false,
                showsDivider: false,
                layoutWidth: width,
                layout: calculatedLayout,
                layoutKey: key
            ),
            callbacks: noopCallbacks(),
            depth: 1,
            showsThreadLine: false,
            showsDivider: false
        )

        let measuredLayout = node.layoutThatFits(ASSizeRange(
            min: CGSize(width: width, height: 0),
            max: CGSize(width: width, height: .greatestFiniteMagnitude)
        ))

        XCTAssertEqual(calculatedLayout.boostFrames.count, 1)
        // Action icons sit under boosts; reaction chips now occupy a dedicated row below.
        let expectedReactionMinY = calculatedLayout.boostFrames[0].maxY
            + FirePostCellLayoutCalculator.actionRowTopSpacing
            + FirePostCellLayoutCalculator.actionRowHeight
            + FirePostCellLayoutCalculator.reactionTopSpacing
        XCTAssertEqual(
            calculatedLayout.reactionsFrame?.minY ?? 0,
            expectedReactionMinY,
            accuracy: 0.01
        )
        // Texture may land a few points tighter than the frame calculator once
        // avatar-led boost chips + overflow chrome compose; keep the footer compact
        // and the two paths within one metric row of each other.
        XCTAssertLessThanOrEqual(measuredLayout.size.height, 190)
        XCTAssertEqual(
            measuredLayout.size.height,
            calculatedLayout.totalHeight,
            accuracy: 12.0
        )
    }

    func testTexturePostCellKeepsCommentImageVisibleWhenCollapsedTextDoesNotOverflow() throws {
        let width: CGFloat = 320
        let image = FireCookedImage(
            url: try XCTUnwrap(URL(string: "https://linux.do/uploads/default/original/1x/comment.png")),
            altText: nil,
            width: 640,
            height: 360
        )
        let contentWithImage = renderContent(
            plainText: "Short reply",
            attributedText: NSAttributedString(
                string: "Short reply",
                attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline)]
            ),
            imageAttachments: [image],
            segments: [
                .text(NSAttributedString(string: "Short reply")),
                .image(image),
            ]
        )
        let collapsed = FirePostTextExpansionState(isCollapsible: true, isExpanded: false)
        let node = FirePostCellNode()
        node.configure(
            payload: FirePostCellRenderPayload(
                post: makePost(id: 765, postNumber: 3, username: "tester"),
                renderContent: contentWithImage,
                baseURLString: "https://linux.do",
                canWriteInteractions: true,
                isMutating: false,
                replyContext: nil,
                replyTargetPostNumber: nil,
                textExpansionState: collapsed,
                isSearchHighlighted: false,
                showsDivider: false,
                layoutWidth: width
            ),
            callbacks: noopCallbacks(),
            depth: 1,
            showsThreadLine: false,
            showsDivider: false
        )

        let measuredLayout = node.layoutThatFits(ASSizeRange(
            min: CGSize(width: width, height: 0),
            max: CGSize(width: width, height: .greatestFiniteMagnitude)
        ))
        let textOnlyNode = FirePostCellNode()
        textOnlyNode.configure(
            payload: FirePostCellRenderPayload(
                post: makePost(id: 766, postNumber: 4, username: "tester"),
                renderContent: renderContent(
                    plainText: "Short reply",
                    attributedText: NSAttributedString(string: "Short reply"),
                    imageAttachments: [],
                    segments: [.text(NSAttributedString(string: "Short reply"))]
                ),
                baseURLString: "https://linux.do",
                canWriteInteractions: true,
                isMutating: false,
                replyContext: nil,
                replyTargetPostNumber: nil,
                textExpansionState: collapsed,
                isSearchHighlighted: false,
                showsDivider: false,
                layoutWidth: width
            ),
            callbacks: noopCallbacks(),
            depth: 1,
            showsThreadLine: false,
            showsDivider: false
        )
        let textOnlyLayout = textOnlyNode.layoutThatFits(ASSizeRange(
            min: CGSize(width: width, height: 0),
            max: CGSize(width: width, height: .greatestFiniteMagnitude)
        ))

        XCTAssertGreaterThan(measuredLayout.size.height, textOnlyLayout.size.height + 80)
    }

    func testOriginalImagesUsePostWidthAndCommentImagesStayCompact() throws {
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
        XCTAssertEqual(rootSize.height, CGFloat(320.0 / (776.0 / 1206.0)), accuracy: 0.01)
        XCTAssertLessThan(commentSize.width, rootSize.width)
        XCTAssertLessThanOrEqual(commentSize.height, FirePostCellLayoutCalculator.commentImageMaxHeight)
    }

    func testAuthorMetadataKeepsStaffBadgesPrimaryAndHumanizesTrustTitle() {
        let post = makePost(
            id: 877,
            postNumber: 5,
            username: "alice",
            authorMetadata: TopicPostAuthorMetadataState(
                userId: 7,
                userTitle: "Trust Level 2",
                primaryGroupName: "core-team",
                flairUrl: nil,
                flairName: "Maintainers",
                flairBgColor: nil,
                flairColor: nil,
                flairGroupId: nil,
                moderator: true,
                admin: false,
                groupModerator: false,
                userStatusEmoji: nil,
                userStatusDescription: "Shipping Fire"
            )
        )

        // Fluxdo-style: staff roles only on the primary line; group/flair are not text chips.
        XCTAssertEqual(
            FirePostAuthorMetadataDisplay.primaryBadgeParts(for: post),
            ["版主"]
        )
        XCTAssertEqual(
            FirePostAuthorMetadataDisplay.secondaryLineParts(for: post),
            ["@alice", "L2 成员", "Shipping Fire"]
        )
        XCTAssertEqual(
            FirePostAuthorMetadataDisplay.humanizedUserTitle("trust_lv_3"),
            "L3 活跃用户"
        )
        XCTAssertEqual(
            FirePostAuthorMetadataDisplay.parsedTrustLevel(from: "trust_lv_3"),
            3
        )
    }

    func testReactionDisplayPolicyCapsVisibleReactionsAndUsesDedicatedRow() {
        let reactions = [
            TopicReactionState(id: "heart", kind: nil, count: 12, canUndo: true),
            TopicReactionState(id: "clap", kind: nil, count: 4, canUndo: true),
            TopicReactionState(id: "laughing", kind: nil, count: 3, canUndo: true),
            TopicReactionState(id: "tada", kind: nil, count: 2, canUndo: true),
            TopicReactionState(id: "cry", kind: nil, count: 2, canUndo: true),
            TopicReactionState(id: "confused", kind: nil, count: 1, canUndo: true),
            TopicReactionState(id: "open_mouth", kind: nil, count: 1, canUndo: true),
        ]

        let originalVisible = FirePostReactionDisplayPolicy.visibleReactions(from: reactions, depth: 0)
        let replyVisible = FirePostReactionDisplayPolicy.visibleReactions(from: reactions, depth: 1)

        // Count desc, then id asc for ties (cry before tada).
        XCTAssertEqual(originalVisible.map(\.id), ["heart", "clap", "laughing", "cry", "tada", "confused"])
        XCTAssertEqual(replyVisible.map(\.id), originalVisible.map(\.id))
        XCTAssertEqual(FirePostReactionDisplayPolicy.hiddenReactionCount(from: reactions, depth: 0), 1)
        XCTAssertFalse(FirePostReactionDisplayPolicy.allowsWrapping(depth: 0))
        XCTAssertFalse(FirePostReactionDisplayPolicy.allowsWrapping(depth: 1))
    }

    private func makePost(
        id: UInt64,
        postNumber: UInt32,
        username: String,
        authorMetadata: TopicPostAuthorMetadataState = fireEmptyPostAuthorMetadataState(),
        reactions: [TopicReactionState] = [],
        boosts: [TopicPostBoostState] = []
    ) -> TopicPostState {
        let cooked = "<p>\(username)</p>"
        return TopicPostState(
            id: id,
            username: username,
            name: nil,
            avatarTemplate: nil,
            authorMetadata: authorMetadata,
            cooked: cooked,
            renderDocument: fireRenderDocumentFixture(cooked),
            raw: username,
            postNumber: postNumber,
            postType: 1,
            createdAt: "2026-03-28T10:00:00Z",
            updatedAt: "2026-03-28T10:00:00Z",
            likeCount: 0,
            replyCount: 0,
            replyToPostNumber: nil,
            replyToUser: nil,
            bookmarked: false,
            bookmarkId: nil,
            bookmarkName: nil,
            bookmarkReminderAt: nil,
            reactions: reactions,
            currentUserReaction: nil,
            boosts: boosts,
            canBoost: !boosts.isEmpty,
            polls: [],
            acceptedAnswer: false,
            canAcceptAnswer: false,
            canUnacceptAnswer: false,
            canEdit: false,
            canDelete: false,
            canRecover: false,
            hidden: false
        )
    }

    private func makeBoost(
        id: UInt64 = 9,
        username: String,
        displayText: String
    ) -> TopicPostBoostState {
        TopicPostBoostState(
            id: id,
            cooked: "<p>\(displayText)</p>",
            renderDocument: fireRenderDocumentFixture("<p>\(displayText)</p>"),
            displayText: displayText,
            user: TopicPostBoostUserState(
                id: 7,
                username: username,
                name: nil,
                avatarTemplate: nil
            ),
            canDelete: false,
            canFlag: false,
            userFlagStatus: nil,
            availableFlags: []
        )
    }

    private func renderContent(
        plainText: String,
        attributedText: NSAttributedString?,
        imageAttachments: [FireCookedImage] = [],
        segments: [FireTopicPostRenderSegment] = []
    ) -> FireTopicPostRenderContent {
        FireTopicPostRenderContent(
            plainText: plainText,
            attributedText: attributedText,
            imageAttachments: imageAttachments,
            segments: segments,
            signature: FireTopicPostRenderSignature.make(
                source: plainText,
                imageAttachments: imageAttachments,
                segments: segments
            )
        )
    }

    private func noopCallbacks() -> FirePostCellCallbacks {
        FirePostCellCallbacks(
            onLinkTapped: { _ in },
            onOpenProfile: { _ in },
            onOpenImage: { _ in },
            onToggleLike: { _ in },
            onSelectReaction: { _, _ in },
            onToggleReactionPicker: { _ in },
            onReplyPost: { _ in },
            onBoostPost: { _ in },
            onQuotePost: { _ in },
            onEditPost: { _ in },
            onBookmarkPost: { _ in },
            onDeletePost: { _ in },
            onRecoverPost: { _ in },
            onFlagPost: { _ in },
            onOpenReplyTarget: { _ in },
            onOpenReplies: { _ in },
            onExpandText: { _ in },
            onVotePoll: { _, _, _ in },
            onUnvotePoll: { _, _ in },
            onSwipeReply: { _ in }
        )
    }


    func testCollapsedTextNormalizerCollapsesBlankLines() {
        let source = NSMutableAttributedString(string: "Hello\n\n\nWorld\n\nFire")
        let normalized = FirePostCollapsedTextNormalizer.attributedTextForCollapsedDisplay(source)
        XCTAssertEqual(normalized.string, "Hello\nWorld\nFire")
        XCTAssertFalse(normalized.string.contains("\n\n"))
    }

    func testCollapsedTextNormalizerPreservesSingleNewlines() {
        let source = NSAttributedString(string: "A\nB\nC")
        let normalized = FirePostCollapsedTextNormalizer.attributedTextForCollapsedDisplay(source)
        XCTAssertEqual(normalized.string, "A\nB\nC")
    }

    func testCollapsedTextNormalizerCollapsesReplyQuoteToHeaderLine() {
        let quote = NSMutableAttributedString()
        quote.append(NSAttributedString(string: "\u{200B}\n"))
        quote.append(NSAttributedString(
            string: "引用 @alice · #12",
            attributes: [.link: URL(string: "fire://profile/alice")!]
        ))
        quote.append(NSAttributedString(string: "\n项目完整开源，无未开源部分：是\n我的开源项目已链接认可\n"))
        quote.append(NSAttributedString(string: "\u{200B}\n"))
        let fullRange = NSRange(location: 0, length: quote.length)
        quote.addAttributes(
            [
                .fireQuotePreviewBlock: true,
                .fireQuotePreviewBackgroundColor: UIColor.secondarySystemBackground,
                .fireQuotePreviewStripeColor: UIColor.tertiaryLabel,
            ],
            range: fullRange
        )

        let post = NSMutableAttributedString(attributedString: quote)
        post.append(NSAttributedString(string: "你咋用那么多的，十分好奇。"))

        let normalized = FirePostCollapsedTextNormalizer.attributedTextForCollapsedDisplay(post)
        let text = normalized.string

        XCTAssertTrue(text.contains("引用 @alice · #12"))
        XCTAssertTrue(text.contains("你咋用那么多的，十分好奇。"))
        XCTAssertFalse(text.contains("项目完整开源"))
        XCTAssertFalse(text.contains("我的开源项目已链接认可"))
        // Quote body was elided → inline expand control so the user can open full quote chrome.
        XCTAssertTrue(text.contains("展开"))
        XCTAssertNil(
            normalized.attribute(
                .fireQuotePreviewBlock,
                at: 0,
                effectiveRange: nil
            )
        )

        let expandRange = (text as NSString).range(of: "展开")
        XCTAssertNotEqual(expandRange.location, NSNotFound)
        XCTAssertEqual(
            normalized.attribute(.link, at: expandRange.location, effectiveRange: nil) as? URL,
            FirePostCollapsedTextNormalizer.expandTextURL
        )
    }

    func testCollapsedTextNormalizerKeepsShortQuoteWithoutExpandWhenNothingElided() {
        let quote = NSMutableAttributedString(string: "引用 @bob · #3")
        quote.addAttribute(
            .fireQuotePreviewBlock,
            value: true,
            range: NSRange(location: 0, length: quote.length)
        )
        let normalized = FirePostCollapsedTextNormalizer.attributedTextForCollapsedDisplay(quote)
        XCTAssertEqual(
            normalized.string.trimmingCharacters(in: .whitespacesAndNewlines),
            "引用 @bob · #3"
        )
        XCTAssertFalse(normalized.string.contains("展开"))
    }

    func testMeasureCollapsedRichTextHeightIsAtMostFourLines() {
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let paragraphs = (0..<12).map { "段落\($0) 内容比较长用来换行" }.joined(separator: "\n\n")
        let attributed = NSAttributedString(string: paragraphs, attributes: [.font: font])
        let full = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: attributed,
            containerWidth: 300,
            contentSizeCategory: .large
        )
        let collapsed = FirePostCellLayoutCalculator.measureCollapsedRichTextHeight(
            attributedText: attributed,
            containerWidth: 300,
            truncationToken: FirePostCollapsedTextNormalizer.expansionTruncationToken()
        )
        XCTAssertNotNil(full)
        XCTAssertNotNil(collapsed)
        XCTAssertLessThan(collapsed!, full!)
        let fourLineCap = FirePostCellLayoutCalculator.collapsedTextHeight(contentSizeCategory: .large) * 1.8
        XCTAssertLessThanOrEqual(collapsed!, fourLineCap)
    }
}
