import Foundation
import SwiftData

#if DEBUG
extension SeedData {
    static func replaceWithStressData(context: ModelContext, profile: StressDataProfile) throws {
        try clearAll(context: context, disablesAutomaticDemoSeeding: false, includesPreferences: false)
        try buildStressData(context: context, profile: profile)
        setAutomaticDemoSeedingDisabled(false)
    }

    private static func buildStressData(context: ModelContext, profile: StressDataProfile) throws {
        let profile = profile.normalized()
        let deviceID = "stress"
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let categories = makeStressCategories(profile: profile, context: context, deviceID: deviceID)
        let tasks = try makeStressTasks(
            profile: profile,
            categories: categories,
            context: context,
            deviceID: deviceID,
            now: now
        )

        try makeStressChecklistItems(profile: profile, tasks: tasks, context: context, deviceID: deviceID)
        try makeStressLedger(
            profile: profile,
            tasks: tasks,
            context: context,
            deviceID: deviceID,
            startOfToday: startOfToday
        )
        makeStressInbox(profile: profile, tasks: tasks, context: context, deviceID: deviceID, now: now)
        makeStressCountdowns(profile: profile, context: context, deviceID: deviceID, now: now)
        try context.save()
    }

    private static func makeStressCategories(
        profile: StressDataProfile,
        context: ModelContext,
        deviceID: String
    ) -> [TaskCategory] {
        let colors = stressColors
        let icons = ["briefcase", "book", "hammer", "paintpalette", "chart.xyaxis.line", "target"]
        return (0..<profile.categoryCount).map { index in
            let category = TaskCategory(
                title: "Stress Category \(index + 1)",
                deviceID: deviceID,
                colorHex: colors[index % colors.count],
                iconName: icons[index % icons.count],
                includesInForecast: !index.isMultiple(of: 5),
                sortOrder: Double(index + 1) * 10
            )
            context.insert(category)
            return category
        }
    }

    private static func makeStressTasks(
        profile: StressDataProfile,
        categories: [TaskCategory],
        context: ModelContext,
        deviceID: String,
        now: Date
    ) throws -> [TaskNode] {
        var tasks: [TaskNode] = []
        var frontier: [(task: TaskNode, rootIndex: Int, childPath: String)] = []

        for rootIndex in 0..<profile.rootCount {
            let root = makeStressTask(
                title: "Stress Root \(rootIndex + 1)",
                parent: nil,
                rootIndex: rootIndex,
                depth: 0,
                siblingIndex: rootIndex,
                childPath: "\(rootIndex + 1)",
                deviceID: deviceID,
                now: now
            )
            context.insert(root)
            tasks.append(root)
            frontier.append((root, rootIndex, "\(rootIndex + 1)"))

            let category = categories[rootIndex % categories.count]
            context.insert(TaskCategoryAssignment(taskID: root.id, categoryID: category.id, deviceID: deviceID))
        }

        for depth in 1..<profile.maxDepth {
            var nextFrontier: [(task: TaskNode, rootIndex: Int, childPath: String)] = []
            for parentEntry in frontier {
                for childIndex in 0..<profile.childrenPerNode {
                    let childPath = "\(parentEntry.childPath).\(childIndex + 1)"
                    let child = makeStressTask(
                        title: "Stress Task \(childPath)",
                        parent: parentEntry.task,
                        rootIndex: parentEntry.rootIndex,
                        depth: depth,
                        siblingIndex: childIndex,
                        childPath: childPath,
                        deviceID: deviceID,
                        now: now
                    )
                    context.insert(child)
                    tasks.append(child)
                    nextFrontier.append((child, parentEntry.rootIndex, childPath))

                    if tasks.count.isMultiple(of: 1_000) {
                        try context.save()
                    }
                }
            }
            frontier = nextFrontier
        }

        return tasks
    }

    private static func makeStressTask(
        title: String,
        parent: TaskNode?,
        rootIndex: Int,
        depth: Int,
        siblingIndex: Int,
        childPath: String,
        deviceID: String,
        now: Date
    ) -> TaskNode {
        let task = TaskNode(
            title: title,
            parentID: parent?.id,
            deviceID: deviceID,
            colorHex: stressColors[(rootIndex + depth + siblingIndex) % stressColors.count],
            iconName: stressTaskIcons[(depth + siblingIndex) % stressTaskIcons.count],
            sortOrder: Double(siblingIndex + 1) * 10
        )
        task.path = (parent?.path ?? "") + "/" + task.id.uuidString
        task.depth = depth
        task.status = TaskStatus.editableCases[(rootIndex + depth + siblingIndex) % TaskStatus.editableCases.count]
        task.estimatedSeconds = 900 + ((rootIndex + depth + siblingIndex) % 12) * 900
        task.dueAt = now.addingTimeInterval(Double((rootIndex + depth + siblingIndex) % 45) * 86_400)
        task.notes = "Stress path \(childPath). Mutable notes, due date, estimate, status, color, icon, checklist, ledger, and forecast data are intentionally populated."
        task.createdAt = now.addingTimeInterval(-Double(rootIndex * 997 + depth * 131 + siblingIndex * 17))
        task.updatedAt = task.createdAt.addingTimeInterval(Double((depth + 1) * 60))
        return task
    }

