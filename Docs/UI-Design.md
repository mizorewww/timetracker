# UI Design Notes

The app should feel like a focused Apple productivity tool: clear hierarchy, native controls, restrained colors, and predictable alignment.

## Principles

- Prefer native `NavigationSplitView`, `List`, `Form`, sheets, popovers, menus, and toolbar items before custom controls.
- Do not add a custom primary-sidebar toggle to the iPad/macOS split view. Let `NavigationSplitView` provide the system sidebar affordance; custom `sidebar.left` buttons can duplicate the system control and disappear after collapsing.
- Cards are for repeated content or framed data, not for every section.
- Today should answer three questions quickly: what is running, what happened today, and what can continue next.
- Forecast UI should explain where numbers come from. Forecast cards need an `info.circle` entry point, a short source label, and a plain-language reason. Do not show a forecast when checklist progress or tracked time is missing.
- Checklist UI belongs inside task editing and task detail surfaces. Do not present checklist items as timed subtasks; they are progress markers under a timed task.
- Checklist rows should behave like native to-do rows: a large circular check button, at least 44 pt row height, unfinished items first, completed items after them with strikethrough text. Adding a checklist item should create a focused empty row immediately.
- iPhone layouts must split dense rows into two lines when icon, title, path, timer, and actions cannot fit.
- iPad and macOS may use a detail inspector, but the inspector should stay narrow and collapse when it is not useful.
- Sheets should use system `NavigationStack` + `Form` + toolbar cancel/save actions. Avoid custom modal title bars unless the content is not an editor.
- Fixed sheet sizes are macOS-only. iPhone and iPad sheets must follow the platform presentation width so they do not overflow compact devices.
- The analytics timeline should separate graphic bars from task text. Bars show time, color, and icon; rows below carry labels.
- When a section shows every item, do not show inert "All" links. A disclosure or navigation affordance should only appear when it performs an action.
- Horizontal iPad/macOS Today action buttons should align to the metric panel height. If a metric card and action stack sit in the same row, their top and bottom edges should match.

## Terminology

Use product language, not internal implementation language.

Preferred terms:

- "Actual Time" or localized equivalent for wall-clock time when space allows.
- "Total Task Time" or localized equivalent for gross time when space allows.
- "Time Segment" should appear only in advanced edit/debug contexts.
- "Optimize Database" belongs in settings and must explain that it permanently deletes orphaned records.

## Responsive Checks

Before merging UI work, verify:

- iPhone portrait Today, Tasks, Pomodoro, Analytics, Settings.
- iPad landscape Today with sidebar and optional inspector.
- macOS narrow minimum window and full-screen window.
- Long task names, localized strings, and dynamic timer text do not overlap.

## Timeline Rules

The Today analytics timeline clips cross-day segments to today's bounds, then displays the visible range from the first visible segment start to the last visible segment end. Empty days fall back to the full day. This keeps dense work periods readable while still respecting midnight boundaries.

Bars should show only time position, duration, color, and the task symbol. Task title, parent path, and exact time range belong in rows below the chart. On iPhone, the timeline is vertical; on iPad and macOS, it is horizontal.

Adjacent tasks with no visible gap should use different lanes so their bars remain distinguishable. The layout should still minimize lane count: if task A overlaps B and B overlaps C, but A does not overlap C, A and C can reuse the same lane.

## Task Lists

The task management screen must render each visible task as its own `List` row. Do not place an entire subtree inside one row, because iPhone context menus and swipe actions would attach to the parent subtree instead of the child task the user touched.

Children are shown by flattening the expanded task tree into visible rows with indentation. This preserves infinite nesting while keeping native row behavior: tap to edit on iPhone, swipe to start/edit/delete, and context menu on each individual task.
