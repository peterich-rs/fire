import UIKit
import XCTest
@testable import Fire

final class FireTextureAttributedTextTests: XCTestCase {
    func testAppearanceTokenDistinguishesStyles() {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let light = UITraitCollection(userInterfaceStyle: .light)
        XCTAssertEqual(FireTextureAttributedText.appearanceToken(for: dark), "dark")
        XCTAssertEqual(FireTextureAttributedText.appearanceToken(for: light), "light")
        XCTAssertNotEqual(
            FireTextureAttributedText.appearanceToken(for: dark),
            FireTextureAttributedText.appearanceToken(for: light)
        )
    }

    func testResolvingDynamicColorsBakesLightLabelToDarkCanvasContrast() {
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        let source = NSAttributedString(
            string: "body",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: FireTheme.uiInk,
            ]
        )

        let lightResolved = FireTextureAttributedText.resolvingDynamicColors(source, with: lightTraits)
        let darkResolved = FireTextureAttributedText.resolvingDynamicColors(source, with: darkTraits)

        let lightColor = lightResolved.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? UIColor
        let darkColor = darkResolved.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? UIColor

        XCTAssertNotNil(lightColor)
        XCTAssertNotNil(darkColor)

        let lightResolvedInk = FireTheme.uiInk.resolvedColor(with: lightTraits)
        let darkResolvedInk = FireTheme.uiInk.resolvedColor(with: darkTraits)
        XCTAssertEqual(lightColor?.cgColor, lightResolvedInk.cgColor)
        XCTAssertEqual(darkColor?.cgColor, darkResolvedInk.cgColor)
        XCTAssertNotEqual(lightResolvedInk.cgColor, darkResolvedInk.cgColor)
    }

    func testExpansionTruncationTokenUsesResolvedInkAndAccent() {
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
        let token = FirePostCollapsedTextNormalizer.expansionTruncationToken(
            accentColor: FireTheme.uiAccent,
            colorTraits: darkTraits
        )
        XCTAssertTrue(token.string.contains("展开"))
        let expandRange = (token.string as NSString).range(of: "展开")
        XCTAssertNotEqual(expandRange.location, NSNotFound)
        let expandColor = token.attribute(.foregroundColor, at: expandRange.location, effectiveRange: nil) as? UIColor
        let expectedAccent = FireTheme.uiAccent.resolvedColor(with: darkTraits)
        XCTAssertEqual(expandColor?.cgColor, expectedAccent.cgColor)
    }

    func testPayloadAppearanceTokenChangesContentBindingIdentity() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertNotEqual(
            FireTextureAttributedText.appearanceToken(for: light),
            FireTextureAttributedText.appearanceToken(for: dark)
        )
    }
}
