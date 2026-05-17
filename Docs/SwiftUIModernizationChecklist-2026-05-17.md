# SwiftUI Modernization Checklist - 2026-05-17

This file is the continuity checklist for the refactor branch. Keep it current after every small refactor commit. If context is compacted or work is resumed later, start here, rerun the scan commands below, and continue from the unchecked items rather than from memory.

Branch: `codex/swiftui-modernization-2026-05-17`

## Scan Scope

- [x] Created a dedicated refactor branch.
- [x] Scanned all Swift source files with `rg --files --glob '*.swift'`.
- [x] Counted Swift scope: 267 Swift files, 34,328 total Swift lines including app, extensions, watch app, widgets, shared live activity code, unit tests, and UI tests.
- [x] Ran the complexity scanner: `python3 /Users/gaozexuan/.codex/skills/complexity-optimizer/scripts/analyze_complexity.py /Users/gaozexuan/Developer/timetracker --format markdown`.
- [x] Searched production Swift for deprecated or legacy patterns: `foregroundColor`, `cornerRadius`, `NavigationView`, old toolbar placements, `Task.sleep(nanoseconds:)`, `DispatchQueue`, UIKit search wrappers, `TextEditor`, `ForEach(Array(...enumerated()))`, `GeometryReader`, `onTapGesture`, `AnyView`, and `String(format:)`.
- [x] Reviewed existing architecture docs: `Docs/CodeRefactorPlan.md`, `Docs/NativeUIPlan.md`, and source-layout contract tests.

## Apple Documentation Consulted

Use these links as the source of truth while refactoring:

