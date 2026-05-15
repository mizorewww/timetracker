# UI and Operation Refactor Plan

This document is the working memory for the UI/operation refactor. Keep it updated after every solved item by changing `[ ]` to `[x]`, adding the verification command or screenshot note, and recording any remaining risk. If context is compacted, resume from the highest unchecked item in "Execution Checklist".

## Product Intent

The app records what the user did in real life and when they did it. The UI should help the user answer three questions quickly:

1. What am I doing now?
2. What did I spend time on during a chosen day/week/month?
3. Which task deserves the next action?

This means the app is not a generic task manager. Time evidence, day context, and low-friction capture are more important than decorative dashboards.

## Context-Persistence Protocol

- Treat this document as the source of truth for the refactor sequence.
- Before changing UI, add or update a UI contract test that locks the intended behavior.
- After changing UI, run the smallest relevant test slice first, then broader build/tests.
- After every simulator/screenshot pass, append device, command, file path, observations, and next fix.
- Baseline simulator/app screenshots must happen before any new image generation. The image-generation prompt must reference the real screenshots and the app intent, then the generated design becomes a direction to implement and verify back in the simulators.
- Baseline screenshots must use representative demo data. The app reads `TimeTrackerAutomaticDemoDataMode` from the generated Info.plist via `TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE`: Debug defaults to `seedIfEmpty`, Release defaults to `off`, and screenshot builds may override it to `replaceOnLaunch`.
- Demo-data modes force a local store before seeding so screenshot/demo data is never written into iCloud.
- Do not move date navigation to Home unless the product goal explicitly changes. Date navigation belongs in Analytics.
- Task row tap must open Task Detail. Editing is a secondary action inside detail, swipe actions, or context menus.
- If context is compacted, run `git status --short --branch`, read this document, and continue from the first unchecked item.

## TDD Loop

1. Write/adjust contract tests that express the desired UI/operation behavior.
2. Run the failing or targeted tests.
3. Implement the narrow UI or logic change.
4. Run the targeted tests again.
5. Build and run baseline platform screenshots before image generation.
6. Analyze screenshots and write the prompt with concrete current-UI problems.
7. Generate design references using the screenshots plus product intent.
8. Implement the UI change and verify with new platform screenshots.
9. Update this document with `[x]`, commands, and screenshot notes.

## UI Inventory

### Root Navigation

- iPhone: `TabView` with Home, Inbox, Tasks, Pomodoro, Analytics.
- iPad/macOS: `NavigationSplitView` with Sidebar and detail destination.
- Global sheets in `ContentView`: task editor, category editor, manual time, segment editor, inbox suggestion editor, start-task picker on iOS.
- macOS command menu: new task, add time, start selected task, start pomodoro, refresh.

Fit check:

- Home as first tab is right because it is the live capture cockpit.
- Analytics as its own tab is right because historical date/range choice is a decision context.
- Settings inside Home toolbar on iPhone is discoverable enough but should not compete with timer controls.
- Global sheet routing is acceptable, but Task Detail should reduce surprise by showing edit state inline or clearly behind an edit affordance.

### Home

Content:

- Today metrics: tracked, wall time, gross time.
- Start timer and new task actions.
- day progress.
- forecast summary.
- active timers.
- paused sessions.
- quick start.
- today timeline.
- selected-task inspector summary on phone.

Operations:

- Start selected task or open task picker on compact iPhone.
- Create new task.
- Open settings on phone.
- Active timer row tap selects task.
- Active timer pause/stop.
- Paused session row tap selects task.
- Paused session resume/stop.
- Timeline row tap selects task.
- Timeline context menu edits/adds similar/deletes segment.
- Quick start task starts task.
- Quick start editor pins/reorders shortcuts.

Fit check:

- Home should remain live "today only"; date switching here confuses the capture cockpit.
- Existing timeline row tap only selects task, not detail. This is acceptable on desktop with inspector, weaker on phone because selection feedback is not obvious.
- Start timer is primary. New task is secondary.

### Analytics

Content:

- Range picker: today/week/month.
- Period control: previous/next, date picker, current period.
- Decision summary insights.
- Overview metrics with comparison.
- Forecast/next-step section.
- Task/root/category distribution.
- Today hour distribution or daily trend.
- Rhythm and quality cards.
- Overlap timeline.

Operations:

- Switch range.
- Move selected analysis period backward/forward.
- Pick a date inside target period.
- Jump back to current period.
- Forecast row tap selects task.

