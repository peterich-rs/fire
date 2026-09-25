import AsyncDisplayKit
import UIKit

struct FirePostBoostManualPlacement: Equatable {
    let rowIndex: Int
    let x: CGFloat
}

struct FirePostBoostManualLayoutResult: Equatable {
    let placements: [FirePostBoostManualPlacement]
    let contentWidth: CGFloat
    let usedRowCount: Int
}

enum FirePostBoostManualLayout {
    static let chipSpacing: CGFloat = 8

    static func placements(
        forChipWidths chipWidths: [CGFloat],
        pageWidth: CGFloat,
        laneCount: Int = 2,
        chipSpacing: CGFloat = chipSpacing
    ) -> FirePostBoostManualLayoutResult {
        let resolvedPageWidth = max(pageWidth, 1)
        let resolvedLaneCount = max(laneCount, 1)
        var pageStartX: CGFloat = 0
        var cursorXByRow = Array(repeating: CGFloat(0), count: resolvedLaneCount)
        var currentRowIndex = 0
        var placements: [FirePostBoostManualPlacement] = []
        placements.reserveCapacity(chipWidths.count)

        for rawChipWidth in chipWidths {
            let chipWidth = min(max(rawChipWidth, 1), resolvedPageWidth)
            var x = nextX(cursorX: cursorXByRow[currentRowIndex], chipSpacing: chipSpacing)
            if x + chipWidth > resolvedPageWidth {
                if currentRowIndex + 1 < resolvedLaneCount {
                    currentRowIndex += 1
                    x = 0
                } else {
                    pageStartX += max(cursorXByRow.max() ?? 0, resolvedPageWidth) + chipSpacing
                    cursorXByRow = Array(repeating: CGFloat(0), count: resolvedLaneCount)
                    currentRowIndex = 0
                    x = 0
                }
            }
            placements.append(FirePostBoostManualPlacement(rowIndex: currentRowIndex, x: pageStartX + x))
            cursorXByRow[currentRowIndex] = x + chipWidth
        }

        let contentWidth = max(pageStartX + (cursorXByRow.max() ?? 0), resolvedPageWidth)
        let usedRowCount = placements.reduce(0) { partialResult, placement in
            max(partialResult, placement.rowIndex + 1)
        }
        return FirePostBoostManualLayoutResult(
            placements: placements,
            contentWidth: contentWidth,
            usedRowCount: usedRowCount
        )
    }

    static func chipWidth(
        for attributedText: NSAttributedString?,
        maxWidth: CGFloat,
        nonTextWidth: CGFloat,
        minWidth: CGFloat
    ) -> CGFloat {
        let textSize = measuredSingleLineTextSize(
            attributedText: attributedText,
            maxWidth: max(maxWidth - nonTextWidth, 1)
        )
        return min(max(textSize.width + nonTextWidth, minWidth), max(maxWidth, 1))
    }

    static func measuredSingleLineTextSize(
        attributedText: NSAttributedString?,
        maxWidth: CGFloat
    ) -> CGSize {
        guard let attributedText,
              attributedText.length > 0 else {
            return .zero
        }
        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(
            width: max(maxWidth, 1),
            height: .greatestFiniteMagnitude
        ))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 1
        textContainer.lineBreakMode = .byTruncatingTail
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else {
            return .zero
        }
        let usedRect = layoutManager.usedRect(for: textContainer)
        return CGSize(
            width: min(ceil(usedRect.width), max(maxWidth, 1)),
            height: ceil(usedRect.height)
        )
    }

    private static func nextX(cursorX: CGFloat, chipSpacing: CGFloat) -> CGFloat {
        cursorX <= 0 ? 0 : cursorX + chipSpacing
    }
}

// MARK: - Fixed Boost Manual Scroller

final class FirePostBoostManualScrollerView: UIView {
    private static let laneCount = 2
    private static let chipHeight: CGFloat = FirePostCellLayoutCalculator.fixedBoostManualRowHeight

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private var rowViews: [UIView] = []
    private var chips: [FirePostBoostChipView] = []
    private var signature: String = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        clipsToBounds = false
        backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.delaysContentTouches = false
        scrollView.backgroundColor = .clear
        addSubview(scrollView)
        scrollView.addSubview(contentView)
        for _ in 0..<Self.laneCount {
            let row = UIView()
            row.clipsToBounds = false
            contentView.addSubview(row)
            rowViews.append(row)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(boosts: [TopicPostBoostState], baseURLString: String) {
        let visibleBoosts = boosts.filter {
            !$0.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let nextSignature = visibleBoosts.map(FirePostBoostDisplay.contentSignature(for:)).joined(separator: "\u{1E}")
        guard nextSignature != signature else {
            isHidden = visibleBoosts.isEmpty
            return
        }

        signature = nextSignature
        chips.forEach { chip in
            chip.removeFromSuperview()
        }
        chips.removeAll()
        scrollView.setContentOffset(.zero, animated: false)
        isHidden = visibleBoosts.isEmpty

        for (index, boost) in visibleBoosts.enumerated() {
            let chip = FirePostBoostChipView.styleForManual()
            chip.configure(
                boost: boost,
                attributedText: FirePostBoostDisplay.compactChipContent(
                    for: boost,
                    textColor: FireTheme.uiSubtleInk
                ),
                signature: FirePostBoostDisplay.contentSignature(for: boost),
                baseURLString: baseURLString
            )
            rowViews[index % Self.laneCount].addSubview(chip)
            chips.append(chip)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutRows()
    }

    private func layoutRows() {
        guard bounds.width > 1, bounds.height > 1 else {
            return
        }

        let rowHeight = FirePostCellLayoutCalculator.fixedBoostManualRowHeight
        let rowSpacing = FirePostCellLayoutCalculator.fixedBoostManualRowSpacing
        scrollView.frame = bounds
        let maxChipWidth = max(bounds.width * 0.72, 1)
        let chipWidths = chips.map { chip in
            let measured = chip.sizeThatFits(CGSize(width: maxChipWidth, height: Self.chipHeight))
            return min(max(measured.width, 48), maxChipWidth)
        }
        let manualLayout = FirePostBoostManualLayout.placements(
            forChipWidths: chipWidths,
            pageWidth: bounds.width,
            laneCount: Self.laneCount
        )

        for (index, chip) in chips.enumerated() {
            guard index < manualLayout.placements.count else {
                continue
            }
            let placement = manualLayout.placements[index]
            let rowIndex = min(max(placement.rowIndex, 0), rowViews.count - 1)
            if chip.superview !== rowViews[rowIndex] {
                rowViews[rowIndex].addSubview(chip)
            }
            chip.frame = CGRect(
                x: placement.x,
                y: max((rowHeight - Self.chipHeight) / 2, 0),
                width: chipWidths[index],
                height: Self.chipHeight
            )
            chip.alpha = 1
            chip.transform = .identity
        }

        let contentWidth = manualLayout.contentWidth
        contentView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: bounds.height)
        scrollView.contentSize = CGSize(width: contentWidth, height: bounds.height)
        for (rowIndex, row) in rowViews.enumerated() {
            row.transform = .identity
            row.frame = CGRect(
                x: 0,
                y: CGFloat(rowIndex) * (rowHeight + rowSpacing),
                width: contentWidth,
                height: rowHeight
            )
        }
    }
}
