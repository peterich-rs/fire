import XCTest
@testable import Fire

@MainActor
final class FireUIKitAppearanceCapsuleControlTests: XCTestCase {
    func testNormalizedForPickerMapsOLEDToDark() {
        XCTAssertEqual(
            FireUIKitAppearanceCapsuleControl.normalizedForPicker(.oled),
            .dark
        )
        XCTAssertEqual(
            FireUIKitAppearanceCapsuleControl.normalizedForPicker(.dark),
            .dark
        )
        XCTAssertEqual(
            FireUIKitAppearanceCapsuleControl.normalizedForPicker(.system),
            .system
        )
        XCTAssertEqual(
            FireUIKitAppearanceCapsuleControl.normalizedForPicker(.light),
            .light
        )
    }

    func testInitialLayoutPlacesSelectionPillOnStoredPreferenceWithoutUserTap() {
        let control = FireUIKitAppearanceCapsuleControl(frame: CGRect(x: 0, y: 0, width: 320, height: 52))
        control.selectedPreference = .light

        // Mimic being attached to a windowed hierarchy so Auto Layout resolves.
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        host.addSubview(control)
        control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            control.topAnchor.constraint(equalTo: host.topAnchor, constant: 8),
        ])
        host.layoutIfNeeded()
        control.layoutIfNeeded()

        XCTAssertFalse(
            control.isSelectionPillHiddenForTesting,
            "Selection pill must be visible on first layout without a tap"
        )
        XCTAssertGreaterThan(control.selectionPillFrameForTesting.width, 1)
        XCTAssertGreaterThan(control.selectionPillFrameForTesting.height, 1)

        guard let lightFrame = control.buttonFrameForTesting(.light) else {
            return XCTFail("Expected light segment button")
        }
        XCTAssertEqual(
            control.selectionPillFrameForTesting.origin.x,
            lightFrame.origin.x,
            accuracy: 1.0,
            "Pill should sit on the light segment after initial layout"
        )
        XCTAssertEqual(
            control.selectionPillFrameForTesting.width,
            lightFrame.width,
            accuracy: 1.0
        )
    }

    func testSelectionPillFollowsEachPickerOptionOnLayout() {
        let control = FireUIKitAppearanceCapsuleControl(frame: CGRect(x: 0, y: 0, width: 360, height: 52))
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 360, height: 80))
        host.addSubview(control)
        control.frame = CGRect(x: 0, y: 8, width: 360, height: 52)
        host.layoutIfNeeded()
        control.layoutIfNeeded()

        for preference in FireUIKitAppearanceCapsuleControl.pickerOptions {
            control.selectedPreference = preference
            control.layoutIfNeeded()

            XCTAssertFalse(control.isSelectionPillHiddenForTesting)
            guard let buttonFrame = control.buttonFrameForTesting(preference) else {
                return XCTFail("Missing button for \(preference)")
            }
            XCTAssertEqual(
                control.selectionPillFrameForTesting.midX,
                buttonFrame.midX,
                accuracy: 1.5,
                "Pill midX should match \(preference) segment"
            )
        }
    }

    func testOLEDPreferenceSelectsDarkSegmentPill() {
        let control = FireUIKitAppearanceCapsuleControl(frame: CGRect(x: 0, y: 0, width: 320, height: 52))
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        host.addSubview(control)
        control.frame = CGRect(x: 0, y: 8, width: 320, height: 52)

        control.selectedPreference = .oled
        host.layoutIfNeeded()
        control.layoutIfNeeded()

        XCTAssertEqual(control.selectedPreference, .dark)
        XCTAssertFalse(control.isSelectionPillHiddenForTesting)
        guard let darkFrame = control.buttonFrameForTesting(.dark) else {
            return XCTFail("Expected dark segment button")
        }
        XCTAssertEqual(
            control.selectionPillFrameForTesting.midX,
            darkFrame.midX,
            accuracy: 1.5
        )
    }
}
