import XCTest
@testable import Fire

final class FireAvatarURLTests: XCTestCase {
    func testAvatarURLReplacesTemplateSizeAndResolvesRelativePath() {
        let url = fireAvatarURL(
            avatarTemplate: "/user_avatar/linux.do/alice/{size}/1_2.png",
            size: 34,
            scale: 3,
            baseURLString: "https://linux.do"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://linux.do/user_avatar/linux.do/alice/102/1_2.png"
        )
    }

    func testAvatarURLSupportsProtocolRelativePath() {
        let url = fireAvatarURL(
            avatarTemplate: "//cdn.linux.do/user_avatar/linux.do/alice/{size}/1_2.png",
            size: 32,
            scale: 2,
            baseURLString: "https://linux.do"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://cdn.linux.do/user_avatar/linux.do/alice/64/1_2.png"
        )
    }
}
