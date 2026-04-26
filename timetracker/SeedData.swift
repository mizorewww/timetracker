import Foundation
import SwiftData

@MainActor
enum SeedData {
    static func ensureSeeded(context: ModelContext) throws {
        let taskCount = try context.fetch(FetchDescriptor<TaskNode>()).count
        guard taskCount == 0 else { return }
        try buildDemoData(context: context)
    }

    static func replaceWithDemoData(context: ModelContext) throws {
        try clearAll(context: context)
        try buildDemoData(context: context)
    }

    static func clearAll(context: ModelContext) throws {
        for model in try context.fetch(FetchDescriptor<DailySummary>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<CountdownEvent>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<PomodoroRun>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<TimeSegment>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<TimeSession>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<TaskNode>()) {
            context.delete(model)
        }
        try context.save()
    }

    static func clearDemoData(context: ModelContext) throws {
        let demoTasks = try context.fetch(FetchDescriptor<TaskNode>()).filter { $0.deviceID == "demo" }
        let demoTaskIDs = Set(demoTasks.map(\.id))
        let demoSessions = try context.fetch(FetchDescriptor<TimeSession>()).filter {
            $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID)
        }
        let demoSessionIDs = Set(demoSessions.map(\.id))

        for model in try context.fetch(FetchDescriptor<DailySummary>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<PomodoroRun>()).filter({ $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID) }) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<TimeSegment>()).filter({ $0.deviceID == "demo" || demoTaskIDs.contains($0.taskID) || demoSessionIDs.contains($0.sessionID) }) {
            context.delete(model)
        }
        for model in demoSessions {
            context.delete(model)
        }
        for model in demoTasks {
            context.delete(model)
        }
        try context.save()
    }

    private static func buildDemoData(context: ModelContext) throws {
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "demo")
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        let app = try taskRepository.createTask(title: "Time Tracker App", kind: .project, parentID: nil, colorHex: "1677FF", iconName: "clock.badge.checkmark")
        let design = try taskRepository.createTask(title: "Design System", kind: .project, parentID: app.id, colorHex: "1677FF", iconName: "paintpalette")
        let macDesign = try taskRepository.createTask(title: "Design macOS UI", kind: .task, parentID: design.id, colorHex: "1677FF", iconName: "macwindow")
        let iosDesign = try taskRepository.createTask(title: "Design iOS UI", kind: .task, parentID: design.id, colorHex: "0EA5E9", iconName: "iphone")
        let implementation = try taskRepository.createTask(title: "Implementation", kind: .project, parentID: app.id, colorHex: "16A34A", iconName: "hammer")
        let ledger = try taskRepository.createTask(title: "SwiftData Ledger", kind: .task, parentID: implementation.id, colorHex: "16A34A", iconName: "externaldrive.badge.checkmark")
        let analytics = try taskRepository.createTask(title: "Analytics Charts", kind: .task, parentID: implementation.id, colorHex: "7C3AED", iconName: "chart.xyaxis.line")
        let sync = try taskRepository.createTask(title: "iCloud Sync", kind: .task, parentID: implementation.id, colorHex: "64748B", iconName: "icloud")

        let client = try taskRepository.createTask(title: "Client Work", kind: .project, parentID: nil, colorHex: "F97316", iconName: "briefcase")
        let meeting = try taskRepository.createTask(title: "Team Meeting", kind: .task, parentID: client.id, colorHex: "F97316", iconName: "person.2")
        let review = try taskRepository.createTask(title: "Requirements Review", kind: .task, parentID: client.id, colorHex: "EF4444", iconName: "doc.text.magnifyingglass")

        let study = try taskRepository.createTask(title: "Study", kind: .project, parentID: nil, colorHex: "16A34A", iconName: "book")
        let hig = try taskRepository.createTask(title: "Read Apple HIG", kind: .task, parentID: study.id, colorHex: "16A34A", iconName: "book.pages")
        let swift = try taskRepository.createTask(title: "SwiftData Docs", kind: .task, parentID: study.id, colorHex: "0EA5E9", iconName: "swift")

        macDesign.notes = "Refine the three-column layout and prioritize the timeline, task tree, and inspector density."
        iosDesign.notes = "On mobile, prioritize quick start, current state, and an editable Today timeline."
        analytics.notes = "All analytics aggregate from TimeSegment records; cached summaries are never the source of truth."
        sync.notes = "SwiftData CloudKit private database with deviceID and clientMutationID kept for conflict handling."

        let focusTasks = [macDesign, iosDesign, ledger, analytics, sync, meeting, review, hig, swift]
        for dayOffset in stride(from: -13, through: 0, by: 1) {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let lightDay = weekday == 1 || weekday == 7
            let baseHour = lightDay ? 10 : 8
            let dayIndex = dayOffset + 13

            try addSegment(
                context: context,
                taskID: focusTasks[dayIndex % focusTasks.count].id,
                source: .pomodoro,
                start: day.addingTimeInterval(TimeInterval(baseHour * 3600 + 20 * 60)),
                duration: TimeInterval((lightDay ? 35 : 50) * 60),
                note: "Deep focus",
                createPomodoroRun: true
            )

            try addSegment(
                context: context,
                taskID: meeting.id,
                source: .timer,
                start: day.addingTimeInterval(TimeInterval((baseHour + 2) * 3600)),
                duration: TimeInterval((30 + (dayIndex % 3) * 15) * 60),
                note: "Sync meeting"
            )

            try addSegment(
                context: context,
                taskID: focusTasks[(dayIndex + 3) % focusTasks.count].id,
                source: .timer,
                start: day.addingTimeInterval(TimeInterval((baseHour + 3) * 3600 + 15 * 60)),
                duration: TimeInterval((65 + (dayIndex % 4) * 10) * 60),
                note: "Implementation"
            )

            if !lightDay {
                try addSegment(
                    context: context,
                    taskID: hig.id,
                    source: .timer,
                    start: day.addingTimeInterval(TimeInterval((baseHour + 3) * 3600 + 45 * 60)),
                    duration: TimeInterval(45 * 60),
                    note: "Overlapping reading to test Gross and Wall differences"
                )
            }

            try addSegment(
                context: context,
                taskID: review.id,
                source: .manual,
                start: day.addingTimeInterval(TimeInterval((baseHour + 6) * 3600 + 20 * 60)),
                duration: TimeInterval((lightDay ? 20 : 40) * 60),
                note: "Manual adjustment"
            )
        }

        try addActiveSegment(
            context: context,
            taskID: macDesign.id,
            source: .pomodoro,
            start: now.addingTimeInterval(-84 * 60),
            note: "Current focus"
        )
        try addActiveSegment(
            context: context,
            taskID: hig.id,
            source: .timer,
            start: now.addingTimeInterval(-32 * 60),
            note: "Parallel reading"
        )

        try context.save()
    }

    private static func addSegment(
        context: ModelContext,
        taskID: UUID,
        source: TimeSessionSource,
        start: Date,
        duration: TimeInterval,
        note: String?,
        createPomodoroRun: Bool = false
    ) throws {
        let end = start.addingTimeInterval(duration)
        let session = TimeSession(taskID: taskID, source: source, deviceID: "demo", startedAt: start)
        session.endedAt = end
        session.note = note
        let segment = TimeSegment(sessionID: session.id, taskID: taskID, source: source, deviceID: "demo", startedAt: start, endedAt: end)
        context.insert(session)
        context.insert(segment)

        if createPomodoroRun {
            let run = PomodoroRun(taskID: taskID, focus: Int(duration), breakSeconds: 5 * 60, targetRounds: 1, deviceID: "demo")
            run.sessionID = session.id
            run.startedAt = start
            run.endedAt = end
            run.completedFocusRounds = 1
            run.state = .completed
            context.insert(run)
        }
    }

    private static func addActiveSegment(
        context: ModelContext,
        taskID: UUID,
        source: TimeSessionSource,
        start: Date,
        note: String?
    ) throws {
        let session = TimeSession(taskID: taskID, source: source, deviceID: "demo", startedAt: start)
        session.note = note
        let segment = TimeSegment(sessionID: session.id, taskID: taskID, source: source, deviceID: "demo", startedAt: start)
        context.insert(session)
        context.insert(segment)

        if source == .pomodoro {
            let run = PomodoroRun(taskID: taskID, focus: 25 * 60, breakSeconds: 5 * 60, targetRounds: 1, deviceID: "demo")
            run.sessionID = session.id
            run.startedAt = start
            run.state = .focusing
            context.insert(run)
        }
    }
}
