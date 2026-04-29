import Foundation

enum StoreRefreshScope: Hashable, CaseIterable {
    case tasks
    case ledgerVisible
    case ledgerHistory
    case pomodoro
    case preferences
    case countdown
    case checklist
    case rollups
    case analytics
    case liveActivities

    static let full: Set<StoreRefreshScope> = Set(allCases)
}

enum StoreDomainMutation: Hashable {
    case taskTree
    case timer
    case ledgerHistory
    case pomodoro
    case checklist
    case preferences
    case countdown
    case allData
}

struct StoreRefreshPlanner {
    func scopes(after mutations: Set<StoreDomainMutation>) -> Set<StoreRefreshScope> {
        guard mutations.isEmpty == false else { return [] }
        if mutations.contains(.allData) {
            return StoreRefreshScope.full
        }

        return mutations.reduce(into: Set<StoreRefreshScope>()) { result, mutation in
            result.formUnion(scopes(after: mutation))
        }
    }

    func scopes(after mutation: StoreDomainMutation) -> Set<StoreRefreshScope> {
        switch mutation {
        case .taskTree:
            return [.tasks, .rollups, .analytics, .liveActivities]
        case .timer:
            return [.ledgerVisible, .pomodoro, .rollups, .analytics, .liveActivities]
        case .ledgerHistory:
            return [.ledgerHistory, .rollups, .analytics, .liveActivities]
        case .pomodoro:
            return [.ledgerVisible, .pomodoro, .rollups, .analytics, .liveActivities]
        case .checklist:
            return [.checklist, .rollups, .analytics]
        case .preferences:
            return [.preferences]
        case .countdown:
            return [.countdown]
        case .allData:
            return StoreRefreshScope.full
        }
    }
}