Fit check:

- Date navigation belongs here and must be visually tied to analytics period.
- The decision summary should be above chart details.
- Gross/wall/overlap need short explanations because the terms are powerful but non-obvious.
- Forecast should read as next action, not passive statistics.

### Tasks

Content:

- Searchable task tree grouped by category.
- Category header with add/edit category.
- Task rows with icon, title, path, checklist/forecast, total time, child count, status.
- Add root task and category actions.

Operations:

- Row tap selects task and opens Task Detail.
- Disclosure button expands/collapses tree.
- Swipe leading starts task or creates subtask.
- Swipe trailing edits or deletes.
- Context menu starts task, adds subtask, adds manual time, changes status, edits, archives, deletes.
- Toolbar menu creates root task or category.

Fit check:

- Row tap as detail is correct. Editing on tap is wrong for a list because it blocks browsing and analysis.
- Current row packs too many facts into one horizontal line on compact widths. Status text is especially likely to float or crowd.
- Row should show status as a compact trailing pill or secondary metadata, never as a standalone block that steals reading order.

### Task Detail

Content:

- Header with icon, title, path, running/status, start timer, add time.
- Inline editor.
- Overview metrics.
- Forecast panel.
- Task analysis range.
- Direct vs child contribution.
- Rhythm/quality metrics.
- Child breakdown.
- Recent records.

Operations:

- Start timer.
- Add manual time.
- Edit title/status/parent/category/icon/color/estimate/due/checklist/notes.
- Save/reset edits.
- Switch task analysis range.

Fit check:

- Detail and edit can be merged, but read mode and edit controls need strong hierarchy.
- Current merged editor appears as a large card immediately under the header, which can make the detail page feel like an edit form rather than a detail/analysis page.
- Better model: top summary is read-first; editable basics live in native grouped sections with Save/Reset only when dirty.
- Status should be a segmented/menu control in a labeled row. Long explanatory status text belongs in help text, not the primary detail surface.

### Inbox

Content:

- Header/subtitle.
- Capture row.
- Open and completed items.
- Suggestion bar/failure/generating states.
- Footer hint.

Operations:

- Add inbox item.
- Edit inbox title inline.
- Complete/reopen.
- Delete.
- Sort open items.
- Apply/discard/retry generated suggestion.

Fit check:

- Capture row at top is right.
- Footer help is useful but should stay quiet and not become the visual center.
- Fixed-height list rows risk clipping with long text or localized strings.

### Inspector

Content:

- Selected task summary.
- Notes.
- Stats.
- Pomodoro settings.
- Recent sessions.
- Forecast.
- Info.
- Checklist.
- Action buttons.

Operations:

- Start task.
- Add manual time.
- Start pomodoro.
- Edit task.
- Archive/delete.
- Toggle checklist items.
- Toggle auto-start break.

Fit check:

- Inspector makes sense for desktop/iPad Home, but should not become the only way to inspect a task.
- Task Detail should be the canonical single-task surface; inspector is a quick side panel.

### Ledger Sheets

Content:

- Manual time form.
- Segment edit form.

Operations:

- Pick task.
- Set start/end.
- Toggle active segment in edit.
- Add note.
- Save/cancel/delete segment.

Fit check:

- Sheets are appropriate because these are transactional edits.
- Needs stable validation and clear destructive confirmation if delete becomes easier to trigger.

### Pomodoro

Content:

- Active pomodoro card.
- Setup card with task, preset, focus/break/round controls.
- Recent runs.

Operations:

- Choose task.
- Apply preset.
- Edit minutes/rounds.
- Start/pause/resume/stop.

Fit check:

- Pomodoro is a focused workflow. It should stay calmer and more singular than Analytics.

### Settings

Content:

- Display/timing.
- Pomodoro defaults.
- Countdown events.
- Data: export CSV, add time, optimize database.
- Sync.
- LLM settings.
- Maintenance.
- About.

Operations:

- Export CSV.
- Add manual time.
- Optimize database with confirmation.
- Toggle iCloud sync.
- Check/force sync.
- Fetch LLM models.
- Rebuild/clear demo data with confirmation.

Fit check:

- CSV export belongs in Data and toolbar.
- Destructive maintenance actions need confirmations, which currently exist.
- LLM settings are technical; keep them lower in the form.

### Sidebar

Content:

- Destinations.
- Task tree shortcuts.

Operations:

