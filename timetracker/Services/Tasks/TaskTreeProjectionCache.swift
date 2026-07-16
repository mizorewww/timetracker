import Foundation

/// Small revision-aware read-through cache shared by the task management and
/// sidebar projections. It retains IDs/value models only and bounds each LRU so
/// a long sequence of expansion states or search queries cannot grow memory.
struct TaskTreeProjectionCache {
    private struct HierarchyEntry {
        let expandedTaskIDs: Set<UUID>
        let projection: TaskTreeProjection
    }

    private struct SearchEntry {
        let query: String
        let projection: TaskTreeSearchProjection
    }

    private let capacity: Int
    private var revision: UInt64?
    private var hierarchyEntries: [HierarchyEntry] = []
    private var searchEntries: [SearchEntry] = []

    private(set) var hierarchyBuildCount = 0
    private(set) var searchBuildCount = 0
    private(set) var invalidationCount = 0

    init(capacity: Int = 4) {
        self.capacity = Swift.max(1, capacity)
    }

    var hierarchyEntryCount: Int {
        hierarchyEntries.count
    }

    var searchEntryCount: Int {
        searchEntries.count
    }

    mutating func projection(
        readIndex: TaskTreeReadIndex,
        revision: UInt64,
        expandedTaskIDs: Set<UUID>
    ) -> TaskTreeProjection {
        prepare(for: revision)
        if let index = hierarchyEntries.firstIndex(where: { $0.expandedTaskIDs == expandedTaskIDs }) {
            let entry = hierarchyEntries.remove(at: index)
            hierarchyEntries.append(entry)
            return entry.projection
        }

        let projection = readIndex.projection(expandedTaskIDs: expandedTaskIDs)
        hierarchyBuildCount += 1
        hierarchyEntries.append(
            HierarchyEntry(expandedTaskIDs: expandedTaskIDs, projection: projection)
        )
        if hierarchyEntries.count > capacity {
            hierarchyEntries.removeFirst(hierarchyEntries.count - capacity)
        }
        return projection
    }

    mutating func searchProjection(
        readIndex: TaskTreeReadIndex,
        revision: UInt64,
        query: String
    ) -> TaskTreeSearchProjection {
        prepare(for: revision)
        if let index = searchEntries.firstIndex(where: { $0.query == query }) {
            let entry = searchEntries.remove(at: index)
            searchEntries.append(entry)
            return entry.projection
        }

        let projection = readIndex.searchProjection(matching: query)
        searchBuildCount += 1
        searchEntries.append(SearchEntry(query: query, projection: projection))
        if searchEntries.count > capacity {
            searchEntries.removeFirst(searchEntries.count - capacity)
        }
        return projection
    }

    private mutating func prepare(for requestedRevision: UInt64) {
        guard revision != requestedRevision else { return }
        if revision != nil {
            invalidationCount += 1
        }
        revision = requestedRevision
        hierarchyEntries.removeAll(keepingCapacity: true)
        searchEntries.removeAll(keepingCapacity: true)
    }
}