- [SwiftUI `foregroundColor(_:)`](https://developer.apple.com/documentation/swiftui/view/foregroundcolor%28_%3A%29/) says to use `foregroundStyle(_:)` instead.
- [SwiftUI `foregroundStyle(_:)`](https://developer.apple.com/documentation/swiftui/view/foregroundstyle%28_%3A%29) styles foreground content such as text, symbols, and shapes.
- [Swift `Task.sleep(for:tolerance:clock:)`](https://developer.apple.com/documentation/swift/task/sleep%28for%3Atolerance%3Aclock%3A%29) suspends the current task using a `Duration`.
- [Swift `Duration`](https://developer.apple.com/documentation/swift/duration) documents `.seconds`, `.milliseconds`, and related factories.
- [SwiftUI `searchable(text:placement:prompt:)`](https://developer.apple.com/documentation/swiftui/view/searchable%28text%3Aplacement%3Aprompt%3A%29-1bjj3) configures the native search field for a view hierarchy.
- [SwiftUI `TextField`](https://developer.apple.com/documentation/swiftui/textfield) includes axis-based multiline initializers.
- [SwiftUI `Form`](https://developer.apple.com/documentation/swiftui/form) applies platform-appropriate styling to settings and data-entry controls.
- [SwiftUI `LabeledContent`](https://developer.apple.com/documentation/swiftui/labeledcontent) aligns labels and value-bearing controls consistently, especially in forms.
- [SwiftUI `ContentUnavailableView`](https://developer.apple.com/documentation/swiftui/contentunavailableview) is recommended for empty, error, and unavailable states.
- [SwiftUI `NavigationView`](https://developer.apple.com/documentation/swiftui/navigationview) is deprecated in favor of `NavigationStack` and `NavigationSplitView`.
- [SwiftUI `NavigationStack`](https://developer.apple.com/documentation/swiftui/navigationstack) and [SwiftUI `NavigationSplitView`](https://developer.apple.com/documentation/swiftui/navigationsplitview) are the modern navigation containers.
- [Observation `@Observable`](https://developer.apple.com/documentation/observation/observable) is the modern observation model, but migrating the app facade requires a separate behavior-preserving pass.
- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance) says to use Instruments to find long view body updates and frequent updates.
- [Xcode performance and testing tools](https://developer.apple.com/documentation/xcode/) documents Simulator, Instruments, Accessibility Inspector, and testing workflows.
- [HIG Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode) recommends respecting the system appearance and using adaptive colors.
- [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) calls out Dynamic Type, contrast, and minimum control sizes.
- [HIG Lists and Tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) recommends platform list/table conventions for hierarchical and editable data.

## Active Refactor Checklist

- [x] Baseline build/test: run `xcodebuild test -scheme timetracker -destination 'platform=macOS'` or the closest available Apple destination, then record failures here.
- [x] Replace `Task.sleep(nanoseconds:)` with `Task.sleep(for:)` in production code.
- [x] Replace remaining `DispatchQueue` main-thread delays with Swift concurrency where behavior is equivalent.
- [x] Replace the custom UIKit `SystemSearchBar` in Tasks with native `.searchable`, unless a verified platform bug requires keeping the wrapper.
- [ ] Replace safe `ForEach(Array(values.enumerated()))` cases with modern direct enumeration or a stable indexed helper after compiler verification.
- [ ] Replace `.cornerRadius(...)` in production SwiftUI with `.clipShape(.rect(cornerRadius: ...))`.
- [ ] Review `TextEditor` note fields and replace with `TextField(..., axis: .vertical)` where full text-view behavior is not required.
- [ ] Audit `onTapGesture` rows and convert to `Button` or add complete accessibility traits/actions when nested controls make a button wrapper unsafe.
- [ ] Split files over the existing size budget where a split can be behavior-preserving: `AnalyticsViews.swift`, `PhoneChromeViews.swift`, `SettingsSectionsViews.swift`, `TaskDetailView.swift`, `TaskDetailEditorViews.swift`, and `TasksViews.swift`.
- [ ] Review macOS Settings appearance in light and dark mode against HIG Dark Mode. Prefer adaptive system colors and native `Form`/`LabeledContent`; avoid forcing a custom dark-only surface.
- [ ] Profile the hot user paths in a Release build with Instruments SwiftUI template: Today, Tasks search, task detail, Analytics, Settings, Pomodoro.
- [ ] Reconcile outdated source-string UI contract tests with current intended UI before using them as blockers.
- [ ] Evaluate a gradual migration from `ObservableObject`/`@Published` facade state to Observation or narrower domain view models. Do not do this as a drive-by edit.

## Complexity Findings

- `App/SeedData+Cleanup.swift`: scanner flags many query/delete loops. This path is maintenance-only, but it should be checked for batch-safe SwiftData cleanup if it becomes slow.
- `App/RootViews/PhoneChromeViews.swift`: many scanner warnings are false positives from SwiftUI closures and custom bottom chrome. Keep the custom bottom bar because it is product-specific, but preserve stable identity and Reduce Motion behavior.
- `Stores/Facade/TimeTrackerStore+LedgerReadModels.swift` and home metrics: repeated derived values are used in frequently refreshed views. Prefer cached domain snapshots over recomputing broad rollups in `TimelineView` bodies.
- `Services/SystemIntegration/SyncConflictService.swift`: very large file with serialization, hashing, restore, and conflict state. Split by responsibility before adding behavior.
- `Features/Analytics/*`: chart/timeline rendering is custom by necessity; keep calculations in services and profile view body churn before visual rewrites.

## Commit Discipline

Every completed item above should be its own small commit when practical. Each commit should include only the code and test/documentation updates needed for that item, so future reversions are precise.

## Verification Log

- 2026-05-17: Baseline `xcodebuild test -scheme timetracker -destination 'platform=macOS'` compiled successfully but failed before code refactors with existing failures in `timetrackerUITests.testPrimaryNavigationAndSettingsLoad`, `timetrackerUITests.testUIRefactorBaselineScreenshots`, outdated phone/home UI contract assertions, analytics source-contract assertions, `InboxUIContractTests.inboxUsesOwnDestinationAndSmoothInlineCapture`, `TaskCategoryTests.taskTreeShowsEmptyCategories`, and `CoreSourceLayoutTests.analyticsServiceFilesStaySplitByResponsibility`.
- 2026-05-17: After replacing `Task.sleep(nanoseconds:)`, `xcodebuild test -scheme timetracker -destination 'platform=macOS' -only-testing:timetrackerTests/PomodoroTests` succeeded.
- 2026-05-17: After replacing remaining production `DispatchQueue` delays, `rg -n "DispatchQueue" timetracker timetrackerWatchApp timetrackerWidgetExtension timetrackerLiveActivityExtension SharedLiveActivity timetrackerTests --glob '*.swift'` only finds the negative contract assertion, and `xcodebuild test -scheme timetracker -destination 'platform=macOS' -only-testing:timetrackerTests/TaskUIContractTests/sidebarSelectionSyncDoesNotRevealProgrammaticTaskSelection -only-testing:timetrackerTests/SharedComponentsContractTests/selectedTaskPulseIsSharedForSidebarRows` succeeded. Xcode warned that some `CoreWatchCommandTests` `Equatable` conformances touch main-actor-isolated properties; treat that as a future Swift 6 migration blocker.
- 2026-05-17: After replacing the Tasks UIKit `SystemSearchBar` wrapper with SwiftUI `.searchable`, `xcodebuild test -scheme timetracker -destination 'platform=macOS' -only-testing:timetrackerTests/TaskUIContractTests/tasksSearchUsesNativeSearchableInsteadOfUIKitWrapper` succeeded, and `xcodebuild build -scheme timetracker -destination 'generic/platform=iOS'` succeeded.
