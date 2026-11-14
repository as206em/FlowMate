# FlowMate

A very opinionated flow partner for macOS. It does the two things I use all day, task management and proofreading, and stays out of the way while I work.

FlowMate lives in the menu bar. It manages tasks for one person running many projects, with timers that run side by side. It also proofreads selected text in any app with one shortcut, using a local Ollama model or OpenAI.

**The opinions it's built on**

- **Menu bar first.** Start a timer, add a task or proofread without opening a window.
- **Keyboard first.** Single keys edit a task, ⌘K jumps anywhere, and one quick-add language works in every New task box.
- **Many projects, one person.** Today gathers what matters across every project, and starting a timer never stops another.
- **Your data stays on your Mac.** Tasks and settings are plain JSON files, API keys live in the Keychain, and proofreading can run fully offline with Ollama. Cloud sync (Settings › Cloud sync, off by default) keeps a copy on your own FlowMate server.
- **Review, then replace.** Proofreading shows the changes before it touches your text, unless you turn that off.
- **One look.** Light only, nothing to theme.

Requires macOS 13 (Ventura) or later.

## Features

- **Proofread anywhere**: select text in any app and press the shortcut (default `⌘.`).
- **Review before replacing**: a results dialog shows the changes. You can edit the result, then **Replace** it in the original app (`⌘↩`), **Copy** it, or **Retry**.
- **Instant replace**: turn off "Show Results Before Replacing" to swap the selected text right away.
- **Proofread Clipboard**: proofread whatever is on the clipboard from the menu bar.
- **Menu bar status**: see the active provider and model, whether the connection works, and whether Accessibility access is missing. Switch provider or model from the menu.
- **Recent results**: re-open recent results from the menu. They're kept in memory only and cleared when FlowMate quits.
- **Ollama and OpenAI**: run fully on your Mac with Ollama, or use OpenAI.
- **Custom instructions**: edit the proofreading instructions, with a reset to the default.
- **Launch at login** in Settings → General. FlowMate is light only.
- **API keys in the Keychain**: never written to the config file.
- **Clean results**: reasoning blocks (`<think>…</think>`), "Here's the corrected text:" lines, and quotes or code fences the model wraps around the answer are removed.

## Agent access (temporary MCP)

Until there is a backend, FlowMate runs a small local MCP server so an agent (Claude Code, Claude Desktop) can work with your tasks. It reads Today (the Start next pick and why), the project verdicts and the sprint (with what Fill sprint would add); creates, edits, completes, deletes and moves tasks, one or many at a time (project, priority, sprint, status, due date, labels, type, notes, subtasks, Today, impact); starts and pauses timers; logs time; fills and completes the sprint; nudges Next best; edits projects, labels and types; takes quick-add lines; and undoes. It listens on `127.0.0.1` only (port 47821, or 47822 for the dev build; `FLOWMATE_MCP_PORT` changes it, `FLOWMATE_MCP=0` turns it off), calls the same code as the UI so changes appear live and undo with ⌘Z. Connect Claude Code with:

```bash
claude mcp add --transport http flowmate http://127.0.0.1:47821/mcp
```

The code is in `Sources/MCP/`; when the backend exists, swap the tool bodies in `MCPTaskTools.swift` for backend calls.

## Tasks

Open the main window with **Open FlowMate** in the menu bar dropdown (`⌘O`).

