import Foundation
import Testing
@testable import timetracker

struct CoreQuickStartSelectionMutationTests {
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
