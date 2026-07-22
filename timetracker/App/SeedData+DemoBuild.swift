import Foundation
import SwiftData

#if DEBUG
extension SeedData {
    static func buildDemoData(context: ModelContext) throws {
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "demo")
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let workCategory = try taskRepository.createCategory(
            title: "Work",
            colorHex: "1677FF",
            iconName: "briefcase",
            includesInForecast: true
        )
        let studyCategory = try taskRepository.createCategory(
            title: "Study",
            colorHex: "16A34A",
            iconName: "book",
            includesInForecast: true
        )

        let app = try taskRepository.createTask(title: "Time Tracker App", parentID: nil, categoryID: workCategory.id, colorHex: "1677FF", iconName: "clock.badge.checkmark")
        let design = try taskRepository.createTask(title: "Design System", parentID: app.id, colorHex: "1677FF", iconName: "paintpalette")
        let macDesign = try taskRepository.createTask(title: "Design macOS UI", parentID: design.id, colorHex: "1677FF", iconName: "macwindow")
        let iosDesign = try taskRepository.createTask(title: "Design iOS UI", parentID: design.id, colorHex: "0EA5E9", iconName: "iphone")
        let implementation = try taskRepository.createTask(title: "Implementation", parentID: app.id, colorHex: "16A34A", iconName: "hammer")
        let ledger = try taskRepository.createTask(title: "SwiftData Ledger", parentID: implementation.id, colorHex: "16A34A", iconName: "externaldrive.badge.checkmark")
        let analytics = try taskRepository.createTask(title: "Analytics Charts", parentID: implementation.id, colorHex: "7C3AED", iconName: "chart.xyaxis.line")
        let sync = try taskRepository.createTask(title: "iCloud Sync", parentID: implementation.id, colorHex: "64748B", iconName: "icloud")

        let client = try taskRepository.createTask(title: "Client Work", parentID: nil, categoryID: workCategory.id, colorHex: "F97316", iconName: "briefcase")
        let meeting = try taskRepository.createTask(title: "Team Meeting", parentID: client.id, colorHex: "F97316", iconName: "person.2")
        let review = try taskRepository.createTask(title: "Requirements Review", parentID: client.id, colorHex: "EF4444", iconName: "doc.text.magnifyingglass")

        let study = try taskRepository.createTask(title: "Study", parentID: nil, categoryID: studyCategory.id, colorHex: "16A34A", iconName: "book")
        let hig = try taskRepository.createTask(title: "Read Apple HIG", parentID: study.id, colorHex: "16A34A", iconName: "book.pages")
        let swift = try taskRepository.createTask(title: "SwiftData Docs", parentID: study.id, colorHex: "0EA5E9", iconName: "swift")

