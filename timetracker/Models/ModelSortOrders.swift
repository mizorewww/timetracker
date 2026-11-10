import Foundation

nonisolated extension Sequence {
    /// Sorts by a key read once per element. Reading SwiftData model
    /// properties is costly, so a comparator that reads them in every
    /// comparison dominates sorting a large fetch.
    func sorted<Key>(
        byKey key: (Element) -> Key,
        by areInIncreasingOrder: (Key, Key) -> Bool
    ) -> [Element] {
        map { (key: key($0), element: $0) }
            .sorted { areInIncreasingOrder($0.key, $1.key) }
            .map(\.element)
    }
}

/// Orders for a date with a stable identity tie-break.
nonisolated enum DatedIdentityOrder {
    static func oldestFirst(_ lhs: (Date, UUID), _ rhs: (Date, UUID)) -> Bool {
        lhs < rhs
    }

    static func newestFirst(_ lhs: (Date, UUID), _ rhs: (Date, UUID)) -> Bool {
        lhs.0 != rhs.0 ? lhs.0 > rhs.0 : lhs.1 < rhs.1
    }
}

extension TimeSegment {
    /// Canonical ledger order key, sorted with `DatedIdentityOrder.oldestFirst`.
    var startOrderKey: (Date, UUID) {
        (startedAt, id)
    }
}

extension TimeSession {
    /// Session list order key, sorted with `DatedIdentityOrder.newestFirst`.
    var startOrderKey: (Date, UUID) {
        (startedAt, id)
    }
}

extension PomodoroRun {
    /// Run list order key, sorted with `DatedIdentityOrder.newestFirst`.
    var creationOrderKey: (Date, UUID) {
        (createdAt, id)
    }
}

extension TaskNode {
    /// Siblings by position, then creation, then identity; sorted with `<`.
    var siblingOrderKey: (Double, Date, UUID) {
        (sortOrder, createdAt, id)
    }

    /// Shallower tasks first, then sibling order; sorted with `<`.
    var hierarchyOrderKey: (Int, Double, Date, UUID) {
        (depth, sortOrder, createdAt, id)
    }
}
