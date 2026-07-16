import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskTreeReadIndexTests {
    @Test @MainActor
    func indexedProjectionMatchesExistingHierarchySemanticsAndKeepsStableIdentity() throws {
        let service = TaskTreeService()
        let category = TaskCategory(title: "Work", deviceID: "test", sortOrder: 10)
        let root = TaskNode(title: "Project", parentID: nil, deviceID: "test", sortOrder: 10)
        let child = TaskNode(title: "Research", parentID: root.id, deviceID: "test", sortOrder: 10)
        child.notes = "Interview notes"
        let grandchild = TaskNode(title: "Transcript", parentID: child.id, deviceID: "test", sortOrder: 10)
        let uncategorized = TaskNode(title: "Errands", parentID: nil, deviceID: "test", sortOrder: 20)
        let archived = TaskNode(title: "Archived", parentID: nil, deviceID: "test", sortOrder: 30)
        archived.status = .archived
        let hiddenChild = TaskNode(title: "Hidden", parentID: archived.id, deviceID: "test")
        let tasks = [root, child, grandchild, uncategorized, archived, hiddenChild]
        let indexes = service.indexes(tasks: tasks)
        let eligibility = TaskTrackingAvailabilityService().eligibility(tasks: tasks)
        let categoryByRoot = [root.id: category.id]
        let readIndex = service.readIndex(
            indexes: indexes,
            visibleTaskIDs: eligibility.visibleTaskIDs,
            categories: [category],
            categoryIDByRootTaskID: categoryByRoot
        )
        let expandedTaskIDs: Set<UUID> = [root.id, child.id]

        let legacyProjection = service.categorySections(
            rootTasks: (indexes.childrenByParentID[nil] ?? []).filter {
                eligibility.visibleTaskIDs.contains($0.id)
            },
            categories: [category],
            categoryIDByRootTaskID: categoryByRoot
        ).map { section in
            TaskTreeVisibleSectionModel(
                id: section.id,
                categoryID: section.categoryID,
                title: section.title,
                iconName: section.iconName,
                colorHex: section.colorHex,
                includesInForecast: section.includesInForecast,
                rows: TaskTreeFlattener.visibleRows(
                    rootTasks: section.rootTasks,
                    children: { task in
                        (indexes.childrenByParentID[task.id] ?? []).filter {
                            eligibility.visibleTaskIDs.contains($0.id)
                        }
                    },
                    expandedTaskIDs: expandedTaskIDs
                )
            )
        }
        let projection = readIndex.projection(expandedTaskIDs: expandedTaskIDs)

        #expect(projection.sections == legacyProjection)
        #expect(projection.sections.map(\.id) == ["category-\(category.id.uuidString)", "uncategorized"])
        #expect(projection.sections.flatMap(\.rows).map(\.id) == [
            root.id, child.id, grandchild.id, uncategorized.id
        ])
        #expect(projection.sections[0].rows.map(\.childCount) == [1, 1, 0])
        #expect(readIndex.visibleTaskCount == 4)
        #expect(readIndex.visibleChildCount(for: archived.id) == 0)
        #expect(readIndex.searchProjection(matching: "project / research").taskIDs == [child.id, grandchild.id])
        #expect(readIndex.searchProjection(matching: "interview").taskIDs == [child.id])

        let rebuilt = service.readIndex(
            indexes: service.indexes(tasks: Array(tasks.reversed())),
            visibleTaskIDs: eligibility.visibleTaskIDs,
            categories: [category],
            categoryIDByRootTaskID: categoryByRoot
        ).projection(expandedTaskIDs: expandedTaskIDs)
        #expect(rebuilt.sections.flatMap(\.rows).map(\.id) == projection.sections.flatMap(\.rows).map(\.id))
    }

    @Test @MainActor
    func projectionCacheReusesRequestsBoundsEntriesAndInvalidatesByOwnedRevision() {
        let root = TaskNode(title: "Root", parentID: nil, deviceID: "test")
        let child = TaskNode(title: "Needle", parentID: root.id, deviceID: "test")
        let service = TaskTreeService()
        let tasks = [root, child]
        let indexes = service.indexes(tasks: tasks)
        let eligibility = TaskTrackingAvailabilityService().eligibility(tasks: tasks)
        let readIndex = service.readIndex(
            indexes: indexes,
            visibleTaskIDs: eligibility.visibleTaskIDs,
            categories: [],
            categoryIDByRootTaskID: [:]
        )
        var cache = TaskTreeProjectionCache(capacity: 2)

        let first = cache.projection(readIndex: readIndex, revision: 7, expandedTaskIDs: [])
        let repeated = cache.projection(readIndex: readIndex, revision: 7, expandedTaskIDs: [])
        #expect(first == repeated)
        #expect(cache.hierarchyBuildCount == 1)

        _ = cache.projection(readIndex: readIndex, revision: 7, expandedTaskIDs: [root.id])
        _ = cache.projection(readIndex: readIndex, revision: 7, expandedTaskIDs: [child.id])
        #expect(cache.hierarchyBuildCount == 3)
        #expect(cache.hierarchyEntryCount == 2)
        _ = cache.projection(readIndex: readIndex, revision: 7, expandedTaskIDs: [root.id])
        #expect(cache.hierarchyBuildCount == 3)

        let search = cache.searchProjection(readIndex: readIndex, revision: 7, query: "needle")
        let repeatedSearch = cache.searchProjection(readIndex: readIndex, revision: 7, query: "needle")
        #expect(search == repeatedSearch)
        #expect(search.taskIDs == [child.id])
        #expect(cache.searchBuildCount == 1)
        _ = cache.searchProjection(readIndex: readIndex, revision: 7, query: "root")
        _ = cache.searchProjection(readIndex: readIndex, revision: 7, query: "absent")
        #expect(cache.searchEntryCount == 2)

        _ = cache.projection(readIndex: readIndex, revision: 8, expandedTaskIDs: [root.id])
        #expect(cache.invalidationCount == 1)
        #expect(cache.hierarchyBuildCount == 4)
        #expect(cache.hierarchyEntryCount == 1)
        #expect(cache.searchEntryCount == 0)
    }

    @Test @MainActor
    func storeOwnsSemanticInvalidationAndIgnoresUnrelatedRefreshes() {
        let store = makeTestStore()
        let root = TaskNode(title: "Root", parentID: nil, deviceID: "test")
        store.tasks = [root]
        let initialRevision = store.taskTreeReadIndexRevision
        _ = store.taskTreeSections(expandedTaskIDs: [])
        let initialBuildCount = store.taskTreeProjectionCache.hierarchyBuildCount

        store.tasks = [root]
        store.activeSegments = []
        _ = store.taskTreeSections(expandedTaskIDs: [])
        #expect(store.taskTreeReadIndexRevision == initialRevision)
        #expect(store.taskTreeProjectionCache.hierarchyBuildCount == initialBuildCount)

        let child = TaskNode(title: "Child", parentID: root.id, deviceID: "test")
        store.tasks = [root, child]
        #expect(store.taskTreeReadIndexRevision == initialRevision + 1)
        let expanded = store.taskTreeSections(expandedTaskIDs: [root.id])
        #expect(expanded.flatMap(\.rows).map(\.taskID) == [root.id, child.id])
        #expect(store.taskTreeProjectionCache.hierarchyBuildCount == initialBuildCount + 1)
        #expect(store.taskTreeProjectionCache.invalidationCount == 1)

        let category = TaskCategory(title: "Work", deviceID: "test")
        store.taskCategories = [category]
        #expect(store.taskTreeReadIndexRevision == initialRevision + 2)
        _ = store.taskTreeSections(expandedTaskIDs: [root.id])
        #expect(store.taskTreeProjectionCache.invalidationCount == 2)

        let assignment = TaskCategoryAssignment(
            taskID: root.id,
            categoryID: category.id,
            deviceID: "test"
        )
        store.taskCategoryAssignments = [assignment]
        #expect(store.taskTreeReadIndexRevision == initialRevision + 3)
        let categorized = store.taskTreeSections(expandedTaskIDs: [root.id])
        #expect(categorized.map(\.id) == ["category-\(category.id.uuidString)"])
        #expect(store.taskTreeProjectionCache.invalidationCount == 3)
    }

    @Test @MainActor
    func fiveThousandNodeProjectionUsesOneChildLookupPerVisibleTaskAndCachesSearch() throws {
        var tasks: [TaskNode] = []
        tasks.reserveCapacity(5_000)
        var parentID: UUID?
        for index in 0..<5_000 {
            let task = TaskNode(title: "Level \(index)", parentID: parentID, deviceID: "test")
            tasks.append(task)
            parentID = task.id
        }
        let service = TaskTreeService()
        let indexes = service.indexes(tasks: tasks)
        let eligibility = TaskTrackingAvailabilityService().eligibility(tasks: tasks)
        let readIndex = service.readIndex(
            indexes: indexes,
            visibleTaskIDs: eligibility.visibleTaskIDs,
            categories: [],
            categoryIDByRootTaskID: [:]
        )
        var cache = TaskTreeProjectionCache()
        let expandedTaskIDs = Set(tasks.map(\.id))

        let projection = cache.projection(
            readIndex: readIndex,
            revision: 1,
            expandedTaskIDs: expandedTaskIDs
        )
        #expect(projection.operationCounts.visitedTaskCount == tasks.count)
        #expect(projection.operationCounts.childBucketLookupCount == tasks.count)
        #expect(projection.sections.flatMap(\.rows).count == tasks.count)
        _ = cache.projection(readIndex: readIndex, revision: 1, expandedTaskIDs: expandedTaskIDs)
        #expect(cache.hierarchyBuildCount == 1)

        let search = cache.searchProjection(readIndex: readIndex, revision: 1, query: "Level 4999")
        let lastTask = try #require(tasks.last)
        #expect(search.inspectedTaskCount == tasks.count)
        #expect(search.taskIDs == [lastTask.id])
        _ = cache.searchProjection(readIndex: readIndex, revision: 1, query: "Level 4999")
        #expect(cache.searchBuildCount == 1)
    }

    @Test
    func swiftUITreeSurfacesDoNotReintroduceWholeTreeOrPerRowFiltering() throws {
        let tasksViewSource = try sourceText(
            "timetracker/Features/Tasks/Management/TasksViews.swift"
        )
        let managementRowSource = try sourceText(
            "timetracker/Features/Tasks/Management/TaskManagementRowViews.swift"
        )
        let sidebarSource = try sourceText(
            "timetracker/Features/Sidebar/SidebarTaskTreeViews.swift"
        )
        let readModelSource = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+TaskReadModels.swift"
        )

        #expect(tasksViewSource.contains("store.taskTreeSections(expandedTaskIDs:"))
        #expect(tasksViewSource.contains("store.taskSearchResults(matching: query)"))
        #expect(tasksViewSource.contains("store.tasks.filter") == false)
        #expect(managementRowSource.contains("store.children(of: task).count") == false)
        #expect(sidebarSource.contains("store.children(of: task).count") == false)
        #expect(readModelSource.contains("taskTreeProjectionCache.projection("))
        #expect(readModelSource.contains("taskTreeProjectionCache.searchProjection("))
    }
}
