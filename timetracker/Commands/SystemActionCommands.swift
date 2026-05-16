import Foundation
import SwiftData

@MainActor
struct SystemActionCommandHandler {
    @discardableResult
    func addInboxItem(
        title: String,
        context: ModelContext,
        deviceID: String = DeviceIdentity.current
    ) throws -> UUID? {
        let existingItems = try context.fetch(
            FetchDescriptor<InboxItem>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
            )
        )
        return try InboxCommandHandler()
            .add(title: title, existingItems: existingItems, context: context, deviceID: deviceID)?
            .id
    }

    @discardableResult
    func startTimer(
        taskID: UUID,
        allowParallelTimers: Bool,
        source: TimeSessionSource = .timer,
        context: ModelContext
    ) throws -> UUID? {
        let taskRepository = SwiftDataTaskRepository(context: context)
        guard try taskRepository.task(id: taskID) != nil else {
            throw SystemActionCommandError.taskNotFound
        }

        let timeRepository = SwiftDataTimeTrackingRepository(context: context)
        let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository)
        let activeSegments = try timeRepository.activeSegments()
        if let existing = activeSegments.first(where: { $0.taskID == taskID }) {
            return existing.id
        }

        try TimerCommandHandler().startTask(
            taskID: taskID,
            allowParallelTimers: allowParallelTimers,
            activeSegments: activeSegments,
            pomodoroRuns: try pomodoroRepository.runs(),
            timeRepository: timeRepository,
            context: context,
            source: source
        )

        return try timeRepository.activeSegments().first(where: { $0.taskID == taskID })?.id
    }

    @discardableResult
    func stopTimer(
        taskID: UUID?,
        context: ModelContext
    ) throws -> UUID? {
        let timeRepository = SwiftDataTimeTrackingRepository(context: context)
        let activeSegments = try timeRepository.activeSegments()
        guard let segment = taskID.flatMap({ taskID in
            activeSegments.first { $0.taskID == taskID }
        }) ?? activeSegments.first else {
            return nil
        }

        let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository)
        try TimerCommandHandler().stop(
            segment: segment,
            pomodoroRuns: try pomodoroRepository.runs(),
            timeRepository: timeRepository,
            context: context
        )
        return segment.id
    }
}

enum SystemActionCommandError: LocalizedError, Equatable {
    case taskNotFound

    var errorDescription: String? {
        switch self {
        case .taskNotFound:
            AppStrings.localized("systemAction.error.taskNotFound")
        }
    }
}
