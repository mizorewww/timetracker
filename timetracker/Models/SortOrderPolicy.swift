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