- **Today**: the first item in the sidebar (its badge counts what's overdue, due today or pinned) answers "what now" in three blocks. **This week** is Make against Reach of the time tracked this week, with the **Reach target** to change in place; when one side is behind it says so ("Reach is behind, so the next pick is Reach work"). **Start next** is the one task Next best ranks first, with a big play button, why it's first and **Skip** (shows the one after it). Then one **Today** list: running, overdue, due today, pinned and done today. The time tracked today sits in the header, once. Pin a task with **⌘T**, right-click › Add to Today, the task panel's Today field, the selection bar or by dropping it on Today; ⌘N there adds a pinned task. A pinned task that isn't done stays the next day, marked "From yesterday". Hovering a row shows **→ Tomorrow**, which moves its due date and its pin to tomorrow. Rows work like the List (status circle, type, timer ring, click to open, ↑/↓ ↵ Space).
- **Notifications** (Settings › Notifications): a morning summary ("3 due today, 1 overdue"), a reminder for each task due that day and "Marketing is due in 2 days · 4 of 9 done", at a time you pick (all off until turned on), plus "Still working on X?" (Keep going · Pause) and the sleep prompt (Keep · Discard sleep time) while FlowMate isn't in front. macOS asks for permission the first time one is turned on; if notifications are off for FlowMate, Settings says so with a button to System Settings. Notifications need the app bundle (build-app.sh).
- **Projects**: create, rename, recolor and delete projects in the sidebar (right-click a project). Choose **All projects** or one project to set the scope. In the **New project** field, ↵ adds it and shows "Added Atlas · Open"; ⇧↵ adds it, shows it and opens its settings.
- **Milestones**: each has a color (a filled ◆ on its chips in rows and cards, its sidebar row and the Milestones tab; change it in the milestone panel or with right-click › Color). New milestones walk the palette, skipping the project's own color. Click a milestone in the sidebar (under a project's arrow) to open its **page**: its tasks on Board (every status of the project's workflow, all sprints and the backlog) and List, with its due date (click to change), "6 of 11 done", the time tracked against the time expected, **Mark complete** and ⓘ for the milestone panel. Each milestone page keeps its own tab, filters and sort, and the window reopens on it. **Show tasks** in a milestone panel, a Milestones row or the menu bar search opens the page too; new tasks added there join the milestone. Add milestones from the sidebar ("Add milestone" under a project), the Milestones tab or the project panel: ↵ adds with an Open toast, ⇧↵ adds and opens its page. ⌥⌘↑ / ⌥⌘↓ walk the sidebar (All projects, projects and the milestones listed under them).
- **Tasks** have a title, one project, an optional milestone, a sprint slot (active, next or backlog), a status from its project's workflow, a priority, an optional due date, an expected time (15m to 8h), the time spent, a Markdown description and subtasks.
- **Timers**: every play button is a ring that fills toward the task's expected time and turns red past it. Any number of timers can run at once; starting one never stops another. Marking a task Done pauses its timer.
- **Time log**: every timer session is kept. The task panel's **Time** section lists them by day ("Tue Oct 28 · 09:12–10:40 · 1h 28m"), with the running one on top; hover a session to edit its start, end and note in place (the end must be after the start and not in the future) or delete it, and use **Add time…** for time spent away from the timer (a day, a start, then a duration or an end time, and a note). "Adjust time" and "Stop at…" edit the same log, and every edit can be undone. Time tracked before the log existed shows as one *Imported* session per task, so totals don't change. The inspector shows when the task was created, last updated and completed (or canceled).
- **Sleep and screen lock**: if timers keep running while your Mac sleeps or sits locked for more than 5 minutes, a quiet prompt in the window and the menu asks "Timers ran while your Mac slept 2h 05m": **Keep** counts it, **Discard sleep time** ends each session when the Mac went to sleep and lets the timer go on from wake (⌘Z puts it back). Timers keep running across a quit and relaunch, and the session is recorded whole when you stop it. A prompt you haven't answered yet is kept with your data, so it's still there after quitting FlowMate.
- **Workflows**: each project has its own statuses (project panel › Workflow): rename them in place, pick a color, choose what each one means (Not started, Started, Done or Canceled), reorder by dragging or ⋯ › Move up/down, add and delete them (a status in use asks where its tasks go; a project always keeps a Not started and a Done status), or apply a preset: Simple (To do, In progress, Done), Dev (Backlog, To do, In progress, Review, Done, Canceled) or Kanban (To do, Doing, Done). Behaviour follows the kind, not the name: starting a timer moves a not started task to the first started status, done and canceled pause timers, aren't overdue and close with the sprint, and the menu bar's play starts the latest started task. Moving a task to another project keeps a status with the same name and kind, else the first of its kind. Every workflow edit can be undone.
- **Overview** (All projects, first tab, ⌘1, or ⌘K "Go to Overview"): this week's Make vs Reach on top, then one row per active project with a single **Needs you** verdict: "2 overdue" (click for the project's overdue tasks), "Nothing planned in Sprint 2", "Untouched 12 days", "Reach is light", or "On track". Each row also has the sprint's done / planned bar and the plan's Make / Reach split; rows that need you come first. A row opens its project and the ring starts its next task.
- **Roadmap timeline**: the Milestones tab has a **List / Timeline** toggle (remembered), in All projects (a lane per project) and in a project (one lane). Milestones are diamonds at their due dates in their color, filled by progress, outlined red when overdue or at risk, with a check once complete; dashed lines and a faint band mark each project's current sprint, a flag its target date, and a line Today. **Month** / **Quarter** zoom, scroll sideways, **Today** scrolls back. Hover a diamond for its due date, "N of M done" and hours left; click it for its page; **drag it sideways to move its due date** (snaps to days, shows the date while dragging, ⌘Z undoes). Milestones without a date wait in the **No date** tray underneath; **drag one onto the timeline** to give it the day under the pointer (⌘Z undoes). Month names stay in view at the left edge as you scroll, and a milestone's name stops before the project's target-date flag.
- **Views**: **Board** (one column per status of the project, drag cards between them; All projects shows a column per kind, with Canceled only when something is canceled), **List** (grouped by status, done and canceled collapsed), **Sprints** (drag tasks between Active, Next and Backlog; one project at a time) and **Milestones** (in All projects, a section per project, by due date; or the roadmap timeline). **⌘N** opens the New task composer pinned at the top of the first group or column, however long it is; tasks added there go first in their group and flash briefly. ⇧↵ adds and opens the task with its description ready to write.
- **Sprints**: each project has a two-week active sprint with a number, dates and a goal. **Complete sprint** closes the done tasks, keeps unfinished ones active, moves next-sprint tasks in, and starts the next sprint.
- **Capacity and velocity**: set **Hours per week on this project** in the project panel. The Sprints tab opens on one **sprint card**: dates, days left and the goal, the plan against capacity ("4h 15m of 27h planned"), the plan's Make / Reach against the Reach target, each project's own capacity (All projects), **Fill sprint** and **⋯** (goal, dates, Reach target, Plan sprints, Complete sprint). Sprint numbers appear only there. While the sprint has room, **Suggested** lists the backlog tasks Fill sprint would add, best score first, with **Add all** (or drag one in). Completing a sprint stores its planned, done and tracked time and the capacity; in a project the past sprints sit in one folded **Old sprints** group (with a Sprint column), with a velocity chart once there are three. The Complete sprint dialog shows your recent velocity (average of the last three) and warns when the next sprint starts with more.
- **Projects without sprints**: turn off **Plan in sprints** in the project panel. The Sprints tab, the sprint filter, column, grouping, chips, #sprint words (they stay in the title) and sprint commands go away; Board shows every open task (and done ones from the last two weeks), and Up next, the menu bar, the play button and Overview ("No sprints · 12 open") use all open tasks. Turning sprints back on starts a fresh sprint today with the work in progress (started, running or pinned to Today) active and the other open tasks in the backlog; one undo step.
- **Project settings**: an **icon** (an emoji, any typed emoji, or an SF Symbol in the project color) replaces the letter tile everywhere: sidebar, cards, rows, pickers, palette, menu bar and timeline. **Opens on** picks a view the project always opens on from the sidebar, menu bar, palette or Overview (Last used keeps the old behaviour). **New task time** and **New task sprint** are what new tasks get from the composer, quick add and the menu bar when no group, column or typed word picks them (a Board column always adds to the active sprint).
- **Task panel**: click a task to open it in a side panel. Edit the title, write the description with Write and Preview (checklists can be ticked in Preview), manage subtasks, and set status, priority, milestone, sprint, due date and expected time. Close it with ×, Esc or a click outside.
- **Menu bar dropdown**: a "Today 3h 20m · 2 due" line opens Today; **Up next** lists overdue, due today and pinned tasks, then the top not started tasks of the active sprints (up to 6, each with a play ring, ↑/↓ Space ↵ work). The proofreading tools fold to one line (click their caption; remembered). Search tasks, projects and milestones (a milestone opens its page), or type a title and press Enter to add a task. It lists the running timers with **Pause all**, and every project with a play button that starts its most recent In progress task (or the top To do of its sprint). A running project shows its sprint tasks with their own play buttons. The menu bar icon shows how many timers are running.
- **Keyboard**: with a task selected (or several, or one open in the panel), single keys edit it: **S** status, **P** priority (or **1**/**2**/**3** for high, medium, low), **M** milestone (type a new name to create one), **R** sprint, **D** due date (type "fri", "nov 18", "tomorrow" or "3d", or pick a preset), **E** expected time, **T** time spent ("1h 15m" sets it, "+15m" / "-5m" adjusts), **L** labels, **⇧M** move to project, **X** done (the workflow's first Done status) or back to its first Not started status. Each opens a small picker next to the row, card or selection bar: type to filter, ↑/↓, ↵, Esc. Every change shows a toast and undoes with ⌘Z. **⌥↑ / ⌥↓** move the selected rows within their group (manual sort, Sprints and Today's My focus); **⇧⌘A** selects nothing; ↑/↓ keep working while the task panel is open (the panel follows); **⌘I** opens or closes the panel; **⌘[ / ⌘]** step through tasks, or milestones when a milestone panel is open; **⌘0** moves to the sidebar (↑/↓, ↵ shows it, → lists a project's milestones, ← hides them, Esc returns). None of these fire while you type in a field. Right-click menus show the same keys, and **⌘/** lists every shortcut.
- **⌘K palette**: one fuzzy list over Today, projects, milestones, tasks of every project and commands (New task, New project, New milestone in…, Complete sprint, Show overdue, Group by…, Go to Overview, Switch to Board/List/Sprints/Milestones, show or hide a project's milestones, Pause all timers, Open settings, and the single-key actions for the selection). ↵ goes there or runs it, ⇧↵ opens the item's panel without leaving the view, a leading `>` lists commands only, and the empty palette shows your recent picks. ⌘F still filters the view on screen. A one-time hint ("Press ⌘K to jump anywhere") can be closed.
- **One quick-add language**: the composer, the menu bar search and the global New task box read the same words: `+atlas` (project; it also becomes the project new tasks go to), `#now` `#next` `#backlog`, `@beta`, `!high` / `!1`, `*review` (status), `%bug` (label), `due:fri`, `today`, `tomorrow`, `2h` / `~90m`; names with spaces take quotes or `_` (`@"beta launch"`, `@beta_launch`). Words that name nothing stay in the title. In the menu bar and the global box, **Tab** completes the word being typed.
- **Labels**: workspace-wide tags shared by every project ("bug", "waiting on client"). Add them in the task panel's **Labels** field, with **L** on the selection (toggle several with ↵ or Space; type a new name to create it), right-click › Labels…, the selection bar's **Labels** button, the composer's Labels chip, or `%bug` / `%"needs review"` in any New task box (a name that doesn't exist yet is created with the task; `#` stays the sprint word). Rows show a **Labels** column (hidden while nothing on screen has a label) with colored chips and "+2" for the rest; cards, Today and milestone pages show them too. Filter by **Label** (any of the chosen ones), **Group by Label** (a task with several labels is listed under each of them; dragging a task from one label group to another moves it: the old group's label comes off and the new one's goes on, like status groups; dropping on "No label" takes them all off), search finds label names, and ⌘K finds a label and shows its tasks in All projects. **Manage labels…** (in every label picker, the Label filter and ⌘K) adds, renames, recolors and deletes them with usage counts; deleting takes the label off every task and view, and Undo puts it back.
- **Task types and the Make / Reach mix**: every task can have a type (Build, Customers, Sales, Marketing and Ops to start; **Edit types…** in the task panel's Type field or the sprint menu adds, renames, recolors and deletes them). Each type is **Make** (building and running the product) or **Reach** (getting it to people) and has an impact from 1 to 10. Type `^sales` in any New task box, or give a project a **New task type**. Sprint group headers show "Make 14h · Reach 3h", and the sprint menu shows the split as a bar against a **Reach target** (No target, or 20–70% of the typed time); a bucket more than 10 points behind turns amber ("Reach is light"). Nothing is ever blocked.
- **Next best** (Today's **Start next** shows its first pick): the open current work of every project, scored 0–100 ("Impact 8 · 30m left"). The score is impact × 10 × an effort factor (1.0 up to 30m left, down to 0.6 past 4h), +20 for High priority or −20 for Low (Medium adds nothing), +5 when the task's bucket is behind the mix target. Impact is the task's own, else its milestone's, else its project's (5 when none set), averaged with its type's. Right-click a task › Next best for **Send up / Send down** (the first press moves 5 points, the second 10, every one after that 15; the other direction takes back the last step), **Send to top** (first for the rest of the day) and **Back to normal**; nudges clear when the task closes or the sprint completes. Tasks already in Today's sections aren't repeated. **In sprint planning** the Sprints view shows the same score in a **Score** column (click it for how it's made and the nudges; right-click a row › Next best does the same). **Fill sprint** (the sprint card) and **Add all** (Suggested) move the best-scoring backlog tasks into the active sprint until its capacity is used, rechecking the Make / Reach mix after every pick; ⌘Z undoes.
- **Saved views**: filter, sort and group a List or Board, then **Save view…** in the filter bar (a name and an icon). Views sit in the sidebar's **Views** section with a live count; a click shows its scope (All projects, a project or a milestone page) on its tab with its filters, without touching the project's own. Change the filters and the bar says **Modified · Update view · Revert** (a dot marks the sidebar row). Right-click a view to Rename, Duplicate, Update to current or Delete; drag to reorder. Views are stored with your data, come back on relaunch, and are part of ⌥⌘↑/↓, ⌘0 and ⌘K. With no views yet, the section suggests *High priority* and *Due this week* (made only when clicked).
- **Timer keys**: **⌥-click** a play button (or **⌥Space**) to start it and pause every other timer; **⇧Space** in the window pauses all. In the menu bar, **⌘1–⌘9** start or pause the timer of the Nth listed task. Settings › General › Task hotkeys can add two global shortcuts (off by default): *Pause or resume the last timer* and *Open the menu bar with search focused*.

Task data is saved on your Mac in `~/Library/Application Support/FlowMate/workspace.json` (with a `.bak` copy of the last good file). All reads and writes go through the `WorkspaceRepository` protocol (`Sources/Tasks/Data/`), so a backend can replace local storage later.

## Updates

FlowMate updates itself (Sparkle 2) from GitHub Releases: Settings › Updates has **Check for updates**, automatic checks and downloads, and backups. Before every update installs, your tasks and settings are copied to `Backups/` next to your data (the newest 5 are kept), and **Restore…** puts one back. See [`docs/RELEASING.md`](../../docs/RELEASING.md) for how releases are built.

## Using FlowMate

1. Select some text in any app.
2. Press the shortcut (`⌘.` by default; change it in Settings → Proofreading).
3. Review the result and press **Replace** (`⌘↩`), or **Copy**.

The menu bar icon shows what's happening:

| Icon | Meaning |
| --- | --- |
| ✓ circle | Ready |
| Arrows | Proofreading |
| Thumbs up | Done |
| Warning triangle | Failed, nothing selected, or the result was left on the clipboard because you switched apps |
| Plug | The AI provider can't be reached |

## Permissions

FlowMate needs **Accessibility** access to notice the shortcut and to copy and paste in other apps. On first launch macOS asks for it. You can also grant it in **System Settings → Privacy & Security → Accessibility**, or from the FlowMate menu (**Allow**). The menu shows a warning until access is granted.

## Installing Ollama

FlowMate uses `gemma3:4b` by default.

```bash
brew install ollama
```

```bash
brew services start ollama
```

```bash
ollama pull gemma3:4b
```

FlowMate connects to `http://127.0.0.1:11434`. Any other installed model can be picked in the menu bar under **Model**.

## Building

1. Install Swift 5.9+ (Xcode or `xcode-select --install`).
2. Create the signing certificate (see below). It only has to be done once.
3. Build the app bundle (from `apps/macos`; the script can also be called from anywhere):

```bash
./build-app.sh
```

This creates `FlowMate Dev.app`, signs it, and opens it. It quits a running FlowMate Dev first, never the released FlowMate.

**Dev and release are separate apps.** A local build is *FlowMate Dev* (`com.asem-mkl.FlowMate.dev`, "DEV" next to its menu bar icon): its tasks, settings and logs live in `~/Library/Application Support/FlowMate Dev`, its API keys under the Keychain service `com.asem-mkl.FlowMate.dev`, and it has its own Accessibility and notification permissions and login item. It never updates itself. The released FlowMate (`com.asem-mkl.FlowMate`, built only by the release workflow with `CHANNEL=production`) keeps `~/Library/Application Support/FlowMate`, so both can run side by side. Give the dev copy different global shortcuts in its Settings if both run at once, or a shortcut fires in both.

For development you can also use `swift build`, `swift run` and `swift test`; these count as dev too and use the FlowMate Dev folder. Launch at login only works from the app bundle. To try a build on throwaway data, point it at another folder: `FLOWMATE_DATA_DIR=/tmp/flowmate .build/debug/FlowMate` (workspace.json, config.json and logs/ go there, and it doesn't ask for Accessibility at launch); `FLOWMATE_WORKSPACE_FILE=/tmp/flowmate/workspace.json` moves only the task data.

## Installing on another Mac

The simplest way is to build on that Mac (steps above). The certificate has to be created on each Mac you build on.

If you copy a built `FlowMate.app` from another Mac instead:

- macOS blocks it on first open because it isn't notarized. Open it once, then allow it in **System Settings → Privacy & Security → Open Anyway**.
- The build only runs on the same chip type (Apple Silicon or Intel) as the Mac that built it.
- Grant Accessibility access on the new Mac.

## Signing the app

Signing with the same certificate every time keeps the Accessibility permission and the Keychain access working across rebuilds.

1. Create a self-signed code signing certificate:
   - Open Keychain Access (Applications → Utilities → Keychain Access).
   - From the menu: Keychain Access → Certificate Assistant → Create a Certificate.
   - Fill in:
     - Name: `FlowMate Dev Certificate` (must match the name in `build-app.sh`).
     - Identity Type: Self Signed Root.
     - Certificate Type: Code Signing.
     - Check "Let me override defaults".
   - Accept the defaults until you see Key Usage, and make sure Code Signing is included.
   - Finish. The certificate appears in login → Certificates.
2. Trust the certificate:
   - Double-click the new certificate in Keychain Access.
   - Expand Trust and set Code Signing to Always Trust.
   - Close it and enter your password if prompted.

## Configuration

Settings are stored in `~/Library/Application Support/FlowMate/config.json`:

- Provider URLs (Ollama, OpenAI)
- Proofreading settings (provider, model, instructions, shortcut, dialog preferences)
- App settings (number of recent results; the old appearance setting is kept but ignored)

Settings missing from the file (for example after an update) get their default values. If the file can't be read at all, it is copied to `config.json.bak` before defaults are used.

The OpenAI API key is stored in the login Keychain (service `com.asem-mkl.FlowMate`, or `com.asem-mkl.FlowMate.dev` for FlowMate Dev), not in the file. Keys found in older config files are moved to the Keychain automatically.

Logs are written to `~/Library/Application Support/FlowMate/logs` and kept for 7 days. They don't contain the text you proofread. Settings → Maintenance can open or clear them, or reset all settings.

## Architecture

- **UI**: SwiftUI views in `Sources/UI/Views/`, built on the Focus design system
- **Design system**: Focus, documented in [`docs/design/FOCUS.md`](../../docs/design/FOCUS.md) with tokens in `docs/design/focus-tokens.json` and reference screens in `docs/design/reference/` (repository root). The SwiftUI tokens and shared components are in `Sources/UI/Focus/Focus.swift`.
- **Tasks**: models, the repository and `TaskStore` in `Sources/Tasks/Models/` and `Sources/Tasks/Data/`; the main window and menu sections in `Sources/Tasks/UI/`
- **Services**: AI providers, clipboard, shortcut and Keychain handling in `Sources/Core/Services/`
- **Models**: configuration and status models in `Sources/Models/`
- **App**: app delegate and state in `Sources/App/`

Networking uses Alamofire (Ollama) and URLSession (OpenAI).

## Testing

```bash
swift test
```

Tests use a temporary config file and an in-memory secret store, so they never touch your settings or Keychain.