- Switch destination.
- Select task.
- Context menu task operations.

Fit check:

- Sidebar is navigation and selection, not editing.
- Task context menus are okay here because desktop users expect secondary actions.

### Watch and Widget

Content:

- Watch shortcuts, running timer, reachability, empty states.
- Widget active timer and empty states.

Operations:

- Watch start shortcut.
- Watch active timer action.

Fit check:

- Watch/widget should remain glanceable and not inherit the full refactor unless shared models break them.

## Operation Logic Inventory

### Capture and Timer

- `presentManualTime`, `saveManualTimeDraft`, `presentEditSegment`, `saveSegmentDraft`.
- `startTask`, `startSelectedTask`, `pause`, `resume`, `stop`.
- Deep links and watch commands route into the same store commands.

Risk:

- Moving buttons between screens should not change command calls.
- Row tap vs button tap must not trigger both parent row and child button actions.

### Task Management

- `presentNewTask`, `presentEditTask`, `saveTaskDraft`.
- `selectTask(task.id, revealInToday:)`.
- `setTaskStatus`, archive/delete, category editing, hierarchy expansion.

Risk:

- Detail navigation must preserve selection without forcing Home reveal.
- Inline Task Detail edits must reset after save and not hold stale drafts.
- Parent/category pickers must not allow invalid hierarchy.

### Analytics

- `analyticsSnapshot(for:now:)`.
- `taskAnalyticsSnapshot(for:range:now:)`.
- Date anchor is passed as `now` to snapshot builder for selected period.

Risk:

- Past periods must not be accidentally computed as current live day.
- Active segments need deterministic clipping for selected periods.

### Inbox and Suggestions

- `addInboxItem`, `toggleInboxItem`, `updateInboxItem`, `deleteInboxItem`, `reorderInboxItems`.
- suggestion apply/discard/retry.

Risk:

- Swipe actions and inline edit should not conflict.
- Generated suggestion UI should not make completing/deleting ambiguous.

### Settings and Maintenance

- Preferences bindings mutate store preferences.
- File export pulls `store.csvExport()`.
- Demo rebuild/clear and optimize are destructive/maintenance actions behind confirmation dialogs.

Risk:

- Toolbar export and section export should stay equivalent.
- Confirmations must remain around destructive actions.

## Design Direction

Apple-native, calm, practical, information-dense:

- Use grouped lists/forms where the user is editing settings or task details.
- Use plain section bands and list rows for repeated data.
- Use cards only for metric groups, repeated insight cards, and framed analytical charts.
- Keep border radius at or below 8 unless using platform-native grouped form backgrounds.
- Prefer SF Symbols in buttons and rows.
- Avoid card-inside-card layouts.
- Avoid decorative gradients and ornamental backgrounds.
- Put date/range controls next to the data they control.
- Make primary action obvious: Start Timer on Home and Task Detail; period selection on Analytics.

## Screenshot-First Design Reference Workflow

Do not generate design references from abstract prompts alone. The correct loop is:

1. Launch the app on iPhone, iPad, and macOS targets.
2. For screenshot builds, use `TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE=replaceOnLaunch` or a Debug build with an empty local store, so the UI is populated with stable demo data.
3. Capture baseline screenshots of the current UI, especially Home, Analytics, Tasks, and Task Detail.
4. Write observations in "Screenshot Log": what is confusing, what is visually broken, and which user decision is blocked.
5. Create the image-generation prompt from the real screenshots. The prompt must tell the image tool the product intent and specific current problems.
6. Generate Apple-native design references using those screenshots as visual input.
7. Implement the SwiftUI changes.
8. Relaunch and recapture screenshots until the blocking layout issues are gone.

The composite image generated before baseline screenshots on 2026-05-15 is invalid as an implementation reference. Keep it only as a record of the wrong sequence.

## Image Generation Prompts

Use these prompts to create visual design references before implementation. Attach the matching baseline screenshots when the image tool supports image input. If the image tool is text-only, translate the Screenshot Log observations into the prompt and explicitly say that the previous abstract composite is invalid.

### Prompt A: iPhone

