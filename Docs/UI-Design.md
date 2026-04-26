# UI Design Notes

The app should feel like a focused Apple productivity tool: clear hierarchy, native controls, restrained colors, and predictable alignment.

## Principles

- Prefer native `NavigationSplitView`, `List`, `Form`, sheets, popovers, menus, and toolbar items before custom controls.
- Cards are for repeated content or framed data, not for every section.
- Today should answer three questions quickly: what is running, what happened today, and what can continue next.
- iPhone layouts must split dense rows into two lines when icon, title, path, timer, and actions cannot fit.
- iPad and macOS may use a detail inspector, but the inspector should stay narrow and collapse when it is not useful.
- The analytics timeline should separate graphic bars from task text. Bars show time, color, and icon; rows below carry labels.

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
