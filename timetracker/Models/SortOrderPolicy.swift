import Foundation

/// Persisted `sortOrder` values are spaced so an item can later be placed
/// between two neighbours without renumbering the whole list.
nonisolated enum SortOrderPolicy {
    static let step: Double = 10

    static func after(_ last: Double?) -> Double {
        (last ?? 0) + step
    }

    static func position(_ index: Int) -> Double {
        Double(index + 1) * step
    }
}

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
