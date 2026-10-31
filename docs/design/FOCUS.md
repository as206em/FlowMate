# Focus design system

Focus is FlowMate's design system. It replaces Stamp. It's light only.

- Tokens: [focus-tokens.json](focus-tokens.json), the source of truth.
- SwiftUI: [Sources/UI/Focus/Focus.swift](../../Sources/UI/Focus/Focus.swift) holds the tokens and the shared components.
- Reference screens: [reference/](reference/) holds the approved HTML designs: `FocusApp` (main window), `FocusMenu` (menu bar dropdown) and `FocusSystem` (token sheet). Read them for layout, spacing and behavior.

## Principles

1. **Calm by default.** Hierarchy comes from three text tones and weight, not from color.
2. **Hairlines, not boxes.** Rows sit together in one panel with a hairline between each one. Rows don't get their own cards. Cards are only for the board.
3. **Color is a signal.** Orange (`live`) means a timer is running, and nothing else uses it except the one primary button. Purple means done, amber means in progress, red means risk.
4. **The timer ring is the signature.** Every play button is also a progress ring that fills toward the task's expected time. It turns red past the estimate. A running ring glows.
5. **Timers never stop each other.** Any number of tasks can run at once. The sidebar and the menu bar list every running timer.

## Color

| Token | Value | Use |
| --- | --- | --- |
| `canvas` | #FBFBFA | Window background |
| `sidebar` | #F3F3F1 | Sidebar, inspector, sunk areas |
| `raised` | #FFFFFF | Panels, cards, fields, menus |
| `hover` | #EEEEEB | Hover |
| `selected` | #E8E8E4 | Keyboard-selected row (with a 2px `text2` bar on the left) |
| `text` | #18181B | Titles and values |
| `text2` | #4F4F58 | Body |
| `text3` | #6E6E78 | Meta, labels |
| `hairline` | black 8% | Separators, panel borders |
| `lineStrong` | black 14% | Buttons, menus, focused fields |
| `live` | #F0532F | Running timer, primary button |
| `liveText` | #C93C1B | Live clock text |
| `done` | #6D5AE6 | Done |
| `progress` | #B76E00 | In progress, medium priority |
| `risk` | #DC2626 | Overdue, over estimate, high priority |
| `ringTrack` | #E4E4E0 | Empty part of a ring |

**Project color.** A project is shown as a tile: its color at 18% behind the project's first letter in the full color. The palette is in the tokens file. Project color appears nowhere else.

## Type

The app uses the system font (SF Pro). The web reference uses Inter.

| Style | Size / weight | Use |
| --- | --- | --- |
| Task title | 26 / semibold | Task panel title |
| Page title | 20 / semibold | Main window header |
| Header | 15 / semibold | Section headers |
| Row | 13.5 / regular | Task titles in rows and cards |
| Row strong | 13.5 / medium | Running task titles, project names in the menu |
| Group title | 13.5 / semibold | List group and board column headings ("To do 4") |
| Body | 13.5 / regular | Descriptions |
| Control | 13 / medium | Buttons, fields, dropdowns |
| Meta | 12.5 / regular, text3 | Dates, counts, hints |
| Caption | 11 / semibold, uppercase, +0.5 tracking | Group labels |
| Clock | Tabular numerals | Timers |

## Components