Use `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-home-baseline.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-analytics-baseline.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-tasks-baseline.png`, and `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-task-detail-baseline.png` as the current UI references. Create an Apple-native iPhone app design mockup for a personal time tracking app that records real-life activities by task and time. Show Today cockpit, Analytics for a selected date, Tasks, and Task Detail. Preserve the useful date controls in Analytics; do not add historical date switching to Home. Fix the current problems: oversized top spacing on Home, forecast explanation consuming too much first-screen height, Analytics cards reading as a wall of equal boxes, task rows with status/time/path competing, and Task Detail opening as an edit form with a broken multi-selected status row. Use iOS grouped navigation, SF Symbols, native segmented controls or menus, clean grouped lists, compact metric cards, readable Chinese labels, no marketing hero, no decorative gradients. Task Detail must be read-first: task summary, start timer, add time, overview, forecast/analysis/recent evidence, then compact editable basics. Calm productivity palette, mostly system backgrounds, blue/green/orange accents, dense but elegant, Apple Human Interface Guidelines style.

### Prompt B: iPad

Use `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-home-baseline.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-analytics-baseline.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-tasks-baseline.png`, and `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-task-detail-baseline.png` as the current UI references. Create an Apple-native iPad time tracking app design mockup in landscape. Use NavigationSplitView with sidebar destinations and task tree, main content showing Analytics for a selected week, optional inspector panel. The app purpose is to help a user understand where real-life time went and decide what task to adjust next. Preserve Analytics date/range navigation and make the selected period unmistakable. Fix current problems: card-heavy Analytics, read/edit hierarchy inverted in Task Detail, the task status row looking broken, and task rows spreading status/time too far across wide layouts. Show period controls, insight cards, root/category distribution, rhythm and quality panels, and read-first task detail. Use native materials, grouped tables, SF Symbols, compact typography, no decorative hero or gradient blobs, no nested cards. Chinese interface labels, clear hierarchy, professional utility app.

### Prompt C: macOS

Use `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-home-baseline.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-analytics-baseline.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-tasks-baseline.png`, and `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-task-detail-baseline.png` as the current UI references. Create an Apple-native macOS SwiftUI productivity app mockup for time tracking. Three-column layout: sidebar navigation, main task detail or analytics workspace, right inspector. Purpose: record what task the user did at what time and analyze past days/weeks/months for decisions. Preserve the clear macOS Analytics period controls. Fix current problems: dense dark-mode Home competing with inspector, Analytics cards lacking a glossary/hierarchy, task list status/time floating at row edges, and Task Detail opening as a giant editor instead of a readable evidence page. Use macOS toolbar, sidebar selection, table/list rows, compact cards only for metrics, native controls, clear date navigation in Analytics, task detail with summary and inline edit sections. Calm system gray background, SF Symbols, small precise typography, Chinese UI, no marketing page, no decorative gradients.

## Execution Checklist

- [x] Create branch `codex/ui-logic-refactor`.
- [x] Inventory root navigation, screens, and operation logic in this document.
- [x] Add build-config-controlled demo data seeding for screenshot baselines; Release stays off.
- [x] Capture baseline iPhone/iPad/macOS screenshots before image generation.
- [x] Analyze baseline screenshots and update Screenshot Log.
- [ ] Generate screenshot-grounded design reference images from the prompts above.
- [x] Add/adjust UI contract tests for the refactor rules.
- [x] Sync phone tab selection with shared navigation destination so screenshot/deep-link navigation matches iPad/macOS semantics.
- [x] Fix Task Detail read/edit hierarchy and status layout.
- [x] Fix iPad/macOS sidebar task selection so clicking a sidebar task opens Task Detail instead of only selecting task context.
- [x] Fix Tasks row hierarchy so title/status/time/path do not collide.
- [x] Refine Analytics header and decision sections so selected period is unmistakable.
- [x] Add concise explanatory copy/tooltips where Analytics terms can confuse users.
- [x] Review Home for operation-only cockpit behavior and no historical date controls.
- [x] Review Inbox row sizing for localization/long text.
- [x] Run targeted tests after each area.
- [x] Run iPhone simulator screenshot pass.
- [x] Run iPad simulator screenshot pass.
- [x] Run macOS screenshot pass.
- [x] Iterate from screenshot findings until no blocking layout issue remains.
- [x] Run broader test/build pass.

## Screenshot Log

