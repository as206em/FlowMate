# Task manager: gaps and missing features

A product review of the current build, from reading the code. Items marked **(you)** come from your feedback.

## Must fix

| # | Gap | Proposed fix |
| --- | --- | --- |
| 1 | **(you)** Projects and milestones have no settings panel. Rename, color and delete are hidden in right-click menus, and clicking a milestone does nothing. | Clicking a project or milestone opens a side panel like the task panel.<br>**Project panel:** name, color, description, target date, sprint (number, start, length, goal), milestones, Archive, Delete.<br>**Milestone panel:** name, due date, description, Mark complete, its tasks with an "Add task" row, Delete. |
| 2 | **(you)** The main window has no search, filters, sort or group-by. | A filter bar on List and Board.<br>**Search:** ⌘F, matching titles, descriptions and subtasks.<br>**Filter chips:** Status, Priority, Milestone, Sprint, Due (Overdue / This week / No date), and Project when viewing All projects.<br>**Sort:** Manual, Priority, Due, Created, Updated.<br>**Group by:** Status, Milestone, Project, Priority, Sprint.<br>**Clear:** resets everything. Filters are remembered per project. |
| 3 | **(you)** The list has no column headers, and values sit at a different position on every row. | Fixed-width columns with a sticky header: Status · Title · Milestone · Sprint · Due · Priority · Expected/Time · Timer, plus Project in All projects. Click a header to sort. Empty cells show "–". |
| 4 | **(you)** It's unclear how to attach a task to a milestone or a sprint. You can only do it inside the task panel. | Clicking the Milestone cell or card chip opens a picker. The right-click menu gains Milestone and Move to project.<br>Group the list by milestone and drag rows between groups. Drag tasks onto a milestone.<br>The "New task" field gets milestone and sprint chips. |
| 5 | The List view has no drag and drop, though you asked for it in list and board. | Drag a row to another status (or milestone) group to change it, and drag within a group to reorder. |
| 6 | Changing a due date, expected time or priority means opening the big panel. | Click a cell to edit it in a small popover. Date presets: Today, Tomorrow, Next week, Clear. Double-click a title to rename. |
| 7 | A task can't be moved to another project. | Make Project a picker in the panel and in the right-click menu. |
| 8 | There is no sprint history. Completed sprints disappear, and their tasks just say "Closed sprint". | Keep each past sprint (number, dates, goal, tasks). Show a "Past sprints" section in Sprints, for example "Sprint 3 · Oct 12 – 25 · 8 of 10 done". |
| 9 | Sprint dates drift, and neither length nor dates can be edited. | Start the next sprint on the day you complete one. Let each project choose a length of 1–4 weeks, and make the dates editable. |
| 10 | Complete sprint gives no choice for unfinished tasks. | The dialog asks whether to move them to the next sprint, move them to the backlog, or keep them, and asks for the next goal. |
| 11 | **(you)** The task title underlines on hover. | Remove the underline. Use the row hover fill and a hand cursor instead. |
| 12 | **(you)** Task titles are too heavy. | Use regular weight in rows. Keep medium only for running tasks. |
| 13 | There is no undo. Deleting, dragging, status changes and Complete sprint are all permanent. | ⌘Z and ⇧⌘Z, plus an "Undo" toast after destructive actions. |
| 14 | Pressing Enter in the menu bar search creates a junk task. | Enter opens the highlighted result. Only "Add “x”" or ⌘↵ creates a task. |
| 15 | There are almost no keyboard shortcuts (only Esc). | **Creating and finding:** ⌘N new task, ⇧⌘N new project, ⌘F search, ⌘1–4 switch tabs.<br>**Selection:** ↑/↓ move, ↵ opens, Space toggles the timer.<br>**Editing:** ⌘⌫ deletes, ⌘D duplicates. |

## Should have

