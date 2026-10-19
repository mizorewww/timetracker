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

    /// Refresh scopes and record identities one committed event invalidates.
    fileprivate var impact: StoreRefreshImpact {
        switch self {
        case let .taskChanged(taskID, ancestorIDs):
            StoreRefreshImpact(
                scopes: [.tasks, .rollups, .analytics],
                directTaskID: taskID,
                ancestorTaskIDs: ancestorIDs
            )
        case let .checklistChanged(taskID, ancestorIDs):
            StoreRefreshImpact(
                scopes: [.checklist, .rollups, .analytics],
                directTaskID: taskID,
                ancestorTaskIDs: ancestorIDs,
                checklistTaskIDs: taskID.map { [$0] } ?? []
            )
        case let .ledgerChanged(taskID, dateInterval, isVisible):
            StoreRefreshImpact(
                scopes: isVisible
                    ? [.ledgerVisible, .pomodoro, .rollups, .analytics]
                    : [.ledgerHistory, .rollups, .analytics],
                directTaskID: taskID,
                ledgerRanges: dateInterval.map { [$0] } ?? []
            )
        case let .pomodoroChanged(_, _, taskID):
            StoreRefreshImpact(
                scopes: [.ledgerVisible, .pomodoro, .rollups, .analytics],
                directTaskID: taskID
            )
        case .preferenceChanged:
            StoreRefreshImpact(scopes: [.preferences])
        case .countdownChanged:
            StoreRefreshImpact(scopes: [.countdown])
        case let .inboxChanged(itemIDs):
            StoreRefreshImpact(scopes: [.inbox], inboxItemIDs: itemIDs)
        case .remoteImportCompleted, .fullSync:
            StoreRefreshImpact(scopes: StoreRefreshScope.full)
        }
    }
}

private nonisolated struct StoreRefreshImpact {
    var scopes: Set<StoreRefreshScope>
    var directTaskID: UUID?
    var ancestorTaskIDs: Set<UUID> = []
    var checklistTaskIDs: Set<UUID> = []
    var ledgerRanges: [StoreInvalidationRange] = []
    var inboxItemIDs: Set<UUID> = []
}

nonisolated struct StoreRefreshPlan: Equatable, Sendable {
    let scopes: Set<StoreRefreshScope>
    /// Direct task IDs plus explicitly affected ancestors.
    let affectedTaskIDs: Set<UUID>
    let directlyAffectedTaskIDs: Set<UUID>
    let explicitlyAffectedAncestorTaskIDs: Set<UUID>
    let directlyAffectedChecklistTaskIDs: Set<UUID>
    let affectedInboxItemIDs: Set<UUID>
    let affectedLedgerRanges: [StoreInvalidationRange]

    init(
        scopes: Set<StoreRefreshScope>,
        directlyAffectedTaskIDs: Set<UUID> = [],
        explicitlyAffectedAncestorTaskIDs: Set<UUID> = [],
        directlyAffectedChecklistTaskIDs: Set<UUID> = [],
        affectedInboxItemIDs: Set<UUID> = [],
        affectedLedgerRanges: [StoreInvalidationRange] = []
    ) {
        self.scopes = scopes
        affectedTaskIDs = directlyAffectedTaskIDs.union(explicitlyAffectedAncestorTaskIDs)
        self.directlyAffectedTaskIDs = directlyAffectedTaskIDs
        self.explicitlyAffectedAncestorTaskIDs = explicitlyAffectedAncestorTaskIDs
        self.directlyAffectedChecklistTaskIDs = directlyAffectedChecklistTaskIDs
        self.affectedInboxItemIDs = affectedInboxItemIDs
        self.affectedLedgerRanges = affectedLedgerRanges
    }

    var refreshTasks: Bool {
        scopes.contains(.tasks)
    }

    var includeLedgerHistory: Bool {
        scopes.contains(.ledgerHistory)
    }

    var refreshLedger: Bool {
        scopes.contains(.ledgerVisible) || includeLedgerHistory
    }

    var refreshPomodoro: Bool {
        scopes.contains(.pomodoro)
    }

    var refreshPreferences: Bool {
        scopes.contains(.preferences)
    }

    var refreshCountdown: Bool {
        scopes.contains(.countdown)
    }

    var refreshChecklist: Bool {
        scopes.contains(.checklist)
    }

    var refreshInbox: Bool {
        scopes.contains(.inbox)
    }

    var refreshRollups: Bool {
        scopes.contains(.rollups) || refreshTasks || refreshLedger || refreshChecklist
    }

    var refreshAnalytics: Bool {
        scopes.contains(.analytics) || refreshTasks || refreshLedger || refreshChecklist
    }

    var validateSelection: Bool {
        refreshTasks || refreshLedger
    }
}

nonisolated struct StoreRefreshPlanner: Sendable {
    func plan(after events: Set<StoreDomainEvent>) -> StoreRefreshPlan {
        var impact = StoreRefreshImpact(scopes: [])
        var directTaskIDs = Set<UUID>()
        for event in events {
            let eventImpact = event.impact
            impact.scopes.formUnion(eventImpact.scopes)
            if let taskID = eventImpact.directTaskID {
                directTaskIDs.insert(taskID)
            }
            impact.ancestorTaskIDs.formUnion(eventImpact.ancestorTaskIDs)
            impact.checklistTaskIDs.formUnion(eventImpact.checklistTaskIDs)
            impact.ledgerRanges += eventImpact.ledgerRanges
            impact.inboxItemIDs.formUnion(eventImpact.inboxItemIDs)
        }
        return StoreRefreshPlan(
            scopes: impact.scopes,
            directlyAffectedTaskIDs: directTaskIDs,
            explicitlyAffectedAncestorTaskIDs: impact.ancestorTaskIDs,
            directlyAffectedChecklistTaskIDs: impact.checklistTaskIDs,
            affectedInboxItemIDs: impact.inboxItemIDs,
            affectedLedgerRanges: impact.ledgerRanges
        )
    }
}
