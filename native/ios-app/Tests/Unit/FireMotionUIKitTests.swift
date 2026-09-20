import UIKit
import XCTest
@testable import Fire

@MainActor
final class FireMotionUIKitTests: XCTestCase {
    func testPressBounceStyleUsesProductionScales() {
        XCTAssertEqual(FirePressBounceStyle.button.pressedScale, 0.94, accuracy: 0.001)
        XCTAssertEqual(FirePressBounceStyle.compact.pressedScale, 0.88, accuracy: 0.001)
        XCTAssertEqual(FirePressBounceStyle.chip.pressedScale, 0.80, accuracy: 0.001)
        XCTAssertEqual(FirePressBounceStyle.button.overshootScale, 1.03, accuracy: 0.001)
        XCTAssertEqual(FirePressBounceStyle.compact.overshootScale, 1.06, accuracy: 0.001)
        XCTAssertEqual(FirePressBounceStyle.chip.overshootScale, 1.10, accuracy: 0.001)
    }

    func testBoundPressBounceAnimatesIntoCompactPressedStateOnTouchDown() {
        let button = UIButton(type: .system)
        button.fireBindPressBounce(.compact)

        button.sendActions(for: .touchDown)

        XCTAssertEqual(button.transform.fireScaleX, 0.88, accuracy: 0.001)
        XCTAssertEqual(button.transform.fireScaleY, 0.88, accuracy: 0.001)
        XCTAssertEqual(button.alpha, 0.92, accuracy: 0.001)
    }

    func testBoundPressBounceReleasesThroughSingleLayerChannel() {
        let button = UIButton(type: .system)
        button.fireBindPressBounce(.compact)

        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)

        XCTAssertTrue(button.transform.isIdentity)
        XCTAssertEqual(button.alpha, 1.0, accuracy: 0.001)
        XCTAssertNotNil(button.layer.animation(forKey: UIView.fireTapBounceKey))
        XCTAssertNil(button.layer.animation(forKey: "transform"))
    }

    func testTapBounceKeepsIdentityModelAndOneScaleAnimation() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))

        view.fireTapBounce(pressedScale: 0.80, overshootScale: 1.10)

        XCTAssertTrue(view.transform.isIdentity)
        XCTAssertEqual(view.alpha, 1.0, accuracy: 0.001)
        let animation = view.layer.animation(forKey: UIView.fireTapBounceKey) as? CAKeyframeAnimation
        XCTAssertEqual(animation?.keyPath, "transform.scale")
        let values = (animation?.values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0], 0.80, accuracy: 0.001)
        XCTAssertEqual(values[1], 1.10, accuracy: 0.001)
        XCTAssertEqual(values[2], 1.0, accuracy: 0.001)
    }
}

private extension CGAffineTransform {
    var fireScaleX: CGFloat {
        sqrt((a * a) + (c * c))
    }

    var fireScaleY: CGFloat {
        sqrt((b * b) + (d * d))
    }
}