| # | Gap | Proposed fix |
| --- | --- | --- |
| 16 | No bulk actions. | ⌘-click or ⇧-click to select. A bar then sets status, priority, milestone, sprint or due date, moves to a project, or deletes. |
| 17 | No duplicate. | "Duplicate" (⌘D) copies a task with its subtasks reset. |
| 18 | Projects and tasks can't be archived. | "Archive project" moves it to an "Archived" sidebar section. Tasks from closed sprints are hidden from List unless a filter shows them. |
| 19 | Creating a task is title only, and in All projects it goes silently to the first project. | Show "Added to X · Open". ⇧↵ adds the task and opens it. Support tokens like `!high`, `@milestone`, `due:fri` and `~90m`. Remember the last project used. |
| 20 | Board silently hides backlog and next-sprint tasks. | A caption above the board: "Showing Sprint 4 · 12 more in Next and Backlog". |
| 21 | The task panel can't step to the next task. | ⌘[ and ⌘] move to the previous and next task. |
| 22 | The breadcrumbs (project › milestone › sprint) look clickable but aren't. | Each one opens its panel or picker. |
| 23 | Milestones have no progress or tasks view, and there's no "complete" state. | A progress bar, a "Show tasks" action and "Mark complete". You can also add a milestone from All projects. |
| 24 | Projects can't be reordered, and their milestones don't show in the sidebar. | Drag projects to reorder them. A disclosure arrow shows a project's milestones. |
| 25 | Time from a timer you forgot to stop can't be fixed. | Click the clock to edit the time spent, or use "Adjust time…" in the right-click menu. |
| 26 | A timer left running is easy to miss. | Optionally show the clock in the menu bar. After a long run, a quiet prompt asks "Still working on X?". |
| 27 | Expected time only offers presets, up to 8h. | Add a custom entry such as "1h 15m". |
| 28 | Due dates are slow to set. | Presets above the calendar, and typed dates like "fri" or "nov 18". |
| 29 | Overdue tasks are hard to reschedule. | An "Overdue (4)" filter chip. With bulk select, move them all at once. |
| 30 | Subtasks can't be reordered or turned into tasks. | Drag to reorder, "Convert to task", and click once to edit. |
| 31 | Save errors are invisible. A corrupt data file silently starts over from sample data. | A banner: "Couldn't save · Retry · Show file". |
| 32 | The first launch only offers sample data. | A banner with "Clear sample data", and a "Create your first project" empty state. |
| 33 | Empty states say "Nothing here". | Explain why the view is empty and offer an action. |
| 34 | In the menu bar, you can't choose which task a project's play button starts. | Expand any project to list its tasks, not only running ones. |
| 35 | The menu bar can't be used from the keyboard. | ↑/↓ move, Space toggles the timer, ↵ opens. |
| 36 | The menu bar quick-add target is surprising. | Remember the last project used, and show the target inside the field. |
| 37 | There's no global quick-add hotkey. | A configurable shortcut opens a small floating "New task" box. |
| 38 | Order and wording are inconsistent. Board shows To do → In progress → Done, but List shows In progress first. | Use one order and one naming pattern everywhere. |
| 39 | Clicking the status circle in a row jumps straight to Done. | A click cycles To do → In progress → Done. Right-click opens the full menu. |
| 40 | The window forgets the scope, tab and filters after relaunch. | Restore them per project. |
| 41 | Opening a project from the menu bar keeps whatever tab and filters were last used. | Open the project's own last tab and filters. |

## Nice to have

- **Organizing:** tags or labels; blocked-by and related tasks; recurring tasks; board swimlanes by project or milestone.
- **Planning:** a capacity hint while planning ("Planned: 18h"); project templates and Duplicate project.
- **Getting around:** task links and deep links; a ⌘K command palette.
- **Data:** images in descriptions; export and automatic backups; iCloud sync later.
- **Revisit later:** optional priority ("None") or an "Urgent" level; dark mode.

## Suggested build order

1. **Quick fixes to the list:** items 3, 7, 11, 12, 14, 38 and 39.
2. **Find and edit:** items 2, 4, 5, 6, 13 and 15.
3. **Projects, milestones and sprints:** items 1, 8, 9, 10, 18, 22, 23 and 24.
4. **Power use:** items 16, 17, 19, 21 and 25–30.
5. **Menu bar and polish:** items 31–37, 40 and 41.
