import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreWidgetSnapshotTests {
    @Test
    func appGroupEntitlementStateIsExplicitAndConsistent() throws {
        let root = try projectRootURL()
        let appGroups = try readAppGroups(in: root.appending(path: "timetracker/timetracker.entitlements"))
        let widgetGroups = try readAppGroups(in: root.appending(path: "timetrackerWidgetExtension/timetrackerWidgetExtension.entitlements"))

        if appGroups.isEmpty || widgetGroups.isEmpty {
            let plan = try String(contentsOf: root.appending(path: "Docs/NextDevelopmentPlan.md"), encoding: .utf8)
            #expect(appGroups.isEmpty && widgetGroups.isEmpty)
            #expect(plan.contains("CLI currently cannot refresh the App Group provisioning profile"))
        } else {
            #expect(appGroups.contains(SharedWidgetSnapshotStore.suiteName))
            #expect(widgetGroups.contains(SharedWidgetSnapshotStore.suiteName))
            #expect(appGroups == widgetGroups)
        }
    }

    @Test @MainActor
    func widgetSnapshotCacheRoundTripsActiveTimerState() throws {
        let suiteName = "WidgetSnapshotTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let generatedAt = Date(timeIntervalSinceReferenceDate: 10000)
        let taskID = UUID()
        let segmentID = UUID()
        let snapshot = WidgetSnapshot(
            generatedAt: generatedAt,
            todayGrossSeconds: 3600,
            todayWallSeconds: 2400,
            activeTimers: [
                WidgetTimerSnapshot(
                    id: segmentID,
                    taskID: taskID,
                    title: "Shortcut timer",
                    path: "Work / Planning",
                    startedAt: generatedAt.addingTimeInterval(-600),
                    colorHex: "#0A84FF",
                    iconName: "timer"
                ),
            ],
            recentTasks: [
                WidgetRecentTaskSnapshot(
                    taskID: taskID,
                    title: "Write plan",
                    path: "Work",
                    colorHex: "#0A84FF",
                    iconName: "doc.text"
                ),
            ]
        )
        let cache = SharedWidgetSnapshotStore(defaults: defaults)

        try cache.save(snapshot)

        #expect(cache.load() == snapshot)

        var invalidSnapshot = snapshot
        invalidSnapshot.todayGrossSeconds = -1
        #expect(throws: WidgetSnapshotStoreError.invalidSnapshot) {
            try cache.save(invalidSnapshot)
        }
    }

    @Test @MainActor
    func widgetSnapshotStoreDoesNotFallbackToStandardDefaultsWhenSharedContainerIsMissing() throws {
        let snapshot = WidgetSnapshot.empty
        let cache = SharedWidgetSnapshotStore(defaults: nil)

        #expect(cache.isAvailable == false)
        #expect(cache.load() == nil)
        #expect(cache.loadResult() == .sharedContainerUnavailable)
        #expect(throws: WidgetSnapshotStoreError.sharedContainerUnavailable) {
            try cache.save(snapshot)
        }
    }

    @Test
    func widgetSnapshotStoreDistinguishesMissingAndCorruptedData() throws {
        let suiteName = "WidgetSnapshotLoadTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = SharedWidgetSnapshotStore(defaults: defaults)

        #expect(cache.loadResult() == .missing)

        defaults.set(Data("not-json".utf8), forKey: SharedWidgetSnapshotStore.snapshotKey)
        #expect(cache.loadResult() == .corrupted)

        defaults.set(
            Data(count: WidgetSnapshotLimits.maximumEncodedBytes + 1),
            forKey: SharedWidgetSnapshotStore.snapshotKey
        )
        #expect(cache.loadResult() == .corrupted)

        var invalidSnapshot = WidgetSnapshot.empty
        invalidSnapshot.todayWallSeconds = -1
        try defaults.set(
            JSONEncoder().encode(invalidSnapshot),
            forKey: SharedWidgetSnapshotStore.snapshotKey
        )
        #expect(cache.loadResult() == .corrupted)
    }

    @Test
    func widgetSnapshotStoreKeepsClockAdjustedDataRecoverable() throws {
        let suiteName = "WidgetSnapshotClockAdjustmentTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSinceReferenceDate: 20000)
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = now.addingTimeInterval(
            WidgetSnapshotLimits.maximumFutureClockSkew + 3600
        )
        let cache = SharedWidgetSnapshotStore(defaults: defaults)

        try cache.save(snapshot)

        #expect(snapshot.isStructurallyValid)
        #expect(snapshot.freshness(at: now) == .clockAdjusted)
        #expect(cache.load(at: now) == snapshot)
        #expect(cache.loadResult(at: now) == .snapshot(snapshot, freshness: .clockAdjusted))
    }

    @Test
    func widgetSnapshotFreshnessUsesTheSharedFifteenMinuteBoundary() {
        let generatedAt = Date(timeIntervalSinceReferenceDate: 10000)
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = generatedAt

        #expect(snapshot.freshness(at: generatedAt.addingTimeInterval(WidgetSnapshot.staleAfter)) == .current)
        #expect(snapshot.freshness(at: generatedAt.addingTimeInterval(WidgetSnapshot.staleAfter + 1)) == .stale)
        #expect(snapshot.isStructurallyValid)

        snapshot.generatedAt = generatedAt.addingTimeInterval(
            WidgetSnapshotLimits.maximumFutureClockSkew + 1
        )
        #expect(snapshot.isStructurallyValid)
        #expect(snapshot.freshness(at: generatedAt) == .clockAdjusted)
    }

    @Test
    func widgetTimelinePolicyAvoidsUnproductivePolling() {
        let policy = WidgetSnapshotTimelinePolicy()
        let generatedAt = Date(timeIntervalSinceReferenceDate: 25000)
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = generatedAt

        let currentResult = WidgetSnapshotLoadResult.snapshot(snapshot, freshness: .current)
        #expect(policy.reloadDecision(for: currentResult, at: generatedAt) == .after(
            generatedAt.addingTimeInterval(WidgetSnapshot.staleAfter)
        ))

        let staleNow = generatedAt.addingTimeInterval(WidgetSnapshot.staleAfter + 1)
        let staleResult = WidgetSnapshotLoadResult.snapshot(snapshot, freshness: .stale)
        #expect(policy.reloadDecision(for: staleResult, at: staleNow) == .never)

        snapshot.generatedAt = generatedAt.addingTimeInterval(3600)
        let adjustedResult = WidgetSnapshotLoadResult.snapshot(snapshot, freshness: .clockAdjusted)
        #expect(policy.reloadDecision(for: adjustedResult, at: generatedAt) == .after(
            snapshot.generatedAt.addingTimeInterval(-WidgetSnapshotLimits.maximumFutureClockSkew)
        ))

        snapshot.generatedAt = generatedAt.addingTimeInterval(
            WidgetSnapshotLimits.maximumFutureClockSkew + 1
        )
        let nearlyRecoveredResult = WidgetSnapshotLoadResult.snapshot(
            snapshot,
            freshness: .clockAdjusted
        )
        #expect(policy.reloadDecision(for: nearlyRecoveredResult, at: generatedAt) == .after(
            generatedAt.addingTimeInterval(WidgetSnapshotTimelinePolicy.minimumRetryDelay)
        ))
        #expect(policy.reloadDecision(for: .corrupted, at: generatedAt) == .never)
    }

    @Test
    func untrustedWidgetSnapshotFreezesElapsedTimeAtTheSnapshotBoundary() {
        let generatedAt = Date(timeIntervalSinceReferenceDate: 40000)
        let timer = WidgetTimerSnapshot(
            id: UUID(),
            taskID: UUID(),
            title: "Clock rollback",
            path: "Work",
            startedAt: generatedAt.addingTimeInterval(-30 * 60),
            colorHex: nil,
            iconName: nil
        )

        #expect(timer.elapsedPresentation(
            for: .clockAdjusted,
            generatedAt: generatedAt
        ) == .frozen(seconds: 30 * 60))
        #expect(timer.elapsedPresentation(
            for: .stale,
            generatedAt: generatedAt
        ) == .frozen(seconds: 30 * 60))
        #expect(timer.elapsedPresentation(
            for: .current,
            generatedAt: generatedAt
        ) == .live(startedAt: timer.startedAt))
    }

    @Test
    func widgetSnapshotValidationRejectsUnboundedAndDuplicateProjectionData() {
        let generatedAt = Date(timeIntervalSinceReferenceDate: 30000)
        let timerID = UUID()
        let taskID = UUID()
        let timer = WidgetTimerSnapshot(
            id: timerID,
            taskID: taskID,
            title: "Timer",
            path: "Work",
            startedAt: generatedAt.addingTimeInterval(-60),
            colorHex: "#0A84FF",
            iconName: "timer"
        )
        var snapshot = WidgetSnapshot(
            generatedAt: generatedAt,
            todayGrossSeconds: 60,
            todayWallSeconds: 60,
            activeTimers: [timer],
            recentTasks: []
        )

        #expect(snapshot.isStructurallyValid)

        snapshot.activeTimers.append(timer)
        #expect(snapshot.isStructurallyValid == false)

        snapshot.activeTimers = [timer]
        snapshot.activeTimers[0].title = String(
            repeating: "x",
            count: WidgetSnapshotLimits.maximumTitleBytes + 1
        )
        #expect(snapshot.isStructurallyValid == false)

        snapshot.activeTimers[0] = timer
        snapshot.activeTimers[0].startedAt = generatedAt.addingTimeInterval(
            WidgetSnapshotLimits.maximumFutureClockSkew + 1
        )
        #expect(snapshot.isStructurallyValid == false)
    }

    @Test
    func widgetUsesEventDrivenReloadsAndAccessibleSystemSurfaces() throws {
        let widget = try [
            "timetrackerWidgetExtension/TimeTrackerWidget.swift",
            "timetrackerWidgetExtension/ActiveTimerWidgetView.swift",
            "timetrackerWidgetExtension/WidgetSupplementaryViews.swift",
        ].map(sourceText).joined(separator: "\n")
        let cache = try sourceText("timetracker/Services/SystemIntegration/WidgetSnapshotCache.swift")

        #expect(widget.contains("context.isPreview"))
        #expect(widget.contains("WidgetSnapshotTimelinePolicy"))
        #expect(widget.contains("clockAdjusted"))
        #expect(widget.contains("WidgetElapsedFormatter.clock"))
        #expect(widget.contains("policy: .never"))
        #expect(widget.contains(".privacySensitive()"))
        #expect(widget.contains("minHeight: 44"))
        #expect(widget.contains(".widgetURL(WidgetDeepLinks.today)"))
        #expect(widget.contains("Link(destination: WidgetDeepLinks.startTimer(taskID: task.taskID))"))
        #expect(widget.contains("private var widgetURL") == false)
        #expect(!widget.contains("byAdding: .minute"))
        #expect(cache.contains("reloadTimelines(ofKind: SharedWidgetSnapshotStore.widgetKind)"))
    }

    @Test @MainActor
    func widgetSnapshotUsesLedgerAndTaskReadModelsWithoutSwiftDataInWidget() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Widget task",
            parentID: nil,
            colorHex: "#34C759",
            iconName: "checkmark.circle"
        )
        let segment = try timeRepository.startTask(taskID: task.id, source: .timer)

        let snapshot = WidgetSnapshotCache.snapshot(
            activeSegments: [segment],
            taskByID: [task.id: task],
            taskParentPathByID: [task.id: "Work"],
            todayGrossSeconds: 120,
            todayWallSeconds: 120,
            generatedAt: segment.startedAt
        )

        #expect(snapshot.activeTimers.map(\.id) == [segment.id])
        #expect(snapshot.activeTimers.map(\.title) == ["Widget task"])
        #expect(snapshot.activeTimers.map(\.path) == ["Work"])
        #expect(snapshot.activeTimers.map(\.colorHex) == ["#34C759"])
        #expect(snapshot.activeTimers.map(\.iconName) == ["checkmark.circle"])
    }

    @Test @MainActor
    func widgetSnapshotIncludesRecentTaskQuickStartModels() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let first = try taskRepository.createTask(
            title: "First recent task",
            parentID: nil,
            colorHex: "#0A84FF",
            iconName: "bolt"
        )
        let second = try taskRepository.createTask(
            title: "Second recent task",
            parentID: nil,
            colorHex: "#BF5AF2",
            iconName: "book"
        )

        let snapshot = WidgetSnapshotCache.snapshot(
            activeSegments: [],
            taskByID: [first.id: first, second.id: second],
            taskParentPathByID: [
                first.id: "Work",
                second.id: "Study",
            ],
            recentTasks: [first, second],
            todayGrossSeconds: 0,
            todayWallSeconds: 0,
            generatedAt: Date(timeIntervalSinceReferenceDate: 20000)
        )

        #expect(snapshot.recentTasks.map(\.taskID) == [first.id, second.id])
        #expect(snapshot.recentTasks.map(\.title) == ["First recent task", "Second recent task"])
        #expect(snapshot.recentTasks.map(\.path) == ["Work", "Study"])
        #expect(snapshot.recentTasks.map(\.iconName) == ["bolt", "book"])
        #expect(snapshot.recentTasks.map(\.colorHex) == ["#0A84FF", "#BF5AF2"])
    }

    @Test @MainActor
    func widgetSnapshotProjectionFitsTransportLimitsWithoutBreakingUnicode() throws {
        let generatedAt = Date(timeIntervalSinceReferenceDate: 40000)
        let longTitle = String(repeating: "🧑🏽‍💻", count: 1000)
        let longPath = String(repeating: "工作／项目／", count: 2000)
        let longStyle = String(repeating: "x", count: 1000)
        let task = TaskNode(
            title: longTitle,
            parentID: nil,
            deviceID: "test",
            colorHex: longStyle,
            iconName: longStyle
        )
        let segments = (0 ... WidgetSnapshotLimits.maximumActiveTimers).map { index in
            let startedAt: Date = switch index {
            case 0:
                generatedAt.addingTimeInterval(60)
            case 1:
                generatedAt.addingTimeInterval(
                    -WidgetSnapshotLimits.maximumActiveTimerAge - 60
                )
            default:
                generatedAt.addingTimeInterval(-60)
            }
            return TimeSegment(
                sessionID: UUID(),
                taskID: task.id,
                source: .timer,
                deviceID: "test",
                startedAt: startedAt
            )
        }

        let snapshot = WidgetSnapshotCache.snapshot(
            activeSegments: segments,
            taskByID: [task.id: task],
            taskParentPathByID: [task.id: longPath],
            recentTasks: [task],
            todayGrossSeconds: -1,
            todayWallSeconds: Int.max,
            generatedAt: generatedAt
        )

        #expect(snapshot.todayGrossSeconds == 0)
        #expect(snapshot.todayWallSeconds == WidgetSnapshotLimits.maximumSummarySeconds)
        #expect(snapshot.activeTimers.count == WidgetSnapshotLimits.maximumActiveTimers)
        #expect(snapshot.activeTimers[0].startedAt == generatedAt)
        #expect(
            snapshot.activeTimers[1].startedAt == generatedAt.addingTimeInterval(
                -WidgetSnapshotLimits.maximumActiveTimerAge
            )
        )
        let titlesAreBounded = snapshot.activeTimers.allSatisfy {
            $0.title.utf8.count <= WidgetSnapshotLimits.maximumProjectedTitleBytes
        }
        let pathsAreBounded = snapshot.activeTimers.allSatisfy {
            $0.path.utf8.count <= WidgetSnapshotLimits.maximumProjectedPathBytes
        }
        let stylesAreBounded = snapshot.activeTimers.allSatisfy {
            ($0.colorHex?.utf8.count ?? 0) <= WidgetSnapshotLimits.maximumProjectedStyleValueBytes &&
                ($0.iconName?.utf8.count ?? 0) <= WidgetSnapshotLimits.maximumProjectedStyleValueBytes
        }
        let unicodePrefixesAreIntact = snapshot.activeTimers.allSatisfy {
            longTitle.hasPrefix($0.title) && longPath.hasPrefix($0.path)
        }
        #expect(titlesAreBounded)
        #expect(pathsAreBounded)
        #expect(stylesAreBounded)
        #expect(unicodePrefixesAreIntact)
        #expect(snapshot.isStructurallyValid)
        let encodedSnapshot = try JSONEncoder().encode(snapshot)
        #expect(encodedSnapshot.count <= WidgetSnapshotLimits.maximumEncodedBytes)

        var textHeavySnapshot = snapshot
        textHeavySnapshot.recentTasks = (0 ..< WidgetSnapshotLimits.maximumRecentTasks).map { _ in
            WidgetRecentTaskSnapshot(
                taskID: UUID(),
                title: String(repeating: "t", count: WidgetSnapshotLimits.maximumProjectedTitleBytes),
                path: String(repeating: "p", count: WidgetSnapshotLimits.maximumProjectedPathBytes),
                colorHex: nil,
                iconName: nil
            )
        }
        #expect(textHeavySnapshot.recentTasks.allSatisfy { $0.isStructurallyValid })
        #expect(textHeavySnapshot.isStructurallyValid == false)
    }
}

private func readAppGroups(in url: URL) throws -> Set<String> {
    let data = try Data(contentsOf: url)
    let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    let dictionary = try #require(plist as? [String: Any])
    return Set(dictionary["com.apple.security.application-groups"] as? [String] ?? [])
}
