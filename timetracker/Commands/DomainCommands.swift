import Foundation
import SwiftData

@MainActor
struct TimerCommandHandler {
    private let pomodoroCommandHandler = PomodoroCommandHandler()

    func startTask(
        taskID: UUID,
        allowParallelTimers: Bool,
        activeSegments: [TimeSegment],
        pausedSessions: [TimeSession],
        pomodoroRuns: [PomodoroRun],
        timeRepository: TimeTrackingRepository,
        context: ModelContext?
    ) throws {
        if activeSegments.contains(where: { $0.taskID == taskID && $0.endedAt == nil && $0.deletedAt == nil }) {
            return
        }
        if allowParallelTimers == false {
            try pauseOtherActiveSegments(
                excluding: taskID,
                activeSegments: activeSegments,
                pomodoroRuns: pomodoroRuns,
                timeRepository: timeRepository,
                context: context
            )
        }
        if let pausedSession = pausedSessions.first(where: { $0.taskID == taskID && $0.endedAt == nil && $0.deletedAt == nil }) {
            _ = try ResumeSessionUseCase(repository: timeRepository).execute(sessionID: pausedSession.id)
            try pomodoroCommandHandler.resumeIfNeeded(sessionID: pausedSession.id, runs: pomodoroRuns, context: context)
            return
        }
        _ = try StartTaskUseCase(repository: timeRepository).execute(taskID: taskID, source: .timer)
    }

    func stop(segment: TimeSegment, pomodoroRuns: [PomodoroRun], timeRepository: TimeTrackingRepository, context: ModelContext?) throws {
        try StopSegmentUseCase(repository: timeRepository).execute(segmentID: segment.id)
        try pomodoroCommandHandler.cancelIfNeeded(sessionID: segment.sessionID, runs: pomodoroRuns, context: context)
    }

    func pause(segment: TimeSegment, pomodoroRuns: [PomodoroRun], timeRepository: TimeTrackingRepository, context: ModelContext?) throws {
        try PauseSessionUseCase(repository: timeRepository).execute(sessionID: segment.sessionID)
        try pomodoroCommandHandler.interruptIfNeeded(sessionID: segment.sessionID, runs: pomodoroRuns, context: context)
    }

    func resume(session: TimeSession, pomodoroRuns: [PomodoroRun], timeRepository: TimeTrackingRepository, context: ModelContext?) throws {
        _ = try ResumeSessionUseCase(repository: timeRepository).execute(sessionID: session.id)
        try pomodoroCommandHandler.resumeIfNeeded(sessionID: session.id, runs: pomodoroRuns, context: context)
    }

    func stop(session: TimeSession, pomodoroRuns: [PomodoroRun], timeRepository: TimeTrackingRepository, context: ModelContext?) throws {
        try StopSessionUseCase(repository: timeRepository).execute(sessionID: session.id)
        try pomodoroCommandHandler.cancelIfNeeded(sessionID: session.id, runs: pomodoroRuns, context: context)
    }

    func pauseOtherActiveSegments(
        excluding taskID: UUID,
        activeSegments: [TimeSegment],
        pomodoroRuns: [PomodoroRun],
        timeRepository: TimeTrackingRepository,
        context: ModelContext?
    ) throws {
        for segment in activeSegments where segment.taskID != taskID {
            try PauseSessionUseCase(repository: timeRepository).execute(sessionID: segment.sessionID)
            try pomodoroCommandHandler.interruptIfNeeded(sessionID: segment.sessionID, runs: pomodoroRuns, context: context)
        }
    }
}

