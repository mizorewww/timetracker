import Foundation
import SwiftData

@MainActor
enum SeedData {
    static func ensureSeeded(context: ModelContext) throws {
        let taskCount = try context.fetch(FetchDescriptor<TaskNode>()).count
        guard taskCount == 0 else { return }

        let taskRepository = SwiftDataTaskRepository(context: context)
        let timeRepository = SwiftDataTimeTrackingRepository(context: context)

        let app = try taskRepository.createTask(title: "Time Tracker App", kind: .project, parentID: nil, colorHex: "1677FF", iconName: "folder")
        let client = try taskRepository.createTask(title: "Client Work", kind: .project, parentID: nil, colorHex: "7C3AED", iconName: "briefcase")
        let study = try taskRepository.createTask(title: "Study", kind: .folder, parentID: nil, colorHex: "16A34A", iconName: "book")

        let design = try taskRepository.createTask(title: "设计 iOS UI", kind: .task, parentID: app.id, colorHex: "1677FF", iconName: "square.grid.2x2")
        let macDesign = try taskRepository.createTask(title: "设计 macOS UI", kind: .task, parentID: app.id, colorHex: "1677FF", iconName: "macwindow")
        let coding = try taskRepository.createTask(title: "编码原型", kind: .task, parentID: app.id, colorHex: "1677FF", iconName: "chevron.left.forwardslash.chevron.right")
        let meeting = try taskRepository.createTask(title: "团队会议", kind: .task, parentID: client.id, colorHex: "7C3AED", iconName: "person.2")
        let reading = try taskRepository.createTask(title: "阅读 Apple HIG", kind: .task, parentID: study.id, colorHex: "16A34A", iconName: "book")
        let manual = try taskRepository.createTask(title: "手动补录：需求整理", kind: .task, parentID: app.id, colorHex: "F97316", iconName: "pencil.and.list.clipboard")

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        try timeRepository.addManualSegment(
            taskID: coding.id,
            startedAt: calendar.date(byAdding: .hour, value: 9, to: startOfDay) ?? now,
            endedAt: calendar.date(byAdding: .minute, value: 590, to: startOfDay) ?? now,
            note: "Pomodoro"
        )
        try timeRepository.addManualSegment(
            taskID: meeting.id,
            startedAt: calendar.date(byAdding: .hour, value: 10, to: startOfDay) ?? now,
            endedAt: calendar.date(byAdding: .minute, value: 630, to: startOfDay) ?? now,
            note: "会议"
        )
        try timeRepository.addManualSegment(
            taskID: manual.id,
            startedAt: calendar.date(byAdding: .minute, value: 810, to: startOfDay) ?? now,
            endedAt: calendar.date(byAdding: .minute, value: 840, to: startOfDay) ?? now,
            note: "Manual"
        )

        _ = try timeRepository.startTask(taskID: design.id, source: .pomodoro)
        _ = try timeRepository.startTask(taskID: reading.id, source: .timer)

        macDesign.notes = "完善三栏布局，强调时间线与 Inspector 的配合。"
        design.notes = "移动端优先展示当前状态、今天时间线和快速开始。"
        try context.save()
    }
}
