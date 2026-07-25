import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct PomodoroMutationIdentityTests {
    @Test @MainActor
    func repositoryCompletionBreakAndCancellationStampInjectedWriter() throws {
        let context = try makeTestContext()
        var now = Date(timeIntervalSinceReferenceDate: 500_000)
        let writer = "pomodoro-writer"
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: writer)
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: writer,
            nowProvider: { now }
        )
        let repository = SwiftDataPomodoroRepository(
            context: context,
            timeRepository: timeRepository,
            deviceID: writer,
            nowProvider: { now }
        )
        let task = try taskRepository.createTask(
            title: "Writer invariant",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let run = try repository.startPomodoro(
            taskID: task.id,
            focusSeconds: 600,
            breakSeconds: 60,
            targetRounds: 2
        )
        let firstSessionID = try #require(run.sessionID)
        let firstSession = try #require(
            try timeRepository.sessions().first { $0.id == firstSessionID }
        )
        let firstSegment = try #require(
            try timeRepository.activeSegments().first { $0.sessionID == firstSessionID }
        )

        let completionMutationID = try spoofRemoteWriter(
            run: run,
            session: firstSession,
            segment: firstSegment,
            context: context
        )
        now = now.addingTimeInterval(30)
        try repository.completeFocus(runID: run.id, endedAt: now)

        #expect(run.state == .shortBreak)
        #expect(run.deviceID == writer)
        #expect(run.updatedAt == now)
        #expect(run.clientMutationID != completionMutationID)
        #expect(firstSession.deviceID == writer)
        #expect(firstSession.updatedAt == now)
        #expect(firstSegment.deviceID == writer)
        #expect(firstSegment.updatedAt == now)

        let breakMutationID = UUID()
        run.deviceID = "remote-break-writer"
        run.clientMutationID = breakMutationID
        try context.save()
        now = now.addingTimeInterval(15)
        try repository.completeBreak(runID: run.id)

        #expect(run.state == .focusing)
        #expect(run.deviceID == writer)
        #expect(run.updatedAt == now)
        #expect(run.clientMutationID != breakMutationID)

        let cancellationMutationID = UUID()
        run.deviceID = "remote-cancel-writer"
        run.clientMutationID = cancellationMutationID
        try context.save()
        now = now.addingTimeInterval(20)
        try repository.cancel(runID: run.id)

        #expect(run.state == .cancelled)
        #expect(run.deviceID == writer)
        #expect(run.updatedAt == now)
        #expect(run.clientMutationID != cancellationMutationID)
    }

    @Test @MainActor
    func startingNewRunCancelsRemoteActiveRunWithLocalWriter() throws {
        let context = try makeTestContext()
        var now = Date(timeIntervalSinceReferenceDate: 510_000)
        let writer = "replacement-writer"
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: writer)
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: writer,
            nowProvider: { now }
        )
        let repository = SwiftDataPomodoroRepository(
            context: context,
            timeRepository: timeRepository,
            deviceID: writer,
            nowProvider: { now }
        )
        let firstTask = try taskRepository.createTask(
            title: "First",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let secondTask = try taskRepository.createTask(
            title: "Second",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let firstRun = try repository.startPomodoro(
            taskID: firstTask.id,
            focusSeconds: 600,
            breakSeconds: 60,
            targetRounds: 1
        )
        let remoteMutationID = UUID()
        firstRun.deviceID = "remote-device"
        firstRun.clientMutationID = remoteMutationID
        try context.save()

        now = now.addingTimeInterval(45)
        let replacement = try repository.startPomodoro(
            taskID: secondTask.id,
            focusSeconds: 600,
            breakSeconds: 60,
            targetRounds: 1
        )

        #expect(firstRun.state == .cancelled)
        #expect(firstRun.endedAt == now)
        #expect(firstRun.deviceID == writer)
        #expect(firstRun.updatedAt == now)
        #expect(firstRun.clientMutationID != remoteMutationID)
        #expect(replacement.state == .focusing)
        #expect(replacement.deviceID == writer)
        #expect(try repository.activeRuns().map(\.id) == [replacement.id])
    }

    @Test @MainActor
    func reconciliationReplacesRemoteWriterAcrossRunAndLedger() throws {
        let context = try makeTestContext()
        let phaseStart = Date(timeIntervalSinceReferenceDate: 520_000)
        let mutationDate = phaseStart.addingTimeInterval(1000)
        let writer = "reconciliation-writer"
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: writer)
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: writer,
            nowProvider: { mutationDate }
        )
        let repository = SwiftDataPomodoroRepository(
            context: context,
            timeRepository: timeRepository,
            deviceID: writer,
            nowProvider: { mutationDate }
        )
        let task = try taskRepository.createTask(
            title: "Reconcile",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let run = try repository.startPomodoro(
            taskID: task.id,
            focusSeconds: 60,
            breakSeconds: 30,
            targetRounds: 2
        )
        let session = try #require(
            try timeRepository.sessions().first { $0.id == run.sessionID }
        )
        let segment = try #require(
            try timeRepository.activeSegments().first { $0.sessionID == run.sessionID }
        )
        run.startedAt = phaseStart
        session.startedAt = phaseStart
        segment.startedAt = phaseStart
        _ = try spoofRemoteWriter(
            run: run,
            session: session,
            segment: segment,
            context: context
        )
        let deadline = phaseStart.addingTimeInterval(60)

        #expect(try repository.reconcileExpiredPhase(
            runID: run.id,
            now: deadline.addingTimeInterval(500)
        ))
        #expect(run.state == .shortBreak)
        #expect(run.startedAt == deadline)
        #expect(run.deviceID == writer)
        #expect(run.updatedAt == mutationDate)
        #expect(session.deviceID == writer)
        #expect(session.updatedAt == mutationDate)
        #expect(segment.deviceID == writer)
        #expect(segment.updatedAt == mutationDate)
    }

    @Test @MainActor
    func commandCancellationAndDiscardUseInjectedWriterAndMutationClock() throws {
        let context = try makeTestContext()
        let effectiveEndDate = Date(timeIntervalSinceReferenceDate: 530_000)
        let mutationDate = effectiveEndDate.addingTimeInterval(5000)
        let writer = "command-writer"
        let fixture = try insertActiveFixture(
            context: context,
            startedAt: effectiveEndDate.addingTimeInterval(-50),
            focusSeconds: 100,
            targetRounds: 2
        )
        let originalMutationID = fixture.run.clientMutationID
        let handler = PomodoroCommandHandler(
            deviceID: writer,
            nowProvider: { mutationDate }
        )

        try handler.cancelIfNeeded(
            sessionID: fixture.session.id,
            runs: [fixture.run],
            context: context,
            now: effectiveEndDate
        )

        #expect(fixture.run.state == .cancelled)
        #expect(fixture.run.endedAt == effectiveEndDate)
        #expect(fixture.run.deletedAt == nil)
        #expect(fixture.run.updatedAt == mutationDate)
        #expect(fixture.run.deviceID == writer)
        #expect(fixture.run.clientMutationID != originalMutationID)

        let discardFixture = try insertActiveFixture(
            context: context,
            startedAt: effectiveEndDate.addingTimeInterval(-10),
            focusSeconds: 100,
            targetRounds: 2
        )
        try handler.discardIfNeeded(
            sessionID: discardFixture.session.id,
            runs: [discardFixture.run],
            context: context,
            now: effectiveEndDate
        )

        #expect(discardFixture.run.endedAt == effectiveEndDate)
        #expect(discardFixture.run.deletedAt == mutationDate)
        #expect(discardFixture.run.updatedAt == mutationDate)
        #expect(discardFixture.run.deviceID == writer)
        #expect(discardFixture.session.deletedAt == mutationDate)
        #expect(discardFixture.session.updatedAt == mutationDate)
        #expect(discardFixture.session.deviceID == writer)
        #expect(discardFixture.segment.deletedAt == mutationDate)
        #expect(discardFixture.segment.updatedAt == mutationDate)
        #expect(discardFixture.segment.deviceID == writer)
    }

    @Test @MainActor
    func commandExpiredSettlementStampsInjectedWriter() throws {
        let context = try makeTestContext()
        let phaseStart = Date(timeIntervalSinceReferenceDate: 540_000)
        let mutationDate = phaseStart.addingTimeInterval(5000)
        let writer = "deadline-writer"
        let fixture = try insertActiveFixture(
            context: context,
            startedAt: phaseStart,
            focusSeconds: 60,
            targetRounds: 1
        )
        let deadline = phaseStart.addingTimeInterval(60)

        try PomodoroCommandHandler(
            deviceID: writer,
            nowProvider: { mutationDate }
        ).cancelIfNeeded(
            sessionID: fixture.session.id,
            runs: [fixture.run],
            context: context,
            now: deadline.addingTimeInterval(300)
        )

        #expect(fixture.run.state == .completed)
        #expect(fixture.run.endedAt == deadline)
        #expect(fixture.run.updatedAt == mutationDate)
        #expect(fixture.run.deviceID == writer)
        #expect(fixture.session.endedAt == deadline)
        #expect(fixture.session.updatedAt == mutationDate)
        #expect(fixture.session.deviceID == writer)
        #expect(fixture.segment.endedAt == deadline)
        #expect(fixture.segment.updatedAt == mutationDate)
        #expect(fixture.segment.deviceID == writer)
    }

    @Test @MainActor
    func ledgerRebindUsesInjectedPomodoroWriter() throws {
        let context = try makeTestContext()
        let start = Date(timeIntervalSinceReferenceDate: 550_000)
        let mutationDate = start.addingTimeInterval(100)
        let writer = "ledger-writer"
        var repositoryNow = start
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: writer)
        let source = try taskRepository.createTask(
            title: "Source",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let target = try taskRepository.createTask(
            title: "Target",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: writer,
            nowProvider: { repositoryNow }
        )
        let segment = try timeRepository.startTask(taskID: source.id, source: .pomodoro)
        let run = PomodoroRun(taskID: source.id, deviceID: "remote-run-writer")
        run.sessionID = segment.sessionID
        run.startedAt = start
        run.state = .focusing
        let remoteMutationID = run.clientMutationID
        context.insert(run)
        try context.save()
        let revisedStart = start.addingTimeInterval(20)
        repositoryNow = mutationDate
        var draft = SegmentEditorDraft(segment: segment, note: "")
        draft.taskID = target.id
        draft.startedAt = revisedStart

        try LedgerCommandHandler(
            deviceID: writer,
            nowProvider: { mutationDate }
        ).updateSegment(
            draft: draft,
            taskID: target.id,
            activePomodoroSessionID: segment.sessionID,
            pomodoroRuns: [run],
            repository: timeRepository,
            context: context
        )

        #expect(run.taskID == target.id)
        #expect(run.startedAt == revisedStart)
        #expect(run.updatedAt == mutationDate)
        #expect(run.deviceID == writer)
        #expect(run.clientMutationID != remoteMutationID)
    }

    @Test @MainActor
    func nonMutatingRepositoryPathsPreserveRemoteAuditTuple() throws {
        let context = try makeTestContext()
        let auditDate = Date(timeIntervalSinceReferenceDate: 560_000)
        let mutationID = UUID()
        let run = PomodoroRun(taskID: UUID(), deviceID: "remote-device")
        run.state = .completed
        run.endedAt = auditDate
        run.updatedAt = auditDate
        run.clientMutationID = mutationID
        context.insert(run)
        try context.save()
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "local-device",
            nowProvider: { auditDate.addingTimeInterval(100) }
        )
        let repository = SwiftDataPomodoroRepository(
            context: context,
            timeRepository: timeRepository,
            deviceID: "local-device",
            nowProvider: { auditDate.addingTimeInterval(100) }
        )

        try repository.completeFocus(runID: run.id, endedAt: auditDate)
        try repository.completeBreak(runID: run.id)
        #expect(try repository.reconcileExpiredPhase(
            runID: run.id,
            now: auditDate.addingTimeInterval(100)
        ) == false)

        #expect(run.state == .completed)
        #expect(run.endedAt == auditDate)
        #expect(run.updatedAt == auditDate)
        #expect(run.deviceID == "remote-device")
        #expect(run.clientMutationID == mutationID)
    }

    @Test @MainActor
    func repositoryCancellationRollsBackEveryRecordWhenSaveFails() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PomodoroWriterRollbackTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "pomodoro.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        let taskID = UUID()
        let sessionID = UUID()
        let segmentID = UUID()
        let runID = UUID()
        let originalDate = Date(timeIntervalSinceReferenceDate: 570_000)
        let originalMutationID = UUID()

        try initializeWritableStore(at: storeURL, schema: schema) { context in
            let task = TaskNode(title: "Rollback", parentID: nil, deviceID: "remote-device")
            task.id = taskID
            let session = TimeSession(
                taskID: taskID,
                source: .pomodoro,
                deviceID: "remote-device",
                startedAt: originalDate
            )
            session.id = sessionID
            session.updatedAt = originalDate
            session.clientMutationID = originalMutationID
            let segment = TimeSegment(
                sessionID: sessionID,
                taskID: taskID,
                source: .pomodoro,
                deviceID: "remote-device",
                startedAt: originalDate
            )
            segment.id = segmentID
            segment.updatedAt = originalDate
            let run = PomodoroRun(
                taskID: taskID,
                focus: 600,
                breakSeconds: 60,
                targetRounds: 1,
                deviceID: "remote-device"
            )
            run.id = runID
            run.sessionID = sessionID
            run.startedAt = originalDate
            run.state = .focusing
            run.updatedAt = originalDate
            run.clientMutationID = originalMutationID
            context.insert(task)
            context.insert(session)
            context.insert(segment)
            context.insert(run)
        }

        let readOnlyContainer = try makeReadOnlyContainer(at: storeURL, schema: schema)
        let context = ModelContext(readOnlyContainer)
        let mutationDate = originalDate.addingTimeInterval(100)
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "local-device",
            nowProvider: { mutationDate }
        )
        let repository = SwiftDataPomodoroRepository(
            context: context,
            timeRepository: timeRepository,
            deviceID: "local-device",
            nowProvider: { mutationDate }
        )

        #expect(throws: (any Error).self) {
            try repository.cancel(runID: runID)
        }

        let run = try #require(
            try context.fetch(FetchDescriptor<PomodoroRun>()).first { $0.id == runID }
        )
        let session = try #require(
            try context.fetch(FetchDescriptor<TimeSession>()).first { $0.id == sessionID }
        )
        let segment = try #require(
            try context.fetch(FetchDescriptor<TimeSegment>()).first { $0.id == segmentID }
        )
        #expect(run.state == .focusing)
        #expect(run.endedAt == nil)
        #expect(run.updatedAt == originalDate)
        #expect(run.deviceID == "remote-device")
        #expect(run.clientMutationID == originalMutationID)
        #expect(session.endedAt == nil)
        #expect(session.updatedAt == originalDate)
        #expect(session.deviceID == "remote-device")
        #expect(session.clientMutationID == originalMutationID)
        #expect(segment.endedAt == nil)
        #expect(segment.updatedAt == originalDate)
        #expect(segment.deviceID == "remote-device")
    }

    @MainActor
    private func spoofRemoteWriter(
        run: PomodoroRun,
        session: TimeSession,
        segment: TimeSegment,
        context: ModelContext
    ) throws -> UUID {
        let mutationID = UUID()
        run.deviceID = "remote-run-writer"
        run.clientMutationID = mutationID
        session.deviceID = "remote-session-writer"
        segment.deviceID = "remote-segment-writer"
        try context.save()
        return mutationID
    }

    @MainActor
    private func insertActiveFixture(
        context: ModelContext,
        startedAt: Date,
        focusSeconds: Int,
        targetRounds: Int
    ) throws -> (run: PomodoroRun, session: TimeSession, segment: TimeSegment) {
        let taskID = UUID()
        let session = TimeSession(
            taskID: taskID,
            source: .pomodoro,
            deviceID: "remote-session-writer",
            startedAt: startedAt
        )
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .pomodoro,
            deviceID: "remote-segment-writer",
            startedAt: startedAt
        )
        let run = PomodoroRun(
            taskID: taskID,
            focus: focusSeconds,
            breakSeconds: 30,
            targetRounds: targetRounds,
            deviceID: "remote-run-writer"
        )
        run.sessionID = session.id
        run.startedAt = startedAt
        run.state = .focusing
        context.insert(session)
        context.insert(segment)
        context.insert(run)
        try context.save()
        return (run, session, segment)
    }

    @MainActor
    private func initializeWritableStore(
        at url: URL,
        schema: Schema,
        seed: (ModelContext) throws -> Void
    ) throws {
        let configuration = ModelConfiguration(
            "WritablePomodoroWriterTests-\(UUID().uuidString)",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        try seed(context)
        try context.save()
    }

    @MainActor
    private func makeReadOnlyContainer(at url: URL, schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "ReadOnlyPomodoroWriterTests-\(UUID().uuidString)",
            schema: schema,
            url: url,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
