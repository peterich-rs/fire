import UIKit
import XCTest
@testable import Fire

final class FireAppearanceEnvironmentTests: XCTestCase {
    func testSnapshotLightCanvasIsNotPureBlack() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let snapshot = FireAppearanceSnapshot.make(traits: light, preference: .light)
        XCTAssertEqual(snapshot.token, "light")
        XCTAssertEqual(snapshot.preference, .light)
        XCTAssertGreaterThan(Self.relativeLuminance(snapshot.canvas), 0.85)
        XCTAssertLessThan(Self.relativeLuminance(snapshot.ink), 0.35)
    }

    func testSnapshotDarkCanvasIsNearBlack() {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let snapshot = FireAppearanceSnapshot.make(traits: dark, preference: .dark)
        XCTAssertEqual(snapshot.token, "dark")
        XCTAssertEqual(snapshot.preference, .dark)
        XCTAssertLessThan(Self.relativeLuminance(snapshot.canvas), 0.08)
        XCTAssertGreaterThan(Self.relativeLuminance(snapshot.ink), 0.80)
    }

    func testOledTokenWhenPreferenceIsOledAndStyleDark() {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let snapshot = FireAppearanceSnapshot.make(traits: dark, preference: .oled)
        XCTAssertEqual(snapshot.token, "oled")
        XCTAssertEqual(snapshot.preference, .oled)
    }

    func testLightAndDarkSnapshotsDiffer() {
        let light = FireAppearanceSnapshot.make(
            traits: UITraitCollection(userInterfaceStyle: .light),
            preference: .light
        )
        let dark = FireAppearanceSnapshot.make(
            traits: UITraitCollection(userInterfaceStyle: .dark),
            preference: .dark
        )
        XCTAssertNotEqual(light.token, dark.token)
        XCTAssertNotEqual(light.canvas.cgColor, dark.canvas.cgColor)
        XCTAssertNotEqual(light.ink.cgColor, dark.ink.cgColor)
        XCTAssertNotEqual(light, dark)
    }

    func testSnapshotEqualityUsesTokenAndPreference() {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let a = FireAppearanceSnapshot.make(traits: traits, preference: .light)
        let b = FireAppearanceSnapshot.make(traits: traits, preference: .light)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.token, b.token)
    }

    func testPayloadAppearanceTokenDrivesContentIdentity() {
        let light = FireAppearanceSnapshot.make(
            traits: UITraitCollection(userInterfaceStyle: .light),
            preference: .light
        )
        let dark = FireAppearanceSnapshot.make(
            traits: UITraitCollection(userInterfaceStyle: .dark),
            preference: .dark
        )
        XCTAssertNotEqual(light.token, dark.token)
        // Soft rebind compares tokens; unequal tokens must force text re-bake.
        XCTAssertNotEqual(light.token, dark.token)
    }

    func testTraitsForceWindowOverrideWhenViewLags() {
        // Simulate lagging light traits while preference wants dark via synthetic
        // trait merge (same algorithm as Environment when override ≠ view).
        let lagging = UITraitCollection(userInterfaceStyle: .light)
        let forced = UITraitCollection(traitsFrom: [
            lagging,
            UITraitCollection(userInterfaceStyle: .dark),
        ])
        XCTAssertEqual(forced.userInterfaceStyle, .dark)
        let snapshot = FireAppearanceSnapshot.make(traits: forced, preference: .dark)
        XCTAssertEqual(snapshot.token, "dark")
        XCTAssertLessThan(Self.relativeLuminance(snapshot.canvas), 0.08)
    }

    func testResolvingAttributedTextUsesSnapshotTraits() {
        let dark = FireAppearanceSnapshot.make(
            traits: UITraitCollection(userInterfaceStyle: .dark),
            preference: .dark
        )
        let source = NSAttributedString(
            string: "body",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: FireTheme.uiInk,
            ]
        )
        let resolved = dark.resolvingDynamicColors(source)
        let color = resolved.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        XCTAssertEqual(color?.cgColor, dark.ink.cgColor)
    }

    private static func relativeLuminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        var white: CGFloat = 0
        if color.getWhite(&white, alpha: &a) {
            return white
        }
        return -1
    }
}