@MainActor
struct TaskDraftCommandHandler {
    @discardableResult
    func save(
        draft: TaskEditorDraft,
        sanitizedTitle: String,
        taskRepository: TaskRepository,
        saveChecklistDrafts: ([ChecklistEditorDraft], UUID) throws -> Void
    ) throws -> UUID {
        if let taskID = draft.taskID {
            try update(taskID: taskID, draft: draft, title: sanitizedTitle, repository: taskRepository)
            try saveChecklistDrafts(draft.checklistItems, taskID)
            return taskID
        }

        let task = try CreateTaskUseCase(repository: taskRepository).execute(
            title: sanitizedTitle,
            parentID: draft.parentID,
            colorHex: draft.colorHex,
            iconName: draft.iconName
        )
        try update(taskID: task.id, draft: draft, title: sanitizedTitle, repository: taskRepository)
        try saveChecklistDrafts(draft.checklistItems, task.id)
        return task.id
    }

    func archive(taskID: UUID, repository: TaskRepository) throws {
        try ArchiveTaskUseCase(repository: repository).execute(taskID: taskID)
    }

    func setStatus(_ status: TaskStatus, taskID: UUID, repository: TaskRepository) throws {
        try SetTaskStatusUseCase(repository: repository).execute(taskID: taskID, status: status)
    }

    func softDelete(taskID: UUID, repository: TaskRepository) throws {
        try SoftDeleteTaskUseCase(repository: repository).execute(taskID: taskID)
    }

    private func update(taskID: UUID, draft: TaskEditorDraft, title: String, repository: TaskRepository) throws {
        try UpdateTaskUseCase(repository: repository).execute(
            taskID: taskID,
            title: title,
            status: draft.status,
            parentID: draft.parentID,
            colorHex: draft.colorHex,
            iconName: draft.iconName,
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            estimatedSeconds: draft.estimatedMinutes.map { $0 * 60 },
            dueAt: draft.hasDueDate ? draft.dueAt : nil
        )
    }
}

@MainActor
struct PomodoroCommandHandler {
    func start(
        taskID: UUID,
        focusSeconds: Int,
        breakSeconds: Int,
        targetRounds: Int,
        allowParallelTimers: Bool,
        activeSegments: [TimeSegment],
        pomodoroRuns: [PomodoroRun],
        timeRepository: TimeTrackingRepository,
        pomodoroRepository: PomodoroRepository,
        context: ModelContext?
    ) throws -> PomodoroRun {
        if allowParallelTimers == false {
            try TimerCommandHandler().pauseOtherActiveSegments(
                excluding: taskID,
                activeSegments: activeSegments,
                pomodoroRuns: pomodoroRuns,
                timeRepository: timeRepository,
                context: context
            )
        }
        return try StartPomodoroUseCase(repository: pomodoroRepository).execute(
            taskID: taskID,
            focusSeconds: focusSeconds,
            breakSeconds: breakSeconds,
            targetRounds: targetRounds
        )
    }

    func complete(run: PomodoroRun, repository: PomodoroRepository) throws {
        try CompletePomodoroFocusUseCase(repository: repository).execute(runID: run.id)
    }

    func cancel(run: PomodoroRun, repository: PomodoroRepository) throws {
        try CancelPomodoroUseCase(repository: repository).execute(runID: run.id)
    }

    func interruptIfNeeded(sessionID: UUID, runs: [PomodoroRun], context: ModelContext?, now: Date = Date()) throws {
        guard let run = runs.first(where: { $0.sessionID == sessionID && $0.deletedAt == nil && $0.endedAt == nil }),
              run.state == .focusing else {
            return
        }
        run.state = .interrupted
        run.updatedAt = now
        run.clientMutationID = UUID()
        try context?.save()
    }

    func resumeIfNeeded(sessionID: UUID, runs: [PomodoroRun], context: ModelContext?, now: Date = Date()) throws {
        guard let run = runs.first(where: { $0.sessionID == sessionID && $0.deletedAt == nil && $0.endedAt == nil }),
              run.state == .interrupted else {
            return
        }
        run.state = .focusing
        run.updatedAt = now
        run.clientMutationID = UUID()
        try context?.save()
    }

