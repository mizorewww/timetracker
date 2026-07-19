import Foundation
import Testing
@testable import timetracker

struct CoreQuickStartSelectionMutationTests {
    @Test
    func addingSelectionAppendsOnceAndPreservesPinnedOrder() {
        let first = UUID()
        let added = UUID()

        #expect(
            QuickStartSelectionMutation.adding(added, to: [first]) ==
                [first, added]
        )
        #expect(
            QuickStartSelectionMutation.adding(added, to: [first, added]) ==
                [first, added]
        )
    }

    @Test
    func removingSelectionPreservesTheOrderOfEveryOtherPinnedTask() {
        let first = UUID()
        let removed = UUID()
        let last = UUID()

        #expect(
            QuickStartSelectionMutation.removing(
                removed,
                from: [first, removed, last]
            ) == [first, last]
        )
    }

    @Test
    func deletionUsesVisibleIdentityWhenAStaleSelectionPrecedesTheRow() {
        let stale = UUID()
        let visible = UUID()

        let result = QuickStartSelectionMutation.removingVisibleSelections(
            at: IndexSet(integer: 0),
            visibleIDs: [visible],
            from: [stale, visible]
        )

        #expect(result == [stale])
    }

    @Test
    func deletionPreservesInterleavedSelectionsAndTheirOrder() {
        let first = UUID()
        let stale = UUID()
        let last = UUID()

        let result = QuickStartSelectionMutation.removingVisibleSelections(
            at: IndexSet(integer: 1),
            visibleIDs: [first, last],
            from: [first, stale, last]
        )

        #expect(result == [first, stale])
    }

    @Test
    func multipleVisibleOffsetsRemoveOnlyTheirMatchingIdentities() {
        let first = UUID()
        let stale = UUID()
        let middle = UUID()
        let last = UUID()

        let result = QuickStartSelectionMutation.removingVisibleSelections(
            at: IndexSet([0, 2]),
            visibleIDs: [first, middle, last],
            from: [first, stale, middle, last]
        )

        #expect(result == [stale, middle])
    }
}
