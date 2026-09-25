import Foundation

struct FireIdentifiedValue<Value>: Identifiable {
    let id: String
    let index: Int
    let value: Value
}

func fireIdentifiedValues<Value>(
    _ values: [Value],
    baseID: (Value) -> String
) -> [FireIdentifiedValue<Value>] {
    var seen: [String: Int] = [:]

    return values.enumerated().map { index, value in
        let rawBase = baseID(value).trimmingCharacters(in: .whitespacesAndNewlines)
        let base = rawBase.isEmpty ? "item" : rawBase
        let occurrence = seen[base, default: 0]
        seen[base] = occurrence + 1

        return FireIdentifiedValue(
            id: occurrence == 0 ? base : "\(base)#\(occurrence)",
            index: index,
            value: value
        )
    }
}

extension UserActionState {
    var fireStableBaseID: String {
        [
            "type:\(actionType)",
            "topic:\(topicId.map(String.init) ?? "nil")",
            "post:\(postNumber.map(String.init) ?? "nil")",
            "title:\(title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")",
            "slug:\(slug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")",
            "created:\(createdAt ?? "")",
            "actor:\(actingUsername ?? "")",
        ].joined(separator: "|")
    }
}

extension InviteLinkState {
    var fireStableBaseID: String {
        if let inviteID = invite?.id {
            return "invite:id:\(inviteID)"
        }
        if let inviteKey = invite?.inviteKey, !inviteKey.isEmpty {
            return "invite:key:\(inviteKey)"
        }
        let trimmedLink = inviteLink.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLink.isEmpty ? "invite:pending" : "invite:link:\(trimmedLink)"
    }
}

extension NetworkTraceEventState {
    var fireStableBaseID: String {
        "event:\(sequence)"
    }
}

extension NetworkTraceHeaderState {
    var fireStableBaseID: String {
        "header:\(name.lowercased())=\(value)"
    }
}