- 2026-05-15 invalidated image generation: produced one composite Apple-native design board before simulator screenshots. Do not use it as an implementation reference. Correct next step is baseline simulator/app screenshots first, then screenshot-grounded prompts.
- 2026-05-15 demo data mode: screenshot builds used `TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE=replaceOnLaunch`; Release remains `off`. Demo modes force a local store so seeded data does not touch iCloud.
- 2026-05-15 iPhone baseline:
  - Files: `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-home-baseline.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-analytics-baseline.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-tasks-baseline.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-task-detail-baseline.png`.
  - Home has correct live-cockpit purpose and no historical date controls, but top whitespace, giant buttons, and forecast explanation consume too much of the first screen.
  - Analytics now has day/week/month plus previous/date/current controls where the user needs them. The selected date is visible, but the first screen is a stack of equally weighted cards; metric meanings still need a compact glossary.
  - Tasks rows are readable but oversized. Status, running state, checklist progress, total time, and forecast compete for attention; status should live with metadata instead of feeling like an independent block.
  - Task Detail opens successfully from row tap, but the first screen is edit-heavy. The status row is visibly broken because multiple options look selected; analysis and recent evidence are below the editor.
- 2026-05-15 iPad baseline:
  - Files: `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-home-baseline.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-analytics-baseline.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-tasks-baseline.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-task-detail-baseline.png`.
  - NavigationSplitView structure is appropriate. Analytics date controls are present, but card hierarchy is flat and the decision summary visually blends into metrics.
  - Tasks page is functional but sparse across wide space; right-edge duration/status creates scan distance.
  - Task Detail repeats the same high-priority defect as iPhone/macOS: editor first, status control odd, analysis not leading.
- 2026-05-15 macOS baseline:
  - Files: `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-home-baseline.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-analytics-baseline.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-tasks-baseline.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-task-detail-baseline.png`.
  - Home is powerful but dense; the right inspector is useful only if Task Detail becomes the canonical deep surface.
  - Analytics is closest to the intended direction: period controls are obvious on macOS. It still needs hierarchy between insight, metric, distribution, rhythm, quality, and explanations for gross/wall/overlap.
  - Tasks list is efficient but status/time metadata floats to the far edge in a way that can break scan order.
  - Task Detail is the clearest broken screen: it acts like a full editor, places status buttons awkwardly, and hides the analysis promise below the fold.
- 2026-05-15 iPhone iteration 1:
  - Files: `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-home-iteration1.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-analytics-iteration1.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-tasks-iteration1.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-task-detail-iteration1.png`.
  - Analytics period controls are back where they matter: the user can move to yesterday or another selected period from Analytics without turning Home into historical mode.
  - Tasks row tap opens Task Detail. No edit sheet appears from the primary row tap.
  - Task Detail is read-first: header, start/add-time actions, and overview precede the editor. Status is a native segmented control with one selected state.
  - Remaining risk: iPhone Analytics is still card-heavy; use the generated reference and next screenshot pass to decide whether to split summary/metrics into tighter native sections.
- 2026-05-15 iPad iteration 1:
  - Files: `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-home-iteration1.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-analytics-iteration1.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-tasks-iteration1.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-task-detail-iteration1.png`.
  - iPad screenshots use demo data from `replaceOnLaunch` and have been rotated to readable landscape PNGs after `simctl io` captured the device buffer in portrait dimensions.
  - Analytics period, decision summary, metric glossary, next-task decision, and distribution are visible in one continuous workspace.
  - Tasks rows now keep status with the title/path metadata. The wide trailing edge is reserved for duration and child count only.
  - Task Detail opens from row tap and behaves as detail plus inline edit, not a surprise edit sheet.
- 2026-05-15 macOS iteration 1:
  - Files: `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-home-iteration1.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-analytics-iteration1.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-tasks-iteration1.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-task-detail-iteration1.png`.
  - Analytics shows explicit period title and gross/wall/overlap glossary immediately after metrics.
  - Tasks rows no longer strand status at the far right.
  - Task Detail now starts with summary/actions/overview before editable basics. The remaining design question is whether edit mode should become collapsible by default on wide screens.
- 2026-05-15 Inbox review:
  - The risk was fixed in code rather than screenshot iteration: Inbox rows no longer use only fixed base/suggested heights. `InboxLayoutPolicy.rowHeight(forTitle:isCompleted:hasSupplementaryContent:)` expands for long localized titles and suggestion/failure bars, while the list still keeps its predictable non-scrolling card behavior.
