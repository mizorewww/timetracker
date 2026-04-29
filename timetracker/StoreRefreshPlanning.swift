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

struct StoreInvalidationRange: Hashable {
    let start: Date
    let end: Date
}

enum StoreInvalidationEvent: Hashable {
    case taskTreeChanged(taskID: UUID?)
    case timerChanged(taskID: UUID?)
    case ledgerHistoryChanged(taskID: UUID?, range: StoreInvalidationRange?)
    case pomodoroChanged(taskID: UUID?)
    case checklistChanged(taskID: UUID?)
    case preferencesChanged
    case countdownChanged
    case fullSync

    var affectedTaskIDs: Set<UUID> {
        switch self {
        case .taskTreeChanged(let taskID),
             .timerChanged(let taskID),
             .pomodoroChanged(let taskID),
             .checklistChanged(let taskID):
            return taskID.map { [$0] } ?? []
        case .ledgerHistoryChanged(let taskID, _):
            return taskID.map { [$0] } ?? []
        case .preferencesChanged,
             .countdownChanged,
             .fullSync:
            return []
        }
    }
}

struct StoreRefreshPlan: Equatable {
    let scopes: Set<StoreRefreshScope>
    let refreshTasks: Bool
    let refreshLedger: Bool
    let includeLedgerHistory: Bool
    let refreshPomodoro: Bool
    let refreshPreferences: Bool
    let refreshCountdown: Bool
    let refreshChecklist: Bool
    let refreshRollups: Bool
    let refreshAnalytics: Bool
    let validateSelection: Bool
    let syncLiveActivities: Bool

    init(scopes: Set<StoreRefreshScope>) {
        self.scopes = scopes
        let isFullRefresh = scopes == StoreRefreshScope.full

        refreshTasks = isFullRefresh || scopes.contains(.tasks)
        includeLedgerHistory = isFullRefresh || scopes.contains(.ledgerHistory)
        refreshLedger = isFullRefresh || scopes.contains(.ledgerVisible) || scopes.contains(.ledgerHistory)
        refreshPomodoro = isFullRefresh || scopes.contains(.pomodoro)
        refreshPreferences = isFullRefresh || scopes.contains(.preferences)
        refreshCountdown = isFullRefresh || scopes.contains(.countdown)
        refreshChecklist = isFullRefresh || scopes.contains(.checklist)

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
    func plan(after events: Set<StoreInvalidationEvent>) -> StoreRefreshPlan {
        StoreRefreshPlan(scopes: scopes(after: events))
    }

    func plan(for scopes: Set<StoreRefreshScope>) -> StoreRefreshPlan {
        StoreRefreshPlan(scopes: scopes)
    }

    func scopes(after events: Set<StoreInvalidationEvent>) -> Set<StoreRefreshScope> {
        guard events.isEmpty == false else { return [] }
        if events.contains(.fullSync) {
            return StoreRefreshScope.full
        }

        return events.reduce(into: Set<StoreRefreshScope>()) { result, event in
            result.formUnion(scopes(after: event))
        }
    }

    func scopes(after event: StoreInvalidationEvent) -> Set<StoreRefreshScope> {
        switch event {
        case .taskTreeChanged:
            return [.tasks, .rollups, .analytics, .liveActivities]
        case .timerChanged:
            return [.ledgerVisible, .pomodoro, .rollups, .analytics, .liveActivities]
        case .ledgerHistoryChanged:
            return [.ledgerHistory, .rollups, .analytics, .liveActivities]
        case .pomodoroChanged:
            return [.ledgerVisible, .pomodoro, .rollups, .analytics, .liveActivities]
        case .checklistChanged:
            return [.checklist, .rollups, .analytics]
        case .preferencesChanged:
            return [.preferences]
        case .countdownChanged:
            return [.countdown]
        case .fullSync:
            return StoreRefreshScope.full
        }
    }

}