        if CommandLine.arguments.contains("--uitesting") {
            _ = try taskRepository.createTask(
                title: "Standalone Task",
                parentID: nil,
                categoryID: workCategory.id,
                colorHex: "64748B",
                iconName: "checkmark.circle"
            )
            context.insert(
                SyncedPreference(
                    key: AppPreferenceKey.quickStartTaskIDs.rawValue,
                    valueJSON: try PreferenceJSON.encodeChecked([
                        app.id.uuidString,
                        design.id.uuidString
                    ]),
                    deviceID: "demo"
                )
            )
            if CommandLine.arguments.contains("--uitesting-short-timeline") {
                try addShortTimelineUITestFixture(
                    context: context,
                    taskRepository: taskRepository,
                    categoryID: workCategory.id,
                    startOfToday: startOfToday,
                    now: now
                )
                try context.saveAfterMutationStep()
                return
            }
            if CommandLine.arguments.contains("--uitesting-overlap-timeline") {
                try addOverlappingTimelineUITestFixture(
                    context: context,
                    taskRepository: taskRepository,
                    categoryID: workCategory.id,
                    startOfToday: startOfToday
                )
                try context.saveAfterMutationStep()
                return
            }
            if CommandLine.arguments.contains("--uitesting-gap-label-collision") {
                try addGapLabelCollisionTimelineUITestFixture(
                    context: context,
                    taskRepository: taskRepository,
                    categoryID: workCategory.id,
                    startOfToday: startOfToday
                )
                try context.saveAfterMutationStep()
                return
            }
            if CommandLine.arguments.contains("--uitesting-today-heatmap") {
                let quantityTask = try taskRepository.createTask(
                    title: "Daily Push-ups",
                    parentID: nil,
                    categoryID: studyCategory.id,
                    colorHex: "7C3AED",
                    iconName: "figure.strengthtraining.traditional"
                )
                let quantityChild = try taskRepository.createTask(
                    title: "Morning Set",
                    parentID: quantityTask.id,
                    colorHex: "A855F7",
                    iconName: "figure.strengthtraining.traditional"
                )
                let quantityGoals = [
                    TaskQuantityGoal(
                        taskID: quantityTask.id,
                        targetAmount: 50,
                        unitLabel: "reps",
                        deviceID: "demo"
                    ),
                    TaskQuantityGoal(
                        taskID: quantityChild.id,
                        targetAmount: 25,
                        unitLabel: " RePs ",
                        deviceID: "demo"
                    ),
                ]
                quantityGoals.forEach(context.insert)
                let yesterday = calendar.date(
                    byAdding: .day,
                    value: -1,
                    to: startOfToday
                ) ?? startOfToday.addingTimeInterval(-86_400)
                let quantityEntries = [
                    TaskQuantityEntry(
                        id: UUID(),
                        taskID: quantityTask.id,
                        amount: 20,
                        recordedAt: yesterday,
                        createdAt: yesterday,
                        deviceID: "demo"
                    ),
                    TaskQuantityEntry(
                        id: UUID(),
                        taskID: quantityChild.id,
                        amount: 10,
                        recordedAt: yesterday,
                        createdAt: yesterday,
                        deviceID: "demo"
                    ),
                    TaskQuantityEntry(
                        id: UUID(),
                        taskID: quantityTask.id,
                        amount: 30,
                        recordedAt: startOfToday,
                        createdAt: startOfToday,
                        deviceID: "demo"
                    ),
                    TaskQuantityEntry(
                        id: UUID(),
                        taskID: quantityChild.id,
                        amount: 15,
                        recordedAt: startOfToday,
                        createdAt: startOfToday,
                        deviceID: "demo"
                    ),
                ]
                quantityEntries.forEach(context.insert)
                context.insert(
                    SyncedPreference(
                        key: AppPreferenceKey.todayHeatmapTaskIDs.rawValue,
                        valueJSON: try PreferenceJSON.encodeChecked([
                            app.id.uuidString,
                            client.id.uuidString,
                            quantityTask.id.uuidString
                        ]),
                        deviceID: "demo"
                    )
                )
            }

            if CommandLine.arguments.contains("--uitesting-inbox-suggestion") {
                let childTaskItem = InboxItem(
                    title: "Prepare the design review brief",
                    sortOrder: 10,
                    deviceID: "demo"
                )
                let categoryTaskItem = InboxItem(
                    title: "Schedule the client kickoff",
                    sortOrder: 20,
                    deviceID: "demo"
                )
                let checklistItem = InboxItem(
                    title: "Confirm the review attendees",
                    sortOrder: 30,
                    deviceID: "demo"
                )
                let completedInboxItem = InboxItem(
                    title: "Archive the previous review notes",
                    isCompleted: true,
                    sortOrder: 40,
                    deviceID: "demo"
                )
                context.insert(childTaskItem)
                context.insert(categoryTaskItem)
                context.insert(checklistItem)
                context.insert(completedInboxItem)
                context.insert(
                    InboxSuggestion(
                        inboxItemID: childTaskItem.id,
                        inboxItemContextID: childTaskItem.suggestionContextID,
                        inboxItemRevisionID: childTaskItem.suggestionRevisionID,
                        taskID: design.id,
                        destinationKind: .childTask,
                        reason: "This belongs with the design-system work.",
                        iconName: "sun.max",
                        colorHex: "FFD60A",
                        modelID: "ui-test",
                        titleSnapshot: childTaskItem.title,
                        deviceID: "demo"
                    )
                )
                context.insert(
                    InboxSuggestion(
                        inboxItemID: categoryTaskItem.id,
                        inboxItemContextID: categoryTaskItem.suggestionContextID,
                        inboxItemRevisionID: categoryTaskItem.suggestionRevisionID,
                        taskID: workCategory.id,
                        destinationKind: .category,
                        reason: "This is a new piece of client work.",
                        iconName: "person.2",
                        colorHex: "F97316",
                        modelID: "ui-test",
                        titleSnapshot: categoryTaskItem.title,
                        deviceID: "demo"
                    )
                )
                context.insert(
                    InboxSuggestion(
                        inboxItemID: checklistItem.id,
                        inboxItemContextID: checklistItem.suggestionContextID,
                        inboxItemRevisionID: checklistItem.suggestionRevisionID,
                        taskID: design.id,
                        destinationKind: .checklist,
                        reason: "This is one step in the design review.",
                        iconName: "person.crop.circle.badge.checkmark",
                        colorHex: "1677FF",
                        modelID: "ui-test",
                        titleSnapshot: checklistItem.title,
                        deviceID: "demo"
                    )
                )
            }
        }