- 2026-05-15 iteration 2:
  - Files: `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-home-iteration2.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-analytics-iteration2.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-tasks-iteration2.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/iphone-task-detail-iteration2.png`.
  - Files: `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-home-iteration2.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-analytics-iteration2.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-tasks-iteration2.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-task-detail-iteration2.png`.
  - Files: `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-home-iteration2.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-analytics-iteration2.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-tasks-iteration2.png`, `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/mac-task-detail-iteration2.png`.
  - Fixed a screenshot automation blind spot: the iPhone analytics capture must wait for `analytics.decisionSummary` and `analytics.periodControl`, not just the tab label. The earlier mislabeled analytics screenshot was actually Home content because the wait condition was too weak.
  - Task Detail now keeps editing collapsed by default. The header pencil and the `任务信息` edit button expand the inline editor; the first screen stays focused on identity, timer actions, totals, forecast, analysis, and recent evidence.
  - Analytics decision summary is flatter and no longer sits inside another chart card. On iPhone, date/range switching is visible in Analytics and Home stays a live cockpit without historical date controls.
  - iPad and macOS screenshots show no blocking overlap in the reviewed first-screen paths. Remaining future polish is stylistic: reduce duplicate large/content titles on wide platforms only if it proves distracting in daily use.
- 2026-05-15 iPad sidebar detail fix:
  - File: `/Users/gaozexuan/Developer/timetracker/build/UIRefactorScreenshots/ipad-sidebar-task-detail-fix.png`.
  - Manual Simulator verification clicked a visible task in the iPad sidebar and confirmed the detail pane switched to `TaskDetailView` with task header, timer actions, overview, forecast, analysis, and recent records.
  - Root cause: sidebar task clicks used plain `selectTask(taskID)`, whose default behavior revealed Today instead of navigating to Task Detail. Store navigation now separates selected task context from `desktopTaskDetailID`.

## Verification Log

- 2026-05-15 screenshot build: `xcodebuild build -quiet -scheme timetracker -destination 'id=93DD2475-B5AD-480B-A6BF-C4AE82F63D03' -derivedDataPath build/DerivedData-UIRefactor TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE=replaceOnLaunch`.
- 2026-05-15 macOS screenshot build: `xcodebuild build -quiet -scheme timetracker -destination 'platform=macOS' -derivedDataPath build/DerivedData-UIRefactor TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE=replaceOnLaunch`.
- 2026-05-15 plist check: Debug/screenshot app Info.plist resolved `TimeTrackerAutomaticDemoDataMode` to `replaceOnLaunch`; project Release build setting is `TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE = off;`.
- 2026-05-15 targeted demo/layout tests: `xcodebuild test -quiet -scheme timetracker -destination 'platform=macOS' -derivedDataPath build/DerivedData-UIRefactor -only-testing:timetrackerTests/Lifecycle/DemoDataLifecycleTests -only-testing:timetrackerTests/CoreSourceLayoutTests/sourceLayoutUsesSemanticStoreServiceFeatureAndSharedUIFolders -only-testing:timetrackerTests/TaskUIContractTests/uiRefactorPlanDocumentsInventoryAndResumableTDDLoop -only-testing:timetrackerTests/TaskUIContractTests/phoneTabsBindToSharedNavigationDestination`.
- 2026-05-15 UI contract slice: `xcodebuild test -quiet -scheme timetracker -destination 'platform=macOS' -derivedDataPath build/DerivedData-UIRefactor -only-testing:timetrackerTests/TaskUIContractTests/taskRowsOpenDetailInsteadOfEditingOnTap -only-testing:timetrackerTests/TaskUIContractTests/taskDetailIsReadFirstBeforeInlineEditing -only-testing:timetrackerTests/TaskUIContractTests/taskDetailUsesNativeCompactStatusControl -only-testing:timetrackerTests/TaskUIContractTests/taskRowsKeepStatusWithMetadataInsteadOfFloatingAtTrailingEdge -only-testing:timetrackerTests/TaskUIContractTests/analyticsMakesSelectedPeriodAndMetricMeaningsExplicit`.
- 2026-05-15 localization/contracts: `xcodebuild test -quiet -scheme timetracker -destination 'platform=macOS' -derivedDataPath build/DerivedData-UIRefactor -only-testing:timetrackerTests/TaskUIContractTests -only-testing:timetrackerTests/UIContracts/LocalizationContractTests`.
- 2026-05-15 UI/full-test cleanup:
  - Fixed `timetrackerUITests.testTaskEditorAndPomodoroFlowOpen()` by closing the editor with a hittable cancel button or Escape on macOS sheets.
  - Updated `BuildInstallScriptTests.buildInstallScriptBuildsAndInstallsWatchApp()` to match the script's current `devicectl` device discovery.
  - Targeted rerun passed: `xcodebuild test -quiet -scheme timetracker -destination 'platform=macOS' -derivedDataPath build/DerivedData-UIRefactor -only-testing:timetrackerUITests/timetrackerUITests/testTaskEditorAndPomodoroFlowOpen -only-testing:timetrackerTests/BuildInstallScriptTests/buildInstallScriptBuildsAndInstallsWatchApp`.
