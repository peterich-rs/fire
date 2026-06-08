import AsyncDisplayKit
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
            boostSignature: [],
            hasReactions: false,
            replyShortcutCount: nil,
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
        XCTAssertEqual(layout.metaFrame.minY, 8, accuracy: 0.01)
        XCTAssertEqual(layout.textFrame?.minY ?? -.greatestFiniteMagnitude, expectedTextMinY, accuracy: 0.01)
        XCTAssertEqual(layout.dividerFrame?.minX ?? -.greatestFiniteMagnitude, 16, accuracy: 0.01)
        XCTAssertEqual(layout.dividerFrame?.width ?? -.greatestFiniteMagnitude, 288, accuracy: 0.01)
        XCTAssertEqual(layout.totalHeight, expectedTotalHeight, accuracy: 0.01)
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
            boostSignature: [],
            hasReactions: false,
            replyShortcutCount: nil,
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
            replyShortcutCount: nil,
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
            replyShortcutCount: nil,
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
            replyShortcutCount: 3,
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
            boostSignature: [],
            hasReactions: true,
            replyShortcutCount: nil,
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
            replyShortcutCount: nil,
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
        XCTAssertGreaterThan(layout.reactionsFrame?.minY ?? 0, layout.boostFrames[0].maxY)
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
            replyShortcutCount: nil,
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
        let boost = makeBoost(username: "carol", displayText: "  Thanks for the detail  ")

        XCTAssertEqual(FirePostBoostDisplay.displayLine(for: boost), "Thanks for the detail")
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
            replyShortcutCount: nil,
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
            replyShortcutCount: nil,
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
            (layout.textFrame?.maxY ?? 0) + FirePostCellLayoutCalculator.replyShortcutTopSpacing,
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
                replyShortcutCount: nil,
                isLoadingReplyContext: false,
                textExpansionState: .disabled,
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
        let renderContent = fireRenderContentFixture("<p>Fire native detail row with reply shortcut and reactions.</p>")
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
                replyShortcutCount: 3,
                isLoadingReplyContext: false,
                textExpansionState: .disabled,
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
            replyShortcutCount: 3,
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

        XCTAssertEqual(measuredLayout.size.height, calculatedLayout.totalHeight, accuracy: 2.5)
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
                replyShortcutCount: nil,
                isLoadingReplyContext: false,
                textExpansionState: collapsed,
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
                replyShortcutCount: nil,
                isLoadingReplyContext: false,
                textExpansionState: collapsed,
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

    func testCommentImageRenderSizeIsScaledDownAndRootImagesRespectMaxHeight() throws {
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

        XCTAssertEqual(rootSize.height, FirePostCellLayoutCalculator.topicImageMaxHeight, accuracy: 0.01)
        XCTAssertLessThan(commentSize.width, rootSize.width)
        XCTAssertLessThanOrEqual(commentSize.height, FirePostCellLayoutCalculator.commentImageMaxHeight)
    }

    func testAuthorMetadataMovesBadgesToPrimaryLineAndCondensesTrustLevel() {
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

        XCTAssertEqual(
            FirePostAuthorMetadataDisplay.primaryBadgeParts(for: post),
            ["Lv.2", "版主", "core-team", "Maintai..."]
        )
        XCTAssertEqual(
            FirePostAuthorMetadataDisplay.secondaryLineParts(for: post),
            ["@alice", "Shipping Fire"]
        )
    }

    func testReactionDisplayPolicyKeepsOriginalPostReactionsButCapsRepliesAtThree() {
        let reactions = [
            TopicReactionState(id: "heart", kind: nil, count: 12, canUndo: true),
            TopicReactionState(id: "clap", kind: nil, count: 4, canUndo: true),
            TopicReactionState(id: "laughing", kind: nil, count: 3, canUndo: true),
            TopicReactionState(id: "tada", kind: nil, count: 2, canUndo: true),
        ]

        let originalVisible = FirePostReactionDisplayPolicy.visibleReactions(from: reactions, depth: 0)
        let replyVisible = FirePostReactionDisplayPolicy.visibleReactions(from: reactions, depth: 1)

        XCTAssertEqual(originalVisible.map(\.id), reactions.map(\.id))
        XCTAssertEqual(replyVisible.map(\.id), ["heart", "clap", "laughing"])
        XCTAssertTrue(FirePostReactionDisplayPolicy.allowsWrapping(depth: 0))
        XCTAssertFalse(FirePostReactionDisplayPolicy.allowsWrapping(depth: 1))
    }

    private func makePost(
        id: UInt64,
        postNumber: UInt32,
        username: String,
        authorMetadata: TopicPostAuthorMetadataState = fireEmptyPostAuthorMetadataState(),
        reactions: [TopicReactionState] = []
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
            boosts: [],
            canBoost: false,
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
}