        macDesign.notes = "Refine the split layout and prioritize the timeline, task tree, and task detail flow."
        iosDesign.notes = "On mobile, prioritize quick start, current state, and an editable Today timeline."
        analytics.notes = "All analytics aggregate from TimeSegment records; cached summaries are never the source of truth."
        sync.notes = "SwiftData CloudKit private database with deviceID and clientMutationID kept for conflict handling."

        addChecklist(
            context: context,
            taskID: macDesign.id,
            titles: ["Polish timeline", "Align task detail", "Tighten sidebar"],
            completed: 2,
            completionDayOffsets: [0, 0],
            completedIndices: [1, 2]
        )
        addChecklist(
            context: context,
            taskID: iosDesign.id,
            titles: ["Compact active timer rows", "Fix task editor sheet", "Review phone analytics"],
            completed: 1,
            completionDayOffsets: [0]
        )
        addChecklist(
            context: context,
            taskID: ledger.id,
            titles: ["Schema migration", "Preference import", "Checklist persistence", "CloudKit smoke test"],
            completed: 3,
            completionDayOffsets: [0, -1, -1]
        )
        addChecklist(
            context: context,
            taskID: analytics.id,
            titles: ["Month axis", "Forecast card", "Donut cleanup", "Overlap lanes"],
            completed: 2,
            completionDayOffsets: [-1, -7]
        )
        addChecklist(
            context: context,
            taskID: sync.id,
            titles: ["Sync settings", "Restart notice", "Manual sync button"],
            completed: 1,
            completionDayOffsets: [-14]
        )

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
        let liveActivityStart = CommandLine.arguments.contains(
            "--uitesting-live-activity-long-timer"
        )
            ? now.addingTimeInterval(-16 * 60 * 60)
            : now.addingTimeInterval(-32 * 60)
        try addActiveSegment(
            context: context,
            taskID: hig.id,
            source: .timer,
            start: liveActivityStart,
            note: "Parallel reading"
        )

        try context.saveAfterMutationStep()
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

    private static func addShortTimelineUITestFixture(
        context: ModelContext,
        taskRepository: SwiftDataTaskRepository,
        categoryID: UUID,
        startOfToday: Date,
        now: Date
    ) throws {
        let contextTask = try taskRepository.createTask(
            title: "Timeline Fixture Context",
            parentID: nil,
            categoryID: categoryID,
            colorHex: "64748B",
            iconName: "rectangle.3.group"
        )
        let firstShortTask = try taskRepository.createTask(
            title: "Timeline Short Blue",
            parentID: nil,
            categoryID: categoryID,
            colorHex: "1677FF",
            iconName: "bolt.fill"
        )
        let secondShortTask = try taskRepository.createTask(
            title: "Timeline Short Orange",
            parentID: nil,
            categoryID: categoryID,
            colorHex: "F97316",
            iconName: "flame.fill"
        )
        let terminalTask = try taskRepository.createTask(
            title: "Timeline Terminal Green",
            parentID: nil,
            categoryID: categoryID,
            colorHex: "16A34A",
            iconName: "arrow.down"
        )

        let terminalEnd = now.addingTimeInterval(-5 * 60)
        let terminalStart = terminalEnd.addingTimeInterval(-30)
        let firstShortStart = terminalStart.addingTimeInterval(-45 * 60)
        let secondShortStart = firstShortStart.addingTimeInterval(2 * 60)
        let contextStart = max(
            startOfToday.addingTimeInterval(60),
            firstShortStart.addingTimeInterval(-2.5 * 60 * 60)
        )

        try addSegment(
            context: context,
            taskID: contextTask.id,
            source: .timer,
            start: contextStart,
            duration: 30 * 60,
            note: "Task 23 compressed-gap context"
        )
        try addSegment(
            context: context,
            taskID: firstShortTask.id,
            source: .manual,
            start: firstShortStart,
            duration: 30,
            note: "Task 23 first short mark"
        )
        try addSegment(
            context: context,
            taskID: secondShortTask.id,
            source: .manual,
            start: secondShortStart,
            duration: 30,
            note: "Task 23 second short mark"
        )
        try addSegment(
            context: context,
            taskID: terminalTask.id,
            source: .manual,
            start: terminalStart,
            duration: 30,
            note: "Task 23 terminal short mark"
        )
    }

