# FlowMate

A macOS menu bar app for a solo engineer running many projects: a task manager with timers that run side by side, plus AI proofreading. Select text in any app, press a shortcut, and FlowMate fixes typos and grammar using a local Ollama model or OpenAI.

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

## Tasks

Open the main window with **Open FlowMate** in the menu bar dropdown (`⌘O`).

- **Projects**: create, rename, recolor and delete projects in the sidebar (right-click a project). Choose **All projects** or one project to set the scope.
- **Tasks** have a title, one project, an optional milestone, a sprint slot (active, next or backlog), a status from its project's workflow, a priority, an optional due date, an expected time (15m to 8h), the time spent, a Markdown description and subtasks.
- **Timers**: every play button is a ring that fills toward the task's expected time and turns red past it. Any number of timers can run at once; starting one never stops another. Marking a task Done pauses its timer.
- **Time log**: every timer session is kept. The task panel's **Time** section lists them by day ("Tue Oct 28 · 09:12–10:40 · 1h 28m"), with the running one on top; hover a session to edit its start, end and note in place (the end must be after the start and not in the future) or delete it, and use **Add time…** for time spent away from the timer (a day, a start, then a duration or an end time, and a note). "Adjust time" and "Stop at…" edit the same log, and every edit can be undone. Time tracked before the log existed shows as one *Imported* session per task, so totals don't change. The inspector shows when the task was created, last updated and completed (or canceled).
- **Sleep and screen lock**: if timers keep running while your Mac sleeps or sits locked for more than 5 minutes, a quiet prompt in the window and the menu asks "Timers ran while your Mac slept 2h 05m": **Keep** counts it, **Discard sleep time** ends each session when the Mac went to sleep and lets the timer go on from wake (⌘Z puts it back). Timers keep running across a quit and relaunch, and the session is recorded whole when you stop it.
- **Workflows**: each project has its own statuses (project panel › Workflow): rename them in place, pick a color, choose what each one means (Not started, Started, Done or Canceled), reorder by dragging or ⋯ › Move up/down, add and delete them (a status in use asks where its tasks go; a project always keeps a Not started and a Done status), or apply a preset: Simple (To do, In progress, Done), Dev (Backlog, To do, In progress, Review, Done, Canceled) or Kanban (To do, Doing, Done). Behaviour follows the kind, not the name: starting a timer moves a not started task to the first started status, done and canceled pause timers, aren't overdue and close with the sprint, and the menu bar's play starts the latest started task. Moving a task to another project keeps a status with the same name and kind, else the first of its kind. Every workflow edit can be undone.
- **Views**: **Board** (one column per status of the project, drag cards between them; All projects shows a column per kind, with Canceled only when something is canceled), **List** (grouped by status, done and canceled collapsed), **Sprints** (drag tasks between Active, Next and Backlog; one project at a time) and **Milestones**.
- **Sprints**: each project has a two-week active sprint with a number, dates and a goal. **Complete sprint** closes the done tasks, keeps unfinished ones active, moves next-sprint tasks in, and starts the next sprint.
- **Task panel**: click a task to open it in a side panel. Edit the title, write the description with Write and Preview (checklists can be ticked in Preview), manage subtasks, and set status, priority, milestone, sprint, due date and expected time. Close it with ×, Esc or a click outside.
- **Menu bar dropdown**: search tasks and projects, or type a title and press Enter to add a task. It lists the running timers with **Pause all**, and every project with a play button that starts its most recent In progress task (or the top To do of its sprint). A running project shows its sprint tasks with their own play buttons. The menu bar icon shows how many timers are running.

Task data is saved on your Mac in `~/Library/Application Support/FlowMate/workspace.json` (with a `.bak` copy of the last good file). All reads and writes go through the `WorkspaceRepository` protocol (`Sources/Tasks/Data/`), so a backend can replace local storage later.

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
3. Build the app bundle:

```bash
./build-app.sh
```

This creates `FlowMate.app`, signs it, and opens it. Move it to `/Applications` so **Launch at login** works.

`build-app.sh` quits any running FlowMate first.

For development you can also use `swift build`, `swift run` and `swift test`. Launch at login only works from the app bundle. To try a build without touching your real tasks, point it at another data file: `FLOWMATE_WORKSPACE_FILE=/tmp/flowmate/workspace.json .build/debug/FlowMate`.

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

The OpenAI API key is stored in the login Keychain (service `com.asem-mkl.FlowMate`), not in the file. Keys found in older config files are moved to the Keychain automatically.

Logs are written to `~/Library/Application Support/FlowMate/logs` and kept for 7 days. They don't contain the text you proofread. Settings → Maintenance can open or clear them, or reset all settings.

## Architecture

- **UI**: SwiftUI views in `Sources/UI/Views/`, built on the Focus design system
- **Design system**: Focus, documented in `docs/design/FOCUS.md` with tokens in `docs/design/focus-tokens.json` and reference screens in `docs/design/reference/`. The SwiftUI tokens and shared components are in `Sources/UI/Focus/Focus.swift`.
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
