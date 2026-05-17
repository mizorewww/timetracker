import Foundation

struct StressDataProfile: Equatable {
    let name: String
    let rootCount: Int
    let maxDepth: Int
    let childrenPerNode: Int
    let checklistItemsPerTask: Int
    let segmentsPerTask: Int
    let categoryCount: Int
    let inboxItemCount: Int
    let countdownEventCount: Int

    var estimatedTaskCount: Int {
        guard rootCount > 0, maxDepth > 0 else { return 0 }
        var total = 0
        var levelCount = rootCount
        for _ in 0..<maxDepth {
            total += levelCount
            levelCount *= max(childrenPerNode, 0)
        }
        return total
    }

    var estimatedModelCount: Int {
        let tasks = estimatedTaskCount
        return tasks +
            categoryCount +
            rootCount +
            tasks * checklistItemsPerTask * 2 +
            tasks * segmentsPerTask * 2 +
            tasks / 4 +
            inboxItemCount * 2 +
            countdownEventCount
    }

    func overridingFromDefaults(_ defaults: UserDefaults = .standard) -> StressDataProfile {
        StressDataProfile(
            name: name,
            rootCount: Self.integerOverride("TimeTrackerStressRootCount", fallback: rootCount, defaults: defaults),
            maxDepth: Self.integerOverride("TimeTrackerStressMaxDepth", fallback: maxDepth, defaults: defaults),
            childrenPerNode: Self.integerOverride("TimeTrackerStressChildrenPerNode", fallback: childrenPerNode, defaults: defaults),
            checklistItemsPerTask: Self.integerOverride("TimeTrackerStressChecklistItemsPerTask", fallback: checklistItemsPerTask, defaults: defaults),
            segmentsPerTask: Self.integerOverride("TimeTrackerStressSegmentsPerTask", fallback: segmentsPerTask, defaults: defaults),
            categoryCount: Self.integerOverride("TimeTrackerStressCategoryCount", fallback: categoryCount, defaults: defaults),
            inboxItemCount: Self.integerOverride("TimeTrackerStressInboxItemCount", fallback: inboxItemCount, defaults: defaults),
            countdownEventCount: Self.integerOverride("TimeTrackerStressCountdownEventCount", fallback: countdownEventCount, defaults: defaults)
        ).normalized()
    }

    func normalized() -> StressDataProfile {
        StressDataProfile(
            name: name,
            rootCount: rootCount.clamped(to: 1...200),
            maxDepth: maxDepth.clamped(to: 1...8),
            childrenPerNode: childrenPerNode.clamped(to: 0...8),
            checklistItemsPerTask: checklistItemsPerTask.clamped(to: 0...12),
            segmentsPerTask: segmentsPerTask.clamped(to: 0...12),
            categoryCount: categoryCount.clamped(to: 1...64),
            inboxItemCount: inboxItemCount.clamped(to: 0...10_000),
            countdownEventCount: countdownEventCount.clamped(to: 0...5_000)
        )
    }

    static func named(_ rawValue: String) -> StressDataProfile? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "compact", "smoke":
            return compact
        case "large":
            return large
        case "extreme":
            return extreme
        case "custom":
            return large
        default:
            return nil
        }
    }

    static let compact = StressDataProfile(
        name: "compact",
        rootCount: 12,
        maxDepth: 4,
        childrenPerNode: 3,
        checklistItemsPerTask: 3,
        segmentsPerTask: 1,
        categoryCount: 6,
        inboxItemCount: 80,
        countdownEventCount: 40
    )

    static let large = StressDataProfile(
        name: "large",
        rootCount: 25,
        maxDepth: 5,
        childrenPerNode: 3,
        checklistItemsPerTask: 2,
        segmentsPerTask: 2,
        categoryCount: 12,
        inboxItemCount: 500,
        countdownEventCount: 200
    )

    static let extreme = StressDataProfile(
        name: "extreme",
        rootCount: 50,
        maxDepth: 6,
        childrenPerNode: 3,
        checklistItemsPerTask: 2,
        segmentsPerTask: 2,
        categoryCount: 24,
        inboxItemCount: 1_500,
        countdownEventCount: 500
    )

    private static func integerOverride(
        _ key: String,
        fallback: Int,
        defaults: UserDefaults
    ) -> Int {
        if let stringValue = defaults.string(forKey: key), let value = Int(stringValue) {
            return value
        }
        if let numberValue = defaults.object(forKey: key) as? NSNumber {
            return numberValue.intValue
        }
        return fallback
    }
}

enum AppStressDataConfiguration {
    static let profileKey = "TimeTrackerStressDataProfile"

    static var requestedProfile: StressDataProfile? {
        guard AppDemoDataConfiguration.allowsDemoDataCreation else { return nil }
        guard let rawProfile = UserDefaults.standard.string(forKey: profileKey) else { return nil }
        guard rawProfile.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "off" else {
            return nil
        }
        return StressDataProfile.named(rawProfile)?.overridingFromDefaults()
    }
}
