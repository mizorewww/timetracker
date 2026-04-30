import Foundation
import Testing
@testable import timetracker

struct CoreRefreshPlannerTests {
    @Test @MainActor
    func refreshPlannerMapsDomainEventsToDomainSizedScopes() {
        let planner = StoreRefreshPlanner()
        let taskID = UUID()
        let range = StoreInvalidationRange(start: Date(timeIntervalSince1970: 1), end: Date(timeIntervalSince1970: 2))

        #expect(planner.scopes(after: [.checklistChanged(taskID: taskID, affectedAncestorIDs: [])]) == [.checklist, .rollups, .analytics])
        #expect(planner.scopes(after: [.taskChanged(taskID: taskID, affectedAncestorIDs: [])]) == [.tasks, .rollups, .analytics, .liveActivities])
        #expect(planner.scopes(after: [.ledgerChanged(taskID: taskID, dateInterval: range, isVisible: true)]) == [.ledgerVisible, .pomodoro, .rollups, .analytics, .liveActivities])
        #expect(planner.scopes(after: [.pomodoroChanged(runID: nil, sessionID: nil, taskID: taskID)]) == [.ledgerVisible, .pomodoro, .rollups, .analytics, .liveActivities])
        #expect(planner.scopes(after: [.ledgerChanged(taskID: taskID, dateInterval: range, isVisible: false)]) == [.ledgerHistory, .rollups, .analytics, .liveActivities])
        #expect(planner.scopes(after: [.preferenceChanged(key: AppPreferenceKey.quickStartTaskIDs.rawValue)]) == [.preferences])
        #expect(planner.scopes(after: [.fullSync]) == StoreRefreshScope.full)
        #expect(planner.scopes(after: [.remoteImportCompleted]) == StoreRefreshScope.full)
        #expect(StoreDomainEvent.checklistChanged(taskID: taskID, affectedAncestorIDs: []).affectedTaskIDs == [taskID])
    }

    @Test @MainActor
    func refreshPlannerCoalescesMultipleDomainEventsWithoutEscalatingToFullRefresh() {
        let taskID = UUID()
        let scopes = StoreRefreshPlanner().scopes(after: [
            .taskChanged(taskID: taskID, affectedAncestorIDs: []),
            .checklistChanged(taskID: taskID, affectedAncestorIDs: []),
            .ledgerChanged(taskID: taskID, dateInterval: nil, isVisible: true)
        ])

        #expect(scopes.contains(.tasks))
        #expect(scopes.contains(.checklist))
        #expect(scopes.contains(.ledgerVisible))
        #expect(scopes.contains(.rollups))
        #expect(scopes.contains(.analytics))
        #expect(scopes.contains(.preferences) == false)
        #expect(scopes != StoreRefreshScope.full)
    }

    @Test @MainActor
    func refreshPlanCentralizesDerivedRefreshRules() {
        let planner = StoreRefreshPlanner()
        let taskID = UUID()
        let ancestorID = UUID()

        let checklistPlan = planner.plan(after: [.checklistChanged(taskID: taskID, affectedAncestorIDs: [ancestorID])])
        #expect(checklistPlan.affectedTaskIDs == [taskID, ancestorID])
        #expect(checklistPlan.affectedLedgerRanges.isEmpty)
        #expect(checklistPlan.refreshChecklist)
        #expect(checklistPlan.refreshRollups)
        #expect(checklistPlan.refreshAnalytics)
        #expect(checklistPlan.refreshLedger == false)
        #expect(checklistPlan.syncLiveActivities == false)

        let timerPlan = planner.plan(after: [.ledgerChanged(taskID: taskID, dateInterval: nil, isVisible: true)])
        #expect(timerPlan.refreshLedger)
        #expect(timerPlan.includeLedgerHistory == false)
        #expect(timerPlan.refreshPomodoro)
        #expect(timerPlan.refreshRollups)
        #expect(timerPlan.refreshAnalytics)
        #expect(timerPlan.syncLiveActivities)

        let range = StoreInvalidationRange(start: Date(timeIntervalSince1970: 1), end: Date(timeIntervalSince1970: 2))
        let historyPlan = planner.plan(after: [
            .ledgerChanged(
                taskID: taskID,
                dateInterval: range,
                isVisible: false
            )
        ])
        #expect(historyPlan.affectedTaskIDs == [taskID])
        #expect(historyPlan.affectedLedgerRanges == [range])
        #expect(historyPlan.refreshLedger)
        #expect(historyPlan.includeLedgerHistory)
        #expect(historyPlan.validateSelection)
    }
}
