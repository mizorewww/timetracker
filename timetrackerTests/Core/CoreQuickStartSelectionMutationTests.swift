import Foundation
import Testing
@testable import timetracker

struct CoreQuickStartSelectionMutationTests {
    @Test
    func addingSelectionAppendsOnceAndPreservesPinnedOrder() {
        let first = UUID()
        let added = UUID()

        #expect(
            OrderedTaskIDSelectionMutation.adding(added, to: [first]) ==
                [first, added]
        )
        #expect(
            OrderedTaskIDSelectionMutation.adding(added, to: [first, added]) ==
                [first, added]
        )
    }

    @Test
    func removingSelectionPreservesTheOrderOfEveryOtherPinnedTask() {
        let first = UUID()
        let removed = UUID()
        let last = UUID()

        #expect(
            OrderedTaskIDSelectionMutation.removing(
                removed,
                from: [first, removed, last]
            ) == [first, last]
        )
    }

    @Test
    func deletionUsesVisibleIdentityWhenAStaleSelectionPrecedesTheRow() {
        let stale = UUID()
        let visible = UUID()

        let result = OrderedTaskIDSelectionMutation.removingVisibleSelections(
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

        let result = OrderedTaskIDSelectionMutation.removingVisibleSelections(
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

        let result = OrderedTaskIDSelectionMutation.removingVisibleSelections(
            at: IndexSet([0, 2]),
            visibleIDs: [first, middle, last],
            from: [first, stale, middle, last]
        )

        #expect(result == [stale, middle])
    }

    @Test
    func reorderUsesVisibleIdentityAndPreservesHiddenSelectionSlots() {
        let staleBefore = UUID()
        let first = UUID()
        let staleBetween = UUID()
        let second = UUID()
        let third = UUID()

        let result = OrderedTaskIDSelectionMutation.movingVisibleSelections(
            fromOffsets: IndexSet(integer: 2),
            toOffset: 1,
            visibleIDs: [first, second, third],
            in: [staleBefore, first, staleBetween, second, third]
        )

        #expect(result == [staleBefore, first, staleBetween, third, second])
    }

    @Test
    func invalidVisibleReorderLeavesSelectionsUnchanged() {
        let first = UUID()
        let second = UUID()
        let missing = UUID()
        let selected = [first, second]

        #expect(
            OrderedTaskIDSelectionMutation.movingVisibleSelections(
                fromOffsets: IndexSet(integer: 1),
                toOffset: 0,
                visibleIDs: [first, missing],
                in: selected
            ) == selected
        )
        #expect(
            OrderedTaskIDSelectionMutation.movingVisibleSelections(
                fromOffsets: IndexSet(integer: 2),
                toOffset: 0,
                visibleIDs: [first, second],
                in: selected
            ) == selected
        )
    }

    @Test
    func toggleAndBulkRemovalReuseTheSameOrderedSelectionSemantics() {
        let first = UUID()
        let second = UUID()
        let added = UUID()

        #expect(
            OrderedTaskIDSelectionMutation.toggling(
                added,
                in: [first, second]
            ) == [first, second, added]
        )
        #expect(
            OrderedTaskIDSelectionMutation.toggling(
                first,
                in: [first, second]
            ) == [second]
        )
        #expect(
            OrderedTaskIDSelectionMutation.removing(
                [first, added],
                from: [first, second, added]
            ) == [second]
        )
    }
}