    func cancelIfNeeded(sessionID: UUID, runs: [PomodoroRun], context: ModelContext?, now: Date = Date()) throws {
        guard let run = runs.first(where: { $0.sessionID == sessionID && $0.deletedAt == nil && $0.endedAt == nil }) else {
            return
        }
        run.state = .cancelled
        run.endedAt = now
        run.updatedAt = now
        run.clientMutationID = UUID()
        try context?.save()
    }
}

@MainActor
struct LedgerCommandHandler {
    @discardableResult
    func addManualTime(draft: ManualTimeDraft, taskID: UUID, repository: TimeTrackingRepository) throws -> TimeSegment {
        try AddManualTimeUseCase(repository: repository).execute(
            taskID: taskID,
            startedAt: draft.startedAt,
            endedAt: draft.endedAt,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Manual"
        )
    }

    func updateSegment(draft: SegmentEditorDraft, taskID: UUID, repository: TimeTrackingRepository) throws {
        let endedAt = draft.isActive ? nil : draft.endedAt
        try UpdateSegmentUseCase(repository: repository).execute(
            segmentID: draft.segmentID,
            taskID: taskID,
            startedAt: draft.startedAt,
            endedAt: endedAt,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    func softDeleteSegment(_ segmentID: UUID, repository: TimeTrackingRepository) throws {
        try SoftDeleteSegmentUseCase(repository: repository).execute(segmentID: segmentID)
    }
}

@MainActor
struct CountdownCommandHandler {
    @discardableResult
    func add(context: ModelContext, deviceID: String = DeviceIdentity.current) throws -> CountdownEvent {
        let event = CountdownEvent(
            title: AppStrings.localized("task.newEvent"),
            date: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
            deviceID: deviceID
        )
        context.insert(event)
        try context.save()
        return event
    }

    func update(_ event: CountdownEvent, title: String? = nil, date: Date? = nil, context: ModelContext, now: Date = Date()) throws {
        if let title {
            event.title = title
        }
        if let date {
            event.date = date
        }
        event.updatedAt = now
        event.clientMutationID = UUID()
        try context.save()
    }

    func softDelete(_ event: CountdownEvent, context: ModelContext, now: Date = Date()) throws {
        event.deletedAt = now
        event.updatedAt = now
        event.clientMutationID = UUID()
        try context.save()
    }
}

@MainActor
struct ChecklistCommandHandler {
    @discardableResult
    func add(
        taskID: UUID,
        title: String,
        existingItems: [ChecklistItem],
        context: ModelContext,
        deviceID: String = DeviceIdentity.current
    ) throws -> ChecklistItem? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false else { return nil }

        let nextSortOrder = ((existingItems.map(\.sortOrder).max() ?? 0) + 10)
        let item = ChecklistItem(
            taskID: taskID,
            title: trimmedTitle,
            isCompleted: false,
            sortOrder: nextSortOrder,
            deviceID: deviceID
        )
        context.insert(item)
        try context.save()
        return item
    }

    func toggle(_ item: ChecklistItem, context: ModelContext, now: Date = Date()) throws {
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? now : nil
        item.updatedAt = now
        item.clientMutationID = UUID()
        try context.save()
    }
}

@MainActor
struct PreferenceCommandHandler {
    func set(key: AppPreferenceKey, valueJSON: String, context: ModelContext, now: Date = Date()) throws {
        let rawKey = key.rawValue
        let descriptor = FetchDescriptor<SyncedPreference>(
            predicate: #Predicate { $0.key == rawKey && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let existing = try context.fetch(descriptor)
        let target = existing.first ?? SyncedPreference(
            key: key.rawValue,
            valueJSON: valueJSON,
            deviceID: DeviceIdentity.current
        )
        if existing.isEmpty {
            context.insert(target)
        }
        target.valueJSON = valueJSON
        target.updatedAt = now
        target.deviceID = DeviceIdentity.current
        target.clientMutationID = UUID()
        for duplicate in existing.dropFirst() {
            duplicate.deletedAt = now
            duplicate.updatedAt = now
            duplicate.clientMutationID = UUID()
        }
        try context.save()
    }
}
