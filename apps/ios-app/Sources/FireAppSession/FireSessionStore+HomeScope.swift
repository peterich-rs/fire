import Foundation

extension FireSessionStore {
    public func currentHomeTopicListScope() throws -> HomeTopicListScopeState {
        try core.session().currentHomeTopicListScope()
    }

    @discardableResult
    public func setCurrentHomeTopicListScope(
        _ scope: HomeTopicListScopeState
    ) throws -> HomeTopicListScopeState {
        try core.session().setCurrentHomeTopicListScope(scope: scope)
    }
}
