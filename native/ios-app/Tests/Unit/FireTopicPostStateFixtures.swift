@testable import Fire

func fireEmptyPostAuthorMetadataState() -> TopicPostAuthorMetadataState {
    TopicPostAuthorMetadataState(
        userId: nil,
        userTitle: nil,
        primaryGroupName: nil,
        flairUrl: nil,
        flairName: nil,
        flairBgColor: nil,
        flairColor: nil,
        flairGroupId: nil,
        moderator: false,
        admin: false,
        groupModerator: false,
        userStatusEmoji: nil,
        userStatusDescription: nil
    )
}
