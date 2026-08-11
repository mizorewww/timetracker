import Testing
@testable import timetracker

struct SystemProjectionSchedulerTests {
    @Test
    @MainActor
    func eventRoutingMatchesEachSurfaceDependency() {
        let allSinks = Set(CommittedMutationSystemProjectionSink.allCases)
        let syncOnly: Set<CommittedMutationSystemProjectionSink> = [
            .syncSnapshot,
        ]

        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: [.taskChanged(taskID: nil, affectedAncestorIDs: [])]
        ) == allSinks)
        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: [.remoteImportCompleted]
        ) == allSinks)
        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: [.preferenceChanged(key: nil)]
        ) == [.syncSnapshot, .watch])
        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: [.checklistChanged(taskID: nil, affectedAncestorIDs: [])]
        ) == syncOnly)
        #expect(CommittedMutationSystemProjectionScheduler.targetedSinks(
            for: [.countdownChanged, .inboxChanged(itemIDs: [])]
        ) == syncOnly)
    }
}
