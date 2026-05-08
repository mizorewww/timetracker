import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct HomeUIContractTests {
    @Test @MainActor
    func quickStartRecentTasksRankByFrequencyAndSkipPinnedTasks() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pinnedTask = try taskRepository.createTask(title: "Pinned", parentID: nil, colorHex: nil, iconName: nil)
        let frequentTask = try taskRepository.createTask(title: "Frequent", parentID: nil, colorHex: nil, iconName: nil)
        let occasionalTask = try taskRepository.createTask(title: "Occasional", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date(timeIntervalSince1970: 10_000)

        _ = try timeRepository.addManualSegment(
            taskID: occasionalTask.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: frequentTask.id,
            startedAt: start.addingTimeInterval(1_000),
            endedAt: start.addingTimeInterval(1_600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: frequentTask.id,
            startedAt: start.addingTimeInterval(2_000),
            endedAt: start.addingTimeInterval(2_600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: pinnedTask.id,
            startedAt: start.addingTimeInterval(3_000),
            endedAt: start.addingTimeInterval(3_600),
            note: nil
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        let quickStartTasks = store.frequentRecentTasks(excluding: [pinnedTask.id], limit: 2)

        #expect(quickStartTasks.map(\.id) == [frequentTask.id, occasionalTask.id])
    }

    @Test @MainActor
    func regularWidthIOSUsesVisibleSystemSplitView() throws {
        let source = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")

        #expect(SplitColumnLayoutPolicy.iPad.sidebar == ColumnWidth(min: 240, ideal: 260, max: 300))
        #expect(SplitColumnLayoutPolicy.iPad.detail.min == 560)
        #expect(source.contains("iPadRootView(store: store)"))
        #expect(source.contains("struct iPadRootView"))
        #expect(source.contains("ipad.splitNavigation"))
        #expect(source.contains("SplitColumnLayoutPolicy.iPad"))
        #expect(source.contains(".navigationSplitViewColumnWidth("))
        #expect(source.contains("NavigationSplitView(columnVisibility: $columnVisibility)"))
        #expect(source.contains("ToolbarItem(placement: .topBarLeading)"))
        #expect(source.contains("if columnVisibility == .detailOnly"))
        #expect(source.contains("\"sidebar.left\""))
        #expect(source.contains(".navigationSplitViewStyle(.balanced)"))
        #expect(source.contains(".tabViewStyle(.sidebarAdaptable)") == false)
        #expect(source.contains("ipad.topNavigation") == false)
        #expect(source.contains(".overlay(alignment: .topLeading)") == false)
    }

    @Test
    func phoneHomeUsesSystemLargeTitle() throws {
        let source = try sourceText("timetracker/Features/Home/HomeViews.swift")

        guard
            let start = source.range(of: "struct PhoneHomeView"),
            let end = source.range(of: "struct HeaderBar")
        else {
            Issue.record("Could not locate PhoneHomeView")
            return
        }
        let phoneHome = String(source[start.lowerBound..<end.lowerBound])

        #expect(phoneHome.contains(".navigationTitle(AppStrings.today)"))
        #expect(phoneHome.contains(".navigationBarTitleDisplayMode(.large)"))
        #expect(phoneHome.contains(".padding(.top, 10)") == false)
        #expect(phoneHome.contains("HeaderBar(store: store") == false)
    }

    @Test
    func phoneTabsStayAtFiveAndSettingsUsesHomeToolbar() throws {
        let contentSource = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")
        let homeSource = try sourceText("timetracker/Features/Home/HomeViews.swift")
        let phoneRoot = try #require(contentSource.slice(from: "struct PhoneRootView", to: "struct iPadRootView"))
        let phoneHome = try #require(homeSource.slice(from: "struct PhoneHomeView", to: "struct HeaderBar"))

        #expect(phoneRoot.components(separatedBy: ".tabItem").count - 1 == 5)
        #expect(phoneRoot.contains("SettingsView(store: store)") == false)
        #expect(phoneRoot.contains("Label(AppStrings.settings") == false)
        #expect(phoneHome.contains("Image(systemName: \"gearshape\")"))
        #expect(phoneHome.contains(".sheet(isPresented: $showsSettings)"))
        #expect(phoneHome.contains("SettingsView(store: store)"))
    }

    @Test
    func quickStartComposesPinnedAndFrequentRecentTasks() throws {
        let homeSource = try [
            "timetracker/Features/Home/Sections/HomeQuickStartViews.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartButtons.swift",
            "timetracker/Features/Home/Sections/HomeQuickStartEditorViews.swift"
        ]
            .map(sourceText)
            .joined(separator: "\n")
        let storeSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+TaskReadModels.swift")

        #expect(homeSource.contains("private var pinnedTasks"))
        #expect(homeSource.contains("private var recentFillTasks"))
        #expect(homeSource.contains("limit: 3"))
        #expect(homeSource.contains("QuickStartTaskButton"))
        #expect(homeSource.contains("private let maxPinnedTasks = 3") == false)
        #expect(homeSource.contains("QuickStartSelectableTaskRow"))
        #expect(homeSource.contains("selectedIDs.append(task.id)"))
        #expect(homeSource.contains("selectedIDs.remove(atOffsets: offsets)"))
        #expect(storeSource.contains("func frequentRecentTasks(excluding excludedIDs: Set<UUID> = [], limit: Int = 3)"))
    }

    @Test
    func homePlacesQuickStartBeforeTimeline() throws {
        let source = try sourceText("timetracker/Features/Home/HomeViews.swift")

        guard
            let desktopStart = source.range(of: "struct DesktopMainView"),
            let phoneStart = source.range(of: "struct PhoneHomeView"),
            let headerStart = source.range(of: "struct HeaderBar")
        else {
            Issue.record("Could not locate home view sections")
            return
        }

        let desktopMain = String(source[desktopStart.lowerBound..<phoneStart.lowerBound])
        let phoneHome = String(source[phoneStart.lowerBound..<headerStart.lowerBound])
        let desktopQuickStart = try #require(desktopMain.range(of: "QuickStartSection(store: store)")?.lowerBound)
        let desktopTimeline = try #require(desktopMain.range(of: "TimelineSection(store: store)")?.lowerBound)
        let phoneQuickStart = try #require(phoneHome.range(of: "QuickStartSection(store: store)")?.lowerBound)
        let phoneTimeline = try #require(phoneHome.range(of: "TimelineSection(store: store)")?.lowerBound)

        #expect(desktopQuickStart < desktopTimeline)
        #expect(phoneQuickStart < phoneTimeline)
    }

    @Test
    func compactTaskPickerUsesOpaqueSystemSheet() throws {
        let source = try sourceText("timetracker/Features/Home/Controls/HomeActionsViews.swift")

        #expect(source.contains(".presentationBackground(Color(uiColor: .systemGroupedBackground))"))
        #expect(source.contains(".scrollContentBackground(.hidden)"))
    }

    @Test
    func todayMetricsUseSemanticTrendColorsAndEqualCompactActions() throws {
        let source = try [
            "timetracker/Features/Home/Sections/HomeMetricsViews.swift",
            "timetracker/Features/Home/Controls/HomeActionsViews.swift",
            "timetracker/SharedUI/Components/MetricCards.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
        let homeMetricsSource = try sourceText("timetracker/Features/Home/Sections/HomeMetricsViews.swift")
        let sharedMetricsSource = try sourceText("timetracker/SharedUI/Components/MetricCards.swift")

        #expect(source.contains("trendColor: grossTrend.color"))
        #expect(source.contains(".foregroundStyle(metric.trendColor)"))
        #expect(source.contains(".green"))
        #expect(source.contains(".red"))
        #expect(sharedMetricsSource.contains("struct MetricCell"))
        #expect(sharedMetricsSource.contains("struct MetricSummaryItem"))
        #expect(homeMetricsSource.contains("struct MetricCell") == false)
        #expect(source.contains("startButton\n                    .frame(maxWidth: .infinity)"))
        #expect(source.contains("newTaskButton\n                    .frame(maxWidth: .infinity)"))
        #expect(source.contains(".layoutPriority(1.1)") == false)
    }
}