    private static func addOverlappingTimelineUITestFixture(
        context: ModelContext,
        taskRepository: SwiftDataTaskRepository,
        categoryID: UUID,
        startOfToday: Date
    ) throws {
        let contextTask = try taskRepository.createTask(
            title: "Timeline Overlap Context",
            parentID: nil,
            categoryID: categoryID,
            colorHex: "64748B",
            iconName: "rectangle.3.group"
        )
        let contextStart = startOfToday.addingTimeInterval(13 * 60 * 60)
        let burstStart = startOfToday.addingTimeInterval(15.5 * 60 * 60)
        let burstTaskCount = 10
        let colors = [
            "1677FF", "7C3AED", "F97316", "16A34A", "EF4444",
            "0EA5E9", "A855F7", "14B8A6", "E11D48", "64748B",
        ]

        try addSegment(
            context: context,
            taskID: contextTask.id,
            source: .timer,
            start: contextStart,
            duration: 30 * 60,
            note: "Task 24 compressed-gap context"
        )

        for index in 0..<burstTaskCount {
            let iconName: String
            switch index {
            case 0:
                iconName = "bolt.fill"
            case 1:
                iconName = "star.fill"
            default:
                iconName = "circle.fill"
            }
            let task = try taskRepository.createTask(
                title: String(format: "Timeline Burst %02d", index + 1),
                parentID: nil,
                categoryID: categoryID,
                colorHex: colors[index],
                iconName: iconName
            )
            try addSegment(
                context: context,
                taskID: task.id,
                source: .manual,
                start: burstStart.addingTimeInterval(TimeInterval(index * 2)),
                duration: 30,
                note: "Task 24 overlapping short mark \(index + 1)"
            )
        }
    }

    private static func addGapLabelCollisionTimelineUITestFixture(
        context: ModelContext,
        taskRepository: SwiftDataTaskRepository,
        categoryID: UUID,
        startOfToday: Date
    ) throws {
        let morning = try taskRepository.createTask(
            title: "Timeline Gap Morning",
            parentID: nil,
            categoryID: categoryID,
            colorHex: "1677FF",
            iconName: "sunrise.fill"
        )
        let bridge = try taskRepository.createTask(
            title: "Timeline Gap Bridge",
            parentID: nil,
            categoryID: categoryID,
            colorHex: "7C3AED",
            iconName: "point.topleft.down.to.point.bottomright.curvepath"
        )
        let evening = try taskRepository.createTask(
            title: "Timeline Gap Evening",
            parentID: nil,
            categoryID: categoryID,
            colorHex: "F97316",
            iconName: "sunset.fill"
        )

        try addSegment(
            context: context,
            taskID: morning.id,
            source: .timer,
            start: startOfToday.addingTimeInterval(9 * 60 * 60),
            duration: 3 * 60 * 60,
            note: "Task 25 morning anchor"
        )
        try addSegment(
            context: context,
            taskID: bridge.id,
            source: .manual,
            start: startOfToday.addingTimeInterval(14 * 60 * 60),
            duration: 10 * 60,
            note: "Task 25 bridge anchor"
        )
        try addSegment(
            context: context,
            taskID: evening.id,
            source: .manual,
            start: startOfToday.addingTimeInterval(
                16 * 60 * 60 + 10 * 60
            ),
            duration: 110 * 60,
            note: "Task 25 evening anchor"
        )
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

    private static func addChecklist(
        context: ModelContext,
        taskID: UUID,
        titles: [String],
        completed: Int,
        completionDayOffsets: [Int],
        completedIndices: Set<Int>? = nil
    ) {
        let calendar = Calendar.current
        let completionReference = Date().addingTimeInterval(-60)
        let resolvedCompletedIndices = completedIndices ?? Set(0..<completed)
        var completionIndex = 0
        for (index, title) in titles.enumerated() {
            let isCompleted = resolvedCompletedIndices.contains(index)
            let item = ChecklistItem(
                taskID: taskID,
                title: title,
                isCompleted: isCompleted,
                sortOrder: Double(index + 1) * 10,
                deviceID: "demo"
            )
            if item.isCompleted {
                let dayOffset = completionDayOffsets.indices.contains(completionIndex)
                    ? completionDayOffsets[completionIndex]
                    : 0
                completionIndex += 1
                item.completedAt = calendar.date(
                    byAdding: .day,
                    value: dayOffset,
                    to: completionReference
                )
            }
            context.insert(item)
            context.insert(
                ChecklistItemVisual(
                    checklistItemID: item.id,
                    iconName: isCompleted ? "checkmark.circle" : "circle.dashed",
                    colorHex: isCompleted ? "16A34A" : "1677FF",
                    deviceID: "demo"
                )
            )
        }
    }
}
#else
extension SeedData {
    static func buildDemoData(context: ModelContext) throws {
        throw SeedDataError.demoDataCreationUnavailable
    }
}
#endif