    private static func makeStressChecklistItems(
        profile: StressDataProfile,
        tasks: [TaskNode],
        context: ModelContext,
        deviceID: String
    ) throws {
        guard profile.checklistItemsPerTask > 0 else { return }
        for (taskIndex, task) in tasks.enumerated() {
            for itemIndex in 0..<profile.checklistItemsPerTask {
                let item = ChecklistItem(
                    taskID: task.id,
                    title: "Stress checklist \(taskIndex + 1).\(itemIndex + 1)",
                    isCompleted: (taskIndex + itemIndex).isMultiple(of: 3),
                    sortOrder: Double(itemIndex + 1) * 10,
                    deviceID: deviceID
                )
                context.insert(item)
                context.insert(
                    ChecklistItemVisual(
                        checklistItemID: item.id,
                        iconName: stressChecklistIcons[itemIndex % stressChecklistIcons.count],
                        colorHex: stressColors[(taskIndex + itemIndex) % stressColors.count],
                        suggestionTitleSnapshot: item.title,
                        suggestionModelID: "stress-generator",
                        suggestionGeneratedAt: item.createdAt,
                        userEditedAt: item.updatedAt,
                        deviceID: deviceID
                    )
                )
            }

            if taskIndex.isMultiple(of: 1_000) {
                try context.save()
            }
        }
    }

    private static func makeStressLedger(
        profile: StressDataProfile,
        tasks: [TaskNode],
        context: ModelContext,
        deviceID: String,
        startOfToday: Date
    ) throws {
        guard profile.segmentsPerTask > 0 else { return }
        let sources = TimeSessionSource.allCases
        for (taskIndex, task) in tasks.enumerated() {
            for segmentIndex in 0..<profile.segmentsPerTask {
                let dayOffset = -((taskIndex + segmentIndex) % 60)
                let minuteOffset = (taskIndex * 13 + segmentIndex * 37) % (18 * 60)
                let start = startOfToday
                    .addingTimeInterval(Double(dayOffset) * 86_400)
                    .addingTimeInterval(Double(6 * 3_600 + minuteOffset * 60))
                let duration = Double(600 + ((taskIndex + segmentIndex) % 12) * 300)
                let source = sources[(taskIndex + segmentIndex) % sources.count]
                let session = TimeSession(
                    taskID: task.id,
                    source: source,
                    deviceID: deviceID,
                    startedAt: start,
                    titleSnapshot: task.title
                )
                session.endedAt = start.addingTimeInterval(duration)
                session.note = "Stress ledger segment \(taskIndex + 1)-\(segmentIndex + 1)"
                context.insert(session)
                context.insert(
                    TimeSegment(
                        sessionID: session.id,
                        taskID: task.id,
                        source: source,
                        deviceID: deviceID,
                        startedAt: session.startedAt,
                        endedAt: session.endedAt
                    )
                )

                if source == .pomodoro {
                    let run = PomodoroRun(
                        taskID: task.id,
                        focus: Int(duration),
                        breakSeconds: 5 * 60,
                        longBreakSeconds: 15 * 60,
                        targetRounds: 4,
                        deviceID: deviceID
                    )
                    run.sessionID = session.id
                    run.startedAt = session.startedAt
                    run.endedAt = session.endedAt
                    run.completedFocusRounds = 1
                    run.state = .completed
                    context.insert(run)
                }
            }

            if taskIndex.isMultiple(of: 1_000) {
                try context.save()
            }
        }

        for task in tasks.prefix(3) {
            let session = TimeSession(
                taskID: task.id,
                source: .timer,
                deviceID: deviceID,
                startedAt: startOfToday.addingTimeInterval(9 * 3_600),
                titleSnapshot: task.title
            )
            context.insert(session)
            context.insert(
                TimeSegment(
                    sessionID: session.id,
                    taskID: task.id,
                    source: .timer,
                    deviceID: deviceID,
                    startedAt: session.startedAt
                )
            )
        }
    }

    private static func makeStressInbox(
        profile: StressDataProfile,
        tasks: [TaskNode],
        context: ModelContext,
        deviceID: String,
        now: Date
    ) {
        guard !tasks.isEmpty else { return }
        for index in 0..<profile.inboxItemCount {
            let task = tasks[index % tasks.count]
            let item = InboxItem(
                title: "Stress inbox capture \(index + 1)",
                isCompleted: index.isMultiple(of: 7),
                sortOrder: Double(index + 1) * 10,
                deviceID: deviceID
            )
            item.notes = "Generated inbox note with suggestion metadata."
            item.suggestedTaskID = task.id
            item.suggestionReason = "Stress suggestion points to \(task.title)."
            item.suggestionGeneratedAt = now
            context.insert(item)
            context.insert(
                InboxSuggestion(
                    inboxItemID: item.id,
                    taskID: task.id,
                    reason: item.suggestionReason,
                    iconName: task.iconName ?? "checkmark.circle",
                    colorHex: task.colorHex ?? "1677FF",
                    modelID: "stress-generator",
                    titleSnapshot: task.title,
                    generatedAt: now,
                    deviceID: deviceID
                )
            )
        }
    }

    private static func makeStressCountdowns(
        profile: StressDataProfile,
        context: ModelContext,
        deviceID: String,
        now: Date
    ) {
        for index in 0..<profile.countdownEventCount {
            context.insert(
                CountdownEvent(
                    title: "Stress deadline \(index + 1)",
                    date: now.addingTimeInterval(Double(index - 20) * 86_400),
                    deviceID: deviceID
                )
            )
        }
    }

    private static let stressColors = [
        "1677FF", "16A34A", "F97316", "EF4444", "7C3AED", "0EA5E9", "64748B", "FF2D55"
    ]

    private static let stressTaskIcons = [
        "folder", "hammer", "paintpalette", "chart.xyaxis.line", "doc.text", "clock", "target", "macwindow"
    ]

    private static let stressChecklistIcons = [
        "checkmark.circle", "circle.dashed", "flag", "lightbulb", "paperclip", "pencil"
    ]
}
#else
extension SeedData {
    static func replaceWithStressData(context: ModelContext, profile: StressDataProfile) throws {
        throw SeedDataError.demoDataCreationUnavailable
    }
}
#endif