- 2026-05-15 Inbox row sizing: `xcodebuild test -quiet -scheme timetracker -destination 'platform=macOS' -derivedDataPath build/DerivedData-UIRefactor -only-testing:timetrackerTests/TimeTrackerUtilityTests -only-testing:timetrackerTests/InboxUIContractTests`.
- 2026-05-15 iteration 2 contract/build pass:
  - Targeted contracts passed after making Task Detail edit collapsed and adding the analytics screenshot readiness identifier: `xcodebuild test -quiet -scheme timetracker -destination 'platform=macOS' -derivedDataPath build/DerivedData-UIRefactor -only-testing:timetrackerTests/TaskUIContractTests -only-testing:timetrackerTests/UIContracts/LocalizationContractTests`.
  - Screenshot macOS build passed: `xcodebuild build -quiet -scheme timetracker -destination 'platform=macOS' -derivedDataPath build/DerivedData-UIRefactor TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE=replaceOnLaunch`.
  - Full serial test initially exposed two UI-test waits that were still matching the Analytics tab label instead of Analytics content. Fixed `analyticsIsReady(in:)` to query the full accessibility tree for `analytics.decisionSummary` and `analytics.periodControl`.
  - Targeted UI rerun passed: `xcodebuild test -quiet -scheme timetracker -destination 'platform=macOS' -derivedDataPath build/DerivedData-UIRefactor -only-testing:timetrackerUITests/timetrackerUITests/testPrimaryNavigationAndSettingsLoad -only-testing:timetrackerUITests/timetrackerUITests/testUIRefactorBaselineScreenshots`.
  - Final serial full test passed: `xcodebuild test -quiet -scheme timetracker -destination 'platform=macOS' -derivedDataPath build/DerivedData-UIRefactor -parallel-testing-enabled NO`.
  - Final iPhone screenshot build passed: `xcodebuild build -quiet -scheme timetracker -destination 'id=93DD2475-B5AD-480B-A6BF-C4AE82F63D03' -derivedDataPath build/DerivedData-UIRefactor TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE=replaceOnLaunch`.
- 2026-05-15 broader pass:
  - Parallel full test exposed one performance-budget flake under load: `CorePerformanceBudgetTests.denseOverlapAnalyticsSnapshotStaysWithinPerformanceBudget`.
  - The performance test passed individually: `xcodebuild test -quiet -scheme timetracker -destination 'platform=macOS' -derivedDataPath build/DerivedData-UIRefactor -only-testing:timetrackerTests/CorePerformanceBudgetTests/denseOverlapAnalyticsSnapshotStaysWithinPerformanceBudget`.
  - Final serial full test passed: `xcodebuild test -quiet -scheme timetracker -destination 'platform=macOS' -derivedDataPath build/DerivedData-UIRefactor -parallel-testing-enabled NO`.
- 2026-05-15 iPad sidebar task detail fix:
  - Targeted state/contract tests passed: `xcodebuild test -quiet -scheme timetracker -destination 'platform=macOS' -derivedDataPath build/DerivedData-UIRefactor -only-testing:timetrackerTests/CoreRefactorTests/desktopTaskDetailNavigationIsSeparateFromPlainTaskSelection -only-testing:timetrackerTests/CoreRefactorTests/deletingSelectedTaskPreservesCurrentDestination -only-testing:timetrackerTests/TaskUIContractTests/sidebarSelectionSyncDoesNotRevealProgrammaticTaskSelection`.
  - iPad build passed: `xcodebuild build -quiet -scheme timetracker -destination 'id=CE695D7E-AADB-4E49-A98C-61A800FD099C' -derivedDataPath build/DerivedData-UIRefactor TIMETRACKER_AUTOMATIC_DEMO_DATA_MODE=replaceOnLaunch`.
  - iPad XCTest runner launch failed once at SpringBoard/test-runner level before assertions ran; manual Simulator verification with Computer Use confirmed sidebar task click opens Task Detail and produced `ipad-sidebar-task-detail-fix.png`.
