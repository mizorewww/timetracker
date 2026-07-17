import AppIntents
import Foundation
import SwiftData

struct AddInboxItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Inbox Item"
    static var description = IntentDescription("Capture a loose item in Time Tracker Inbox.")
    static var openAppWhenRun = false

    @Parameter(title: "Title")
    var titleText: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let outcome = try SystemActionCommandHandler().addInboxItem(
            title: titleText,
            container: SystemActionContextProvider.container
        )
        if outcome.didMutate {
            let postCommitContext = SystemActionContextProvider.makeContext()
            SystemActionPostCommitEffects().apply(
                context: postCommitContext,
                events: outcome.events
            )
        }
        return .result()
    }
}

struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Timer"
    static var description = IntentDescription("Start tracking time for a Time Tracker task.")
    static var openAppWhenRun = false

    @Parameter(title: "Task")
    var task: TaskNodeAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let taskID = try task.uuid()
        let outcome = try SystemActionCommandHandler().startTimerMutation(
            taskID: taskID,
            source: .shortcut,
            container: SystemActionContextProvider.container
        )
        let events = outcome.events
        if events.isEmpty == false {
            let postCommitContext = SystemActionContextProvider.makeContext()
            SystemActionPostCommitEffects().apply(
                context: postCommitContext,
                events: events
            )
        }
        return .result()
    }
}

struct StopTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Timer"
    static var description = IntentDescription("Stop a specific running Time Tracker timer.")
    static var openAppWhenRun = false

    @Parameter(title: "Timer")
    var timer: ActiveTimerAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let targetID = try timer.uuid()
        let outcome = try SystemActionCommandHandler().stopTimerMutation(
            segmentID: targetID,
            container: SystemActionContextProvider.container
        )
        let events = outcome.events
        if outcome.subjectSegmentID == targetID, events.isEmpty == false {
            let postCommitContext = SystemActionContextProvider.makeContext()
            SystemActionPostCommitEffects().apply(
                context: postCommitContext,
                events: events
            )
        }
        return .result()
    }
}

struct ActiveTimerAppEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Running Timer")
    static var defaultQuery = ActiveTimerEntityQuery()

    let id: String
    let title: String
    let path: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: path.isEmpty ? nil : "\(path)"
        )
    }

    func uuid() throws -> UUID {
        guard let uuid = UUID(uuidString: id) else {
            throw SystemActionCommandError.taskNotFound
        }
        return uuid
    }
}

struct ActiveTimerEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [ActiveTimerAppEntity.ID]) async throws -> [ActiveTimerAppEntity] {
        let ids = Set(identifiers)
        return try fetchTimerEntities().filter { ids.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ActiveTimerAppEntity] {
        try fetchTimerEntities()
    }

    @MainActor
    private func fetchTimerEntities() throws -> [ActiveTimerAppEntity] {
        let context = SystemActionContextProvider.makeContext()
        let activeSegments = try SwiftDataTimeTrackingRepository(context: context).activeSegments()
        let tasks = try SwiftDataTaskRepository(context: context).allNodes()
        let taskByID = tasks.reduce(into: [UUID: TaskNode]()) { result, task in
            result[task.id] = task
        }
        let parentPathByID = TaskTreeService().indexes(tasks: tasks).taskParentPathByID

        return activeSegments.compactMap { segment in
            guard let task = taskByID[segment.taskID] else { return nil }
            return ActiveTimerAppEntity(
                id: segment.id.uuidString,
                title: task.title,
                path: parentPathByID[task.id] ?? ""
            )
        }
    }
}

struct TimeTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddInboxItemIntent(),
            phrases: [
                "Add inbox item in \(.applicationName)",
                "Capture in \(.applicationName)"
            ],
            shortTitle: "Add Inbox Item",
            systemImageName: "tray.and.arrow.down"
        )

        AppShortcut(
            intent: StartTimerIntent(),
            phrases: [
                "Start timer in \(.applicationName)",
                "Track time in \(.applicationName)"
            ],
            shortTitle: "Start Timer",
            systemImageName: "play.fill"
        )

        AppShortcut(
            intent: StopTimerIntent(),
            phrases: [
                "Stop timer in \(.applicationName)",
                "Stop tracking in \(.applicationName)"
            ],
            shortTitle: "Stop Timer",
            systemImageName: "stop.fill"
        )
    }
}

struct TaskNodeAppEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Task")
    static var defaultQuery = TaskNodeEntityQuery()

    let id: String
    let title: String
    let path: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: path.isEmpty ? nil : "\(path)"
        )
    }

    func uuid() throws -> UUID {
        guard let uuid = UUID(uuidString: id) else {
            throw SystemActionCommandError.taskNotFound
        }
        return uuid
    }
}

struct TaskNodeEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [TaskNodeAppEntity.ID]) async throws -> [TaskNodeAppEntity] {
        let ids = Set(identifiers.compactMap(UUID.init(uuidString:)))
        guard ids.isEmpty == false else { return [] }
        return try fetchTaskEntities().filter { entity in
            guard let id = UUID(uuidString: entity.id) else { return false }
            return ids.contains(id)
        }
    }

    @MainActor
    func entities(matching string: String) async throws -> [TaskNodeAppEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.isEmpty == false else {
            return try await suggestedEntities()
        }
        return try fetchTaskEntities().filter {
            $0.title.lowercased().contains(query) || $0.path.lowercased().contains(query)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [TaskNodeAppEntity] {
        try Array(fetchTaskEntities().prefix(12))
    }

    @MainActor
    private func fetchTaskEntities() throws -> [TaskNodeAppEntity] {
        let context = SystemActionContextProvider.makeContext()
        let tasks = try SwiftDataTaskRepository(context: context)
            .allNodes()
        let trackableTaskIDs = TaskTrackingAvailabilityService().trackableTaskIDs(tasks: tasks)
        let trackableTasks = tasks.filter { trackableTaskIDs.contains($0.id) }
        let parentPathByID = TaskTreeService().indexes(tasks: trackableTasks).taskParentPathByID
        return trackableTasks.map { task in
            TaskNodeAppEntity(
                id: task.id.uuidString,
                title: task.title,
                path: parentPathByID[task.id] ?? ""
            )
        }
    }
}

@MainActor
enum SystemActionContextProvider {
    static var container: ModelContainer {
        timetrackerApp.applicationModelContainer
    }

    static func makeContext() -> ModelContext {
        ModelContext(container)
    }
}