| Component | Spec |
| --- | --- |
| Button | 30 tall, radius 7, 1px `lineStrong`, raised fill. Labels never truncate. **Compact:** 8 side padding for rows of short buttons in popovers. **Primary:** `live` fill and `onLive` text. **Ghost:** no border. |
| Field and dropdown | 30 tall, radius 7, 1px `hairline` (`lineStrong` on hover or focus), control type. |
| Status dropdown | Field size, tinted with the status colors, with the status icon and a chevron. The menu shows the icons and a check next to the current value. |
| Priority dropdown | Same pattern with priority bars. |
| Segmented tabs | A sidebar-colored track with 2px padding. The selected tab is a raised fill with the `selected` shadow. |
| Row | 46 tall, 14px leading padding, hairline on top except the first row. Hover is `hover`. A task title is never underlined: the hover fill and a pointing-hand cursor show it opens. The keyboard selection is `selected` with a 2px `text2` bar on the left; a selected board card gets a 1.5px `text3` border. |
| Editable cell | A list cell that opens a small popover editor on click (milestone, sprint, due, priority, time). No chrome at rest; on hover a raised fill and a `lineStrong` box, radius 6. Double-clicking a title renames it in place. The time cell's popover edits the time spent (a field such as "1h 12m" with Set and Reset, then −15m / −5m / +5m / +15m) above the expected presets and a custom entry. |
| Date popover | A "Type a date" field on top (fri, nov 18, 3d, in 2 weeks, 11/18; what it reads shows on the right, `risk` "?" when it can't tell; ↵ applies), then Today, Tomorrow, Next week and Clear, then the calendar. |
| Search field | Field size with a magnifier, a clear × and a key hint (`⌘F`) while empty. Esc clears the text, then leaves the field; ↵ jumps to the first result. |
| Filter chip | 30 tall, radius 7. **Inactive:** hairline, `text2`, a small chevron. **Active:** raised, `lineStrong`, the label in `text2` and the value in `text`, with an × that removes it. Also used for the Group and Sort buttons. |
| Toast | Bottom center, 40 tall, raised fill, `lineStrong`, radius 10, `menu` shadow. One short message ("Task deleted", "Added to Atlas · High"), up to two actions ("Open", "Undo ⌘Z") and a close ×. Goes away after 6 seconds or when a newer action replaces the one it would undo. It draws above the side panel, so actions taken inside a panel (duplicate, remove or convert a subtask) show theirs. |
| Action bar | Bottom center, 44 tall, raised fill, `lineStrong`, radius 10, `menu` shadow, like the toast. Shows while two or more tasks are selected: "3 selected", then bar buttons (Status, Priority, Milestone, Sprint (only when a selected task's project uses sprints), Due, Labels, Move to) that open Focus menus above the bar, Today (sun), Delete in `risk`, and `esc` ×. A toast stacks just above it. It never runs past the content: when the full bar doesn't fit (the 980 minimum window), the count drops "selected", Today and Delete become 30 icon buttons, "Move to" reads "Move" and `esc` goes; narrower still, Milestone, Sprint, Due, Labels and Move to fold into a "More" menu whose items (with their single-key hints) open in the same popover. |
| Bar button | 30 tall ghost button in control type, radius 7, `hover` fill, with an optional icon and a small chevron when it opens a menu. Hairline separators group them. |
| Long-run prompt | "Still working on X? Running for 3h 10m without a break." with Keep (ghost) and Stop at… (standard). In the window it's a raised banner with `lineStrong` and a live dot under the filter bar; in the menu it's a compact line under the running timer. It never stops a timer by itself and makes no sound. |
| Sleep prompt | "Timers ran while your Mac slept 2h 05m" as an info banner (moon icon) with Keep (ghost) and Discard sleep time (standard); in the menu a compact line under the In progress caption. Shown when timers ran through more than 5 minutes of sleep or screen lock. |
| Banner | A full-width card under the filter bar, min 50 tall, radius 10, 14 side padding: an icon, a 13 semibold title with one line of `text2` explanation, a ghost and a standard button, and an optional ×. **Info** (sample data) is raised with `lineStrong`; **risk** (a save or load problem) uses the risk tint. |
| Empty state | Says why a view is empty and offers the next step: a 15 semibold title with a `text3` icon, one or two lines of `text2` body, then a standard button and an optional ghost one, left aligned with 20 padding inside the view's panel. Never just "Nothing here". |
| Quick-add box | A floating 520 wide panel (raised, `lineStrong`, radius 12, menu shadow) opened by the global quick-add shortcut over any app: "New task" with the project chip, a 52 tall 17pt field, and a `sidebar` footer with the preview ("Atlas · High · Due Fri") or "✓ Added to Atlas", plus the ↵ / ⇧↵ / esc keys. |
| Column header | Sticky over a table of rows, 30 tall, caption type in `text3` (`text` when hovered or sorted), with a small chevron for the sort direction. Header and rows share one set of column widths. |
| Panel | Raised fill, 1px hairline, radius 12. |
| Board card | Raised fill, hairline, radius 10, 12px padding. Drag to change status. |
| Tag | 22 tall, radius 6, hairline, 12 / medium, `text2`. A due tag turns `risk` when overdue or due today. |
| Status icon | Drawn by the status's kind, in the status's color (from `statusPalette`: `text3` gray, `progress`, `done`, then the project palette and `risk`). **Not started:** an open circle. **Started:** a circle half filled. **Done:** a filled circle with a white check. **Canceled:** a filled circle at 75% with a white ×. In a row, a click moves to the next status of the project's workflow (wrapping around), and a right-click lists them all. |
| Priority bars | Three bars 3px wide and 5, 8 and 12px tall in the priority color. Unused bars are at 25% opacity. |
| Timer ring | 32 in rows, 28 on cards and in the menu, 150 in the task panel. A 2.5 stroke (8 on the large ring) over `ringTrack`, filled by spent ÷ expected. **Idle:** the fill is `text2` and the icon is a play glyph. **Running:** the fill is `live` and the icon is a pause glyph, with a glow. **Over estimate:** a `risk` ring. On hover, the large ring shows a big pause or play overlay, and clicking it toggles the timer. |
| Live dot | A 6px `live` circle that pulses, next to projects with a running timer. |
| Side panel | Opens a task, a project or a milestone over the current view, one at a time. It's 860 wide, slides in from the right, and dims the content behind it with `scrim`. It closes with ×, Esc or a click on the scrim. A 54 header holds the breadcrumbs, then the content on the left and a 320 inspector (sidebar fill, hairline on the left) on the right. |
| Breadcrumb | Body type in `text2` (`text3` for an empty value such as "No milestone"), with a hover fill, `text` and a hand cursor; separated by "›" in `text3`. Each one opens its panel or a picker. The current item is `text` medium and not clickable. |
| Progress bar | 4 tall (6 in the milestone inspector), a `ringTrack` capsule filled with `done`. Used for milestones. |
| Color swatches | The project palette as 18 circles, 7 apart; the chosen one has a 1.5 `text` ring. |
| Stepper | Field size with − and + buttons around a tabular number (sprint number). |
| Choice row | A 16 radio circle (`lineStrong`, or `text` with a filled dot when chosen), a body title and a meta hint, with a hover fill. Used in dialogs such as Complete sprint. |
| Label chip | 20 tall, radius 6, a 10% fill of the label's color with a 6px dot and the name in 12 medium in the darkened tint (`Focus.colorTint`). Rows and cards show as many as fit, then "+2" in `text3`. Labels are workspace-wide, sorted by name wherever they're listed. |
| Labels picker | A 260 wide Focus menu: a 38 tall search field with a tag icon, then a row per label (8px color dot, name, a check when every chosen task has it, a − when only some do) and "Create label “x”" for a new name; ↵ toggles, esc closes. The same rows serve the L key, the panel's Labels field, the bulk bar and the right-click menu. |
| Labels manager | A 480 sheet: page title "Labels" with a line on where labels come from, then a row per label: a 12 color dot that opens the color menu, the name edited in place, its task count ("Unused" when none), an arrow that shows its tasks in All projects and a trash icon button. Deleting takes the label off every task and out of saved views (one undo step with a toast). Done closes it. |
| Single-key picker | S, P, M, R, D, E, T, L and ⇧M open a 280 wide Focus menu hanging from the row, card, panel (for the open task) or the bulk bar: a caption with the action and what it edits ("STATUS · 3 TASKS"), a 38 tall filter field, 30 tall rows (icon, title, meta detail, a check on the current value, − when mixed), and a 26 tall key footer. Typing filters; typed values are read too ("fri", "90m", a new milestone name). A row in the milestone side panel is an anchor as well; when a task is on screen twice the one shown last wins. |
| Command palette | ⌘K: a 600 wide raised panel (radius 12, `lineStrong`, two soft shadows) near the top over a `scrim`. A 54 tall 17pt field, then 36 tall result rows (20 icon column, title in row type, a 12 `text3` subtitle, the kind on the right) with `selected` for the highlight and `hover` under the pointer, grouped under captions (Today, Projects, Milestones, Tasks, Commands), and a 32 tall footer of key hints. ">" lists commands only. |
| Saved view row | A sidebar item under the "Views" caption: an SF Symbol (12.5 medium, 18 wide), the name, a 6px `progress` dot while the open view is modified, and the live count in `text3`. Drag to reorder (a 2px `text3` line). With no views yet, ghost suggestion rows (28 tall, `text3`) offer starters. The view's header shows its icon and name with "Modified · Update · Revert" while changed. |
| Save view sheet | A 460 sheet: page title, a meta line saying where it looks ("Atlas › Beta"), the name field, a grid of 28 icon buttons (radius 7, `selected` when chosen) and Cancel / Save view. |
| Overview card | Cards of at least 300 wide in a grid, 16 apart: raised fill, hairline (`lineStrong` on hover), radius 10, 14 side padding. The tile and name with the live dot and a play ring for the next task; the sprint line ("Sprint 4 · day 6 of 14") with a progress bar and "5 of 9 done"; stat cells in 15 semibold tabular numbers over meta labels (open, in progress, tracked this week, and overdue as a `risk` button that opens the List filtered to it); the next milestone (◆, name, due tag, health tag); and the last activity in meta ("Untouched for 9 days" in `progress` when stale). Sorted by attention, Name or Recent activity. |
| Roadmap timeline | A panel with a sticky 200 wide lane column (raised; tile, name and "3 open" per 56 tall lane) and a horizontally scrolling canvas: a 44 tall axis (month names in caption type, which stay pinned at the left edge while their month is in view, and week numbers in meta `text3`, with the "Today" capsule in `text2`), faint week lines, weekends at 60% `sidebar`, each lane's current sprint as a 5% band of the project color between dashed lines, the project's target date as a 1.5 line with a small flag in its color, and the Today line. Milestones are 18 diamonds in their color, filled from the bottom by progress, `risk` outline when overdue or at risk, with the name in meta type stopping before the next diamond or the target flag. Hover for a tooltip card; drag sideways to move the date (a 22 tall date chip follows, whole days, one undo step). Undated milestones wait in a "No date" tray of chips under the panel; drag one onto the canvas to give it the day under the pointer (a line and a date capsule on the axis show where it lands). Month and Quarter zoom, and Today scrolls back. |
| Velocity chart | A panel (raised, hairline, radius 12, 16 / 14 padding) under "Past sprints": "Velocity" in group type with "~6h done per sprint, last 3" in meta, a legend, then a 120 tall chart with a bar per recent sprint (the last six) for the hours done, a dash for what was planned and, with a capacity, a dashed line for it; hover a sprint for its numbers; a meta caption below. Group headers of the plan read "7 tasks · 11h of 20h · 5h left", `progress` near the capacity and `risk` over it. |
| Menu (popover) | Raised fill, `lineStrong` border, radius 10, `menu` shadow, 4px padding, 7-radius items. Multi-select menus (filters) stay open and show a check per chosen item; caption headers separate groups. |

## Layout

- **Main window:** a 240 sidebar, then the content.
  - **Sidebar:** All projects, the projects with their open count and live dot, an inline "New project" field, an "Archived" section (collapsed, only when something is archived), and the running timers with Pause all. Drag a project to reorder (a 2px `text3` line shows where it lands). Drop a task on a project to move it there, or on a milestone row to attach it (a dashed `text3` outline or the raised fill shows the target; one undo step with a toast). A small arrow at the right of a project lists its milestones underneath (◆ in the milestone's color, name and done/total; a click shows the milestone's page with the row in the raised fill, a second click opens its panel), ending in an "Add milestone" field (↵ adds with an Open toast, ⇧↵ adds and opens the page). ⌥⌘↑ / ⌥⌘↓ step through the sidebar items. A click shows the project; a second click on the project already shown opens its panel. Right-click a project for Project settings, Rename, Color, Archive and Delete.
  - **Header:** the title, the tabs (Board · List · Sprints · Milestones) and an inline "New task" field. The field has a milestone chip (◇ / ◆ name) and a sprint chip (Sprint · Next · Backlog) for the next task, and shows `⌘N` while idle.
  - **Filter bar** (List and Board), 48 tall under the header: Search (`⌘F`; title, description and subtasks), the active filter chips, a "Filter" button whose menu lists every dimension (Status, Priority, Milestone, Sprint, Due: Overdue / This week / No date, and Project in All projects; Sprint isn't offered on Board), then Group (List only: Status, Milestone, Project, Priority, Sprint), Sort (Manual, Priority, Due, Created, Updated, with the direction) and Clear. Each project keeps its own settings. In a narrow window, Filter, Group and Sort drop their labels for icons, and chips that don't fit scroll under a fade. Dragging a row onto another group sets that value (a milestone of another project moves the task too); dragging within a group reorders it in manual order. The grouped-by column is hidden from the table.
  - **Header title:** in a project, the tile and name open the project panel. An archived project shows an "Archived" tag and Unarchive.
  - **Board caption:** Board shows only the active sprint, so a `meta` `text3` line above the columns says so: "Showing Sprint 4 · 12 more in Next and Backlog" (All projects: "Showing each project's active sprint"), with a Plan in Sprints link in a project. The count follows the filter chips. When the sprint is empty, the empty state says it instead.
  - **Sprint header** (Board and Sprints): the sprint name, its dates (click to set the start and the length, 1–4 weeks) and goal, and Complete sprint.
  - **Complete sprint dialog** (a 460 sheet): what closes and what moves in, then a choice for unfinished tasks (move to the next sprint, move to the backlog, or keep them in the closing sprint), the next sprint's goal, and Cancel / Complete sprint. The next sprint starts the day you complete one. One undo step.
  - **Sprints:** the active sprint, the next one and the backlog (each header with its load against the capacity), then "Past sprints" with the velocity chart and each sprint newest first and collapsed: "Sprint 3  10  8 done · 18h planned · 21h tracked · Oct 12 – Oct 25 · goal" (the header's own count is the task total, so the hint doesn't repeat it), each with its tasks. A project can turn sprints off (Project settings): its tabs drop Sprints, every open task is current work, and sprint pickers, chips, the R key and #sprint words leave it alone.
  - **Today:** the sidebar's first item (badge: overdue, due today and pinned, in `risk` when anything is overdue). One page without tabs: Running, Overdue (with "Move all to today · Tomorrow"), Due today, My focus (tasks pinned with ⌘T or the sun, drag to reorder, "From yesterday" on carried-over ones, "Planned 5h 30m" left), Done today, and the time tracked today per project. Rows are the List table with a Project column.
  - **Overview** (All projects' first tab): the Overview cards, sorted by attention by default.
  - **Labels and views:** List can group by Label (a task shows under each of its labels; dragging between label groups moves the label: the source group's comes off, the target's goes on; "No label" takes them all off). The filter bar's Label chip matches any of the chosen labels, and "Save view" keeps the scope, layout, filters, grouping and sort as a sidebar view; a filter by status is stored by status id, so a view across projects matches each project's status of that id, and a status deleted everywhere drops out of the view.
  - **Milestone page:** the header shows project › ◆ name (the project crumb shows the project, the name opens the panel) and only Board and List. A 48 line under it holds the due date (click for the date editor), a progress bar with "6 of 11 done", "4h 10m tracked of 12h expected" (`progress` once over), then Mark complete (Reopen) and an ⓘ icon button for the panel. Board columns are the project's statuses and show every sprint and the backlog; the List hides the Milestone column, the filter bar drops Milestone, and Group drops Milestone and Project.
  - **Milestone colors:** each milestone has a palette color. Chips (rows, cards) are tinted with it: a 10% fill, the darkened color for text and a filled ◆. A card without a milestone shows no chip until hovered. `justAdded` (amber at 16%) washes a task just added from ⌘N's composer for a moment.
  - **Milestones:** one panel of rows (in All projects, one panel per project under its tile and name), open ones by due date then completed ones: ◆ name, a progress bar with done/total, and the due tag (`risk` when overdue) or "✓ Completed". A click shows the milestone's page; right-click for Show tasks, Details, Mark complete, Due date, Color and Delete. The last row adds a milestone, with a project chip in All projects.
  - **List:** a table with fixed-width columns under a sticky header: Status · Title · Milestone · Sprint · Due · Priority · Expected · Timer, plus Project (after Status) in All projects. Click a header to sort; click again to flip, a third time to return to the manual order. Empty cells show "–". When the window is narrow, Sprint, Milestone, Project and Priority drop out in that order so the title keeps 200pt. Sprints uses the same table without the Sprint column, in manual order.
  - **Undo:** every edit can be undone with ⌘Z and redone with ⇧⌘Z; typing is one step. Timer starts and pauses aren't steps, and undo never removes tracked time. Deleting a task, a milestone or a project and Complete sprint show an "Undo" toast. Deleting a task needs no confirmation.
  - **New task field:** in All projects it adds to the last project used (remembered across launches); the tile changes it. ↵ adds and shows "Added to Atlas · Open"; ⇧↵ adds and opens the task. Tokens set fields as you type: `!high` / `!med` / `!low`, `@milestone` (or `@"two words"`), `due:fri` / `due:nov18`, `~90m` / `~1h30m`. While typing, a small line under the field shows what will happen ("Atlas · High · ◆ Beta · Due Fri"). Unknown tokens stay in the title.
  - **Selection:** ⌘-click adds or removes a task, ⇧-click selects a range, ⇧↑/⇧↓ grows it, ⌘A selects every task shown. Selected rows use `selected` with the 2px bar. With two or more, the action bar appears; ⌘⌫ and ⌘D act on all of them, and every bulk change is one undo step with a toast ("3 tasks moved to Done · Undo").
  - **Overdue:** when tasks are overdue and no Due filter is set, an "Overdue 4" chip (count in `risk`, `riskTint` border) sits in the filter bar. With the filter on, "Reschedule 4…" opens the date popover and moves them all at once.
  - **Fixing time:** the list's time cell, "Adjust time" under the large ring, and "Adjust time…" in the right-click menu set the time spent. A running timer keeps running from the new total. Undo takes an adjustment back out.
  - **Still working?:** after a timer runs longer than the chosen time (Settings › General › Timers; 3h by default, or never) without a break, the long-run prompt asks quietly. Keep asks again one interval later (the answer is saved with the data, so a relaunch doesn't ask early); Stop at… offers Now, 15 / 30 minutes or 1 hour ago, when the expected time ran out, or any time since the start. Settings can also show the running clock next to the menu bar icon ("1:12:05 +1").
  - **Keyboard:** ⌘N new task, ⇧⌘N new project, ⌘F search, ⌘K palette, ⌘1–4 tabs, ↑/↓ select, ↵ open, Space timer, X done or back, the single-key pickers (S, P, M, R, D, E, T, L, ⇧M; 1–3 set the priority), ⌘T Today, ⌘⌫ delete, ⌘D duplicate, Esc clears the selection, ⌘A selects all, ⌘[ / ⌘] step to the previous or next task in the panel, ⌘0 and ⌥⌘↑ / ⌥⌘↓ move a keyboard cursor through the sidebar (a 1.5 `text3` ring; the sidebar scrolls to keep it in view), ⌘/ (or the ? in the sidebar) lists them. Shortcuts that edit tasks wait while a text field has focus.
  - **Status order:** each project's workflow order (board columns, list groups, menus, pickers). All projects uses the kinds instead: Not started → Started → Done → Canceled (Canceled only when used). Priority is always High → Medium → Low.
- **Task side panel:** breadcrumbs (project › milestone › sprint: the project and milestone open their panels, an empty milestone and the sprint open a picker), then "3 of 12" with up and down arrows (⌘[ / ⌘]) to step through the tasks of the view behind. The content is on the left (title, Markdown description with Write and Preview, subtasks, then Time: the total and "Add time…" over a panel of sessions grouped by day under caption headers with day totals, the running session first on a `liveSoft` row with the live dot; hover a session for Edit (start, end and note in place on a `sidebar` row) and Delete; manual and imported sessions carry a tag) and a 320 inspector on the right (large timer ring with "Adjust time", Status, Priority, Milestone, Sprint, Due date, Expected with presets and a custom entry, Project, then Created / Updated / Completed in meta type, then Duplicate and Delete task).
- **Subtasks:** click a title to edit it (↵ saves, Esc cancels). On hover a row shows a drag handle on the left (drag to reorder; a 2px `text3` line shows where it lands) and Convert to task on the right; right-click has Edit, Convert to task and Remove. A converted subtask becomes a task just below its parent, with the same project, milestone and sprint.
- **Project side panel:** the name, a Markdown description, the milestones (with progress; "Add a milestone" row) and the Workflow on the left. Workflow is a panel of status rows (drag handle on hover, the status icon that opens the color swatches, the name edited in place, a kind dropdown, the task count, ⋯ with Move up / Move down / Delete), an "Add a status" row, and "Apply preset" (Simple, Dev, Kanban) in the section header. Deleting a status in use opens a popover asking which status its tasks move to. The inspector has the open-task count, Color, Target date, the Sprint (number, start, length, goal, where the next one falls, Complete sprint…, past count), then Show tasks, Archive (Unarchive) and Delete project….
- **Milestone side panel:** breadcrumbs (project › milestone), the name, a Markdown description and its tasks (status, title, sprint, due, timer; an "Add task" row) on the left. The inspector has the progress ("3 of 7 tasks done" and a bar), Project, Due date, Color swatches, Mark complete (Reopen), Show tasks (the milestone page) and Delete milestone….
- **Archive:** an archived project leaves the sidebar list, every picker, All projects and the menu bar, and its timers pause. Its data stays; it opens from the Archived section.
- **Past sprints in List:** tasks of closed sprints are hidden, with a caption saying how many; the Sprint › Past sprints filter shows them.
- **Menu bar dropdown:** 360 wide. A global hotkey (Settings › General) opens it with the search field focused, as a click on FlowMate's menu bar icon would. Contents:
  - A search and quick-add field with the target project as a chip inside it (the last project used, remembered across launches; click to change). While typing, ↑/↓ move the highlight, ↵ opens the highlighted project or task, and only the "Add “x”" row or ⌘↵ creates a task. Adding understands the New task tokens and shows "✓ Added to Atlas · High · Open" under the field for a few seconds.
  - With the field empty the menu works from the keyboard: ↑/↓ move a highlight through the running timers, projects and listed tasks (hover fill; a `liveText` outline on a running row), Space starts or pauses the highlighted timer (a project's ring for a project), ↵ opens it in FlowMate, → / ← show or hide a project's tasks and Esc clears the highlight. The field shows the key hint ("␣ timer").
  - A failed save shows a notice with Retry at the top.
  - Running timers, each with the quiet "Still working on this? Keep · Stop at…" line once it has run past the prompt time, and the sleep prompt when one waits (it's kept with the data, so it's still there after quitting).
  - Up next when nothing runs: overdue, due today and pinned tasks, then the top not started tasks of each project's current work, each with a play ring.
  - Projects, each with a disclosure chevron and a ring play button. Any project expands to list its open sprint tasks (or, when the sprint is empty, its Next and Backlog tasks under a caption), each with its own play ring, so you choose which task starts. A running project starts expanded. With no projects: "Create a project".
  - Proofreading tools.
  - A footer with Open FlowMate, Settings and Quit.
- **Quick add from anywhere:** Settings › General › Quick add sets a global shortcut (⌃⌥N by default, can be turned off; it can never be the proofreading shortcut). It opens the quick-add box without bringing FlowMate forward: ↵ adds and closes a moment later, ⇧↵ adds and opens the task, Esc or a click elsewhere closes.
- **Notices:** under the filter bar. "Couldn't save your tasks" (risk) with Retry and Show file stays until a save works. If the data file can't be read FlowMate never falls back to sample data: it loads the last good copy or starts empty, keeps the damaged file next to it, and says so with Show file. On first launch the sample project carries an info banner with Clear sample data (undoable) and Keep it.
- **Empty states:** no projects shows "Create your first project" with a name field in place of the view. An empty List or Board says whether there are no tasks yet (New task), the filters hide them all (Clear filters), or the sprint is empty ("Nothing in Sprint 4 yet · 3 tasks wait in Next and Backlog", Plan in Sprints). Empty groups say what belongs there and how to get it there.
- **Restoring the window:** the scope, the tab of each scope and the filters, sort and grouping of each scope, the collapsed groups and the sidebar projects showing their milestones come back after relaunch (kept as UI state, not in the data file; the search text and an open panel aren't kept). Opening a project, from the sidebar or the menu bar, shows its own last tab and filters.

## Writing

- Sentence case everywhere.
- Short labels: "New task", "Complete sprint", "Pause all".
- Show time as `1:38:08` for a clock and as `2h 30m`, `45m` or `2h` for an estimate.
