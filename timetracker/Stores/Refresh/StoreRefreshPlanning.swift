import Foundation

nonisolated enum StoreRefreshScope: Hashable, CaseIterable, Sendable {
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

nonisolated struct StoreInvalidationRange: Hashable, Sendable {
    let start: Date
    let end: Date

    init(start: Date, end: Date) {
        // Foundation traps when DateInterval is initialized with a reversed
        // range. Normalize here because invalidations may also describe legacy
        // or remotely imported records that predate current editor validation.
        self.start = min(start, end)
        self.end = max(start, end)
    }

    var dateInterval: DateInterval {
        DateInterval(start: start, end: end)
    }
}

nonisolated enum StoreDomainEvent: Hashable, Sendable {
    case taskChanged(taskID: UUID?, affectedAncestorIDs: Set<UUID>)
    case checklistChanged(taskID: UUID?, affectedAncestorIDs: Set<UUID>)
    case ledgerChanged(taskID: UUID?, dateInterval: StoreInvalidationRange?, isVisible: Bool)
    case pomodoroChanged(runID: UUID?, sessionID: UUID?, taskID: UUID?)
    case preferenceChanged(key: String?)
    case countdownChanged
    case inboxChanged(itemIDs: Set<UUID>)
    case remoteImportCompleted
    case fullSync

    var affectedTaskIDs: Set<UUID> {
        switch self {
        case let .taskChanged(taskID, affectedAncestorIDs),
             let .checklistChanged(taskID, affectedAncestorIDs):
            var ids = affectedAncestorIDs
            if let taskID {
                ids.insert(taskID)
            }
            return ids
        case let .ledgerChanged(taskID, _, _),
             let .pomodoroChanged(_, _, taskID):
            return taskID.map { [$0] } ?? []
        case .preferenceChanged,
             .countdownChanged,
             .inboxChanged,
             .remoteImportCompleted,
             .fullSync:
            return []
        }
    }

    var directlyAffectedTaskIDs: Set<UUID> {
        switch self {
        case let .taskChanged(taskID, _),
             let .checklistChanged(taskID, _),
             let .ledgerChanged(taskID, _, _),
             let .pomodoroChanged(_, _, taskID):
            taskID.map { [$0] } ?? []
        case .preferenceChanged,
             .countdownChanged,
             .inboxChanged,
             .remoteImportCompleted,
             .fullSync:
            []
        }
    }

    var explicitlyAffectedAncestorTaskIDs: Set<UUID> {
        switch self {
        case let .taskChanged(_, ancestorIDs),
             let .checklistChanged(_, ancestorIDs):
            ancestorIDs
        case .ledgerChanged,
             .pomodoroChanged,
             .preferenceChanged,
             .countdownChanged,
             .inboxChanged,
             .remoteImportCompleted,
             .fullSync:
            []
        }
    }

    var directlyAffectedChecklistTaskIDs: Set<UUID> {
        guard case let .checklistChanged(taskID, _) = self else { return [] }
        return taskID.map { [$0] } ?? []
    }

    var affectedLedgerRanges: [StoreInvalidationRange] {
        switch self {
        case let .ledgerChanged(_, dateInterval, _):
            dateInterval.map { [$0] } ?? []
        case .taskChanged,
             .pomodoroChanged,
             .checklistChanged,
             .preferenceChanged,
             .countdownChanged,
             .inboxChanged,
             .remoteImportCompleted,
             .fullSync:
            []
        }
    }

    var affectedInboxItemIDs: Set<UUID> {
        switch self {
        case let .inboxChanged(itemIDs):
            itemIDs
        case .taskChanged,
             .checklistChanged,
             .ledgerChanged,
             .pomodoroChanged,
             .preferenceChanged,
             .countdownChanged,
             .remoteImportCompleted,
             .fullSync:
            []
        }
    }
}

nonisolated struct StoreRefreshPlan: Equatable, Sendable {
    let scopes: Set<StoreRefreshScope>
    let affectedTaskIDs: Set<UUID>
    let directlyAffectedTaskIDs: Set<UUID>
    let explicitlyAffectedAncestorTaskIDs: Set<UUID>
    let directlyAffectedChecklistTaskIDs: Set<UUID>
    let affectedInboxItemIDs: Set<UUID>
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

    init(
        scopes: Set<StoreRefreshScope>,
        affectedTaskIDs: Set<UUID> = [],
        directlyAffectedTaskIDs: Set<UUID> = [],
        explicitlyAffectedAncestorTaskIDs: Set<UUID> = [],
        directlyAffectedChecklistTaskIDs: Set<UUID> = [],
        affectedInboxItemIDs: Set<UUID> = [],
        affectedLedgerRanges: [StoreInvalidationRange] = []
    ) {
        self.scopes = scopes
        self.affectedTaskIDs = affectedTaskIDs
        self.directlyAffectedTaskIDs = directlyAffectedTaskIDs
        self.explicitlyAffectedAncestorTaskIDs = explicitlyAffectedAncestorTaskIDs
        self.directlyAffectedChecklistTaskIDs = directlyAffectedChecklistTaskIDs
        self.affectedInboxItemIDs = affectedInboxItemIDs
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

nonisolated struct StoreRefreshPlanner: Sendable {
    func plan(after events: Set<StoreDomainEvent>) -> StoreRefreshPlan {
        StoreRefreshPlan(
            scopes: scopes(after: events),
            affectedTaskIDs: events.reduce(into: Set<UUID>()) { $0.formUnion($1.affectedTaskIDs) },
            directlyAffectedTaskIDs: events.reduce(into: Set<UUID>()) {
                $0.formUnion($1.directlyAffectedTaskIDs)
            },
            explicitlyAffectedAncestorTaskIDs: events.reduce(into: Set<UUID>()) {
                $0.formUnion($1.explicitlyAffectedAncestorTaskIDs)
            },
            directlyAffectedChecklistTaskIDs: events.reduce(into: Set<UUID>()) {
                $0.formUnion($1.directlyAffectedChecklistTaskIDs)
            },
            affectedInboxItemIDs: events.reduce(into: Set<UUID>()) { $0.formUnion($1.affectedInboxItemIDs) },
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
        case let .ledgerChanged(_, _, isVisible):
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
