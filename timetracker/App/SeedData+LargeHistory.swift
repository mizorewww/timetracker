import Foundation
import SwiftData

#if DEBUG
/// A heavy-user demo store for load testing, selected with
/// `-TimeTrackerDemoHistoryDays <days>` alongside a demo data mode: about
/// 1,500 tasks and 24 records a day for the given number of past days.
extension SeedData {
    static func buildLargeHistory(context: ModelContext, days: Int) throws {
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "demo")
        var random = SplitMix64(seed: 0x7173_7469_6D65)
        let colors = TaskColorPalette.hexValues
        let icons = ["briefcase", "book", "hammer", "paintpalette", "chart.bar", "person.2", "cup.and.saucer", "figure.run"]

        var leafTaskIDs: [UUID] = []
        for categoryIndex in 0 ..< 12 {
            let category = try taskRepository.createCategory(
                title: "Area \(categoryIndex + 1)",
                colorHex: colors[categoryIndex % colors.count],
                iconName: icons[categoryIndex % icons.count]
            )
            for rootIndex in 0 ..< 6 {
                let root = try taskRepository.createTask(
                    title: "Project \(categoryIndex + 1).\(rootIndex + 1)",
                    parentID: nil,
                    categoryID: category.id,
                    colorHex: colors[random.next(below: colors.count)],
                    iconName: icons[random.next(below: icons.count)]
                )
                for childIndex in 0 ..< 5 {
                    let child = try taskRepository.createTask(
                        title: "Stream \(childIndex + 1)",
                        parentID: root.id,
                        colorHex: root.colorHex,
                        iconName: icons[random.next(below: icons.count)]
                    )
                    for leafIndex in 0 ..< 3 {
                        let leaf = try taskRepository.createTask(
                            title: "Step \(leafIndex + 1)",
                            parentID: child.id,
                            colorHex: root.colorHex,
                            iconName: icons[random.next(below: icons.count)]
                        )
                        leafTaskIDs.append(leaf.id)
                    }
                }
            }
        }

        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        for dayOffset in 1 ... max(1, days) {
            let day = startOfToday.addingTimeInterval(-Double(dayOffset) * 86400)
            var start = day.addingTimeInterval(7 * 3600)
            for recordIndex in 0 ..< 24 {
                let duration = TimeInterval((10 + random.next(below: 50)) * 60)
                guard start.addingTimeInterval(duration) < now else { break }
                let source: TimeSessionSource = switch recordIndex % 6 {
                case 0: .pomodoro
                case 5: .manual
                default: .timer
                }
                try addSegment(
                    context: context,
                    taskID: leafTaskIDs[random.next(below: leafTaskIDs.count)],
                    source: source,
                    start: start,
                    duration: duration,
                    note: nil,
                    createPomodoroRun: source == .pomodoro
                )
                // Every third record overlaps the next, as parallel timers do.
                start = start.addingTimeInterval(recordIndex % 3 == 0 ? duration / 2 : duration)
            }
        }
    }
}

/// Deterministic generator, so every load-test store has the same shape.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(below bound: Int) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Int(value % UInt64(bound))
    }
}
#endif
