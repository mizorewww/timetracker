import Foundation

enum StoreRefreshScope: Hashable, CaseIterable {
    case tasks
    case ledgerVisible
    case ledgerHistory
    case pomodoro
    case preferences
    case countdown
    case checklist
    case inbox
    case rollups
    case analytics
    case liveActivities

    static let full: Set<StoreRefreshScope> = Set(allCases)
}

struct StoreInvalidationRange: Hashable {
    let start: Date
    let end: Date
}

enum StoreDomainEvent: Hashable {
    case taskChanged(taskID: UUID?, affectedAncestorIDs: Set<UUID>)
    case checklistChanged(taskID: UUID?, affectedAncestorIDs: Set<UUID>)
    case ledgerChanged(taskID: UUID?, dateInterval: StoreInvalidationRange?, isVisible: Bool)
    case pomodoroChanged(runID: UUID?, sessionID: UUID?, taskID: UUID?)
    case preferenceChanged(key: String?)
    case countdownChanged
    case inboxChanged
    case remoteImportCompleted
    case fullSync

    var affectedTaskIDs: Set<UUID> {
        switch self {
        case .taskChanged(let taskID, let affectedAncestorIDs),
             .checklistChanged(let taskID, let affectedAncestorIDs):
            var ids = affectedAncestorIDs
            if let taskID {
                ids.insert(taskID)
            }
            return ids
        case .ledgerChanged(let taskID, _, _),
             .pomodoroChanged(_, _, let taskID):
            return taskID.map { [$0] } ?? []
        case .preferenceChanged,
             .countdownChanged,
             .inboxChanged,
             .remoteImportCompleted,
             .fullSync:
            return []
        }
    }

    var affectedLedgerRanges: [StoreInvalidationRange] {
        switch self {
        case .ledgerChanged(_, let dateInterval, _):
            return dateInterval.map { [$0] } ?? []
        case .taskChanged,
             .pomodoroChanged,
             .checklistChanged,
             .preferenceChanged,
             .countdownChanged,
             .inboxChanged,
             .remoteImportCompleted,
             .fullSync:
            return []
        }
    }
}

struct StoreRefreshPlan: Equatable {
    let scopes: Set<StoreRefreshScope>
    let affectedTaskIDs: Set<UUID>
    let affectedLedgerRanges: [StoreInvalidationRange]
    let refreshTasks: Bool
    let refreshLedger: Bool
    let includeLedgerHistory: Bool
    let refreshPomodoro: Bool
    let refreshPreferences: Bool
    let refreshCountdown: Bool
    let refreshChecklist: Bool
    let refreshInbox: Bool
    let refreshRollups: Bool
    let refreshAnalytics: Bool
    let validateSelection: Bool
    let syncLiveActivities: Bool

    init(scopes: Set<StoreRefreshScope>, affectedTaskIDs: Set<UUID> = [], affectedLedgerRanges: [StoreInvalidationRange] = []) {
        self.scopes = scopes
        self.affectedTaskIDs = affectedTaskIDs
        self.affectedLedgerRanges = affectedLedgerRanges
        let isFullRefresh = scopes == StoreRefreshScope.full

        refreshTasks = isFullRefresh || scopes.contains(.tasks)
        includeLedgerHistory = isFullRefresh || scopes.contains(.ledgerHistory)
        refreshLedger = isFullRefresh || scopes.contains(.ledgerVisible) || scopes.contains(.ledgerHistory)
        refreshPomodoro = isFullRefresh || scopes.contains(.pomodoro)
        refreshPreferences = isFullRefresh || scopes.contains(.preferences)
        refreshCountdown = isFullRefresh || scopes.contains(.countdown)
        refreshChecklist = isFullRefresh || scopes.contains(.checklist)
        refreshInbox = isFullRefresh || scopes.contains(.inbox)

        refreshRollups = isFullRefresh ||
            scopes.contains(.rollups) ||
            scopes.contains(.tasks) ||
            scopes.contains(.ledgerVisible) ||
            scopes.contains(.ledgerHistory) ||
            scopes.contains(.checklist)

        refreshAnalytics = isFullRefresh ||
            scopes.contains(.analytics) ||
            scopes.contains(.tasks) ||
            scopes.contains(.ledgerVisible) ||
            scopes.contains(.ledgerHistory) ||
            scopes.contains(.checklist)

        validateSelection = refreshTasks || refreshLedger
        syncLiveActivities = isFullRefresh ||
            scopes.contains(.liveActivities) ||
            scopes.contains(.ledgerVisible) ||
            scopes.contains(.ledgerHistory) ||
            scopes.contains(.tasks)
    }
}

struct StoreRefreshPlanner {
    func plan(after events: Set<StoreDomainEvent>) -> StoreRefreshPlan {
        StoreRefreshPlan(
            scopes: scopes(after: events),
            affectedTaskIDs: events.reduce(into: Set<UUID>()) { $0.formUnion($1.affectedTaskIDs) },
            affectedLedgerRanges: events.flatMap(\.affectedLedgerRanges)
        )
    }

    func scopes(after events: Set<StoreDomainEvent>) -> Set<StoreRefreshScope> {
        guard events.isEmpty == false else { return [] }
        if events.contains(.fullSync) || events.contains(.remoteImportCompleted) {
            return StoreRefreshScope.full
        }

        return events.reduce(into: Set<StoreRefreshScope>()) { result, event in
            result.formUnion(scopes(after: event))
        }
    }

    func scopes(after event: StoreDomainEvent) -> Set<StoreRefreshScope> {
        switch event {
        case .taskChanged:
            return [.tasks, .rollups, .analytics, .liveActivities]
        case .ledgerChanged(_, _, let isVisible):
            if isVisible {
                return [.ledgerVisible, .pomodoro, .rollups, .analytics, .liveActivities]
            }
            return [.ledgerHistory, .rollups, .analytics, .liveActivities]
        case .pomodoroChanged:
            return [.ledgerVisible, .pomodoro, .rollups, .analytics, .liveActivities]
        case .checklistChanged:
            return [.checklist, .rollups, .analytics]
        case .preferenceChanged:
            return [.preferences]
        case .countdownChanged:
            return [.countdown]
        case .inboxChanged:
            return [.inbox]
        case .remoteImportCompleted:
            return StoreRefreshScope.full
        case .fullSync:
            return StoreRefreshScope.full
        }
    }
}
