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
        let context = SystemActionContextProvider.makeContext()
        try SystemActionCommandHandler().addInboxItem(title: titleText, context: context)
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
        let context = SystemActionContextProvider.makeContext()
        let taskID = try task.uuid()
        try SystemActionCommandHandler().startTimer(
            taskID: taskID,
            allowParallelTimers: true,
            context: context
        )
        return .result()
    }
}

struct StopTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Timer"
    static var description = IntentDescription("Stop the current Time Tracker timer.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = SystemActionContextProvider.makeContext()
        try SystemActionCommandHandler().stopTimer(taskID: nil, context: context)
        return .result()
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
        let descriptor = FetchDescriptor<TaskNode>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        let tasks = try context.fetch(descriptor)
        return tasks.map { task in
            TaskNodeAppEntity(
                id: task.id.uuidString,
                title: task.title,
                path: task.path
            )
        }
    }
}

@MainActor
enum SystemActionContextProvider {
    static func makeContext() -> ModelContext {
        ModelContext(timetrackerApp.makeModelContainer())
    }
}
