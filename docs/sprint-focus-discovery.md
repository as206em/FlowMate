# Sprint focus: keeping a builder honest without a wall of process

Discovery, not a spec. Nothing here is built.

## TL;DR: the plan that helps most

You drift to building because building is the easy, rewarded work. Fix it at planning time, not mid-flow, with soft signals and no blocking. All scores are 1–10.

1. **Next best list** (biggest win). One ranked list across every project, ordered by impact ÷ effort, each row saying why. Impact (1–10) is set on project, milestone and type, and tasks inherit it. Ends the scrolling between projects.
2. **Type + mix bar.** Tag tasks Make or Reach (Build, Customers, Sales, Marketing, Ops). The sprint header shows planned mix against your target (say 50/50) and turns amber when Reach is light. This is the drift made visible.
3. **Outcomes, not a goal sentence.** Up to three numbered sprint outcomes ("2 paying users"). They feed the ranking: tasks serving the lead outcome float up.
4. **Deferral signal.** Count how often a task is pushed. At 3×, ask once: Drop · Shrink · Do today · Still important. Reach tasks default to Shrink (likely avoidance); Build tasks default to Drop.
5. **AI as a helper, last.** Suggest the type chip, draft impact scores, and run one weekly triage at planning. Never re-rank silently.

Rules: nothing blocks, friction only at planning and review, everything off by default, 60 seconds to set up a sprint.

Build order: 1 → 2 → 3 → 4 → 5. Steps 1 and 2 need no AI and no outcomes, and already deliver most of the value.

## The problem, stated precisely

You are not short of discipline. Every default in a normal task app (a flat backlog, "what's next?", time tracking) rewards the work you already prefer. Building has instant feedback, full control and no risk of rejection. Selling, support and marketing have delayed feedback, ambiguous "done", and a chance of being told no. A neutral tool therefore drifts to building, and every sprint ends with more shipped and no more customers.

So the product job is not "manage the sprint". It is **make the drift visible while you plan, and keep it out of your way while you work**.

## Psychology: what explains it, and what it implies

Findings marked ✓ came from sources found this session; the rest is established psychology recalled from general knowledge, not re-verified here.

| Mechanism | What it says | Design consequence |
|---|---|---|
| Procrastination as mood repair (Sirois & Pychyl) | People avoid tasks that trigger anxiety or ego threat and switch to pleasant ones. Building is the "productive" escape from outreach. | Don't shame. Make the avoided work smaller and more specific, not bigger. |
| Task avoidance via vague tasks | "Do marketing" is ungradable, so it never starts. | Grow tasks need a concrete shape (a named person, a count, a channel). |
| Hyperbolic discounting | Build feedback is today; customer feedback is weeks away. | Show the long-term outcome next to today's work, so it competes. |
| Implementation intentions (Gollwitzer) | "When X, I will Y" plans help goal attainment, d ≈ .65 in a 94-test meta-analysis ✓, but only when goal commitment is already high ✓. | Plan the Grow work at a time and place, once, during planning. Don't nag later. Commitment must come first, so the sprint's outcome has to be something you chose. |
| Pre-commitment (Ulysses) | Decisions made when calm beat decisions made mid-flow. | Put the friction at **planning** time, never at execution time. |
| Reactance (Brehm) | Rules that feel imposed provoke resistance. Process that blocks you will be turned off within a week. | Soft limits only. Every limit is yours, editable, and overridable in one keystroke. |
| Goodhart and output vs outcome (Perri's build trap ✓) | Counting activity ("5 calls") gets gamed. Teams drift to shipping as the success measure ✓. | Define success as an outcome you can't fake (a signup, a reply, a paid user). Count activity only as a leading signal. |
| Ratio rules in the field ✓ | Indie founders use a 50/50 code/marketing split. Yongfook alternates whole weeks, others block days. These are anecdotes, and several founders admit their real split is far worse than the rule. | The ratio is a starting default you set, not a research-backed number. Batching by day or week reduces context switching. |
| Zeigarnik / goal gradient (recalled, not found) | Open loops nag, and effort rises near the finish. | One visible "outcome progress" bar at the top of the sprint, which is the gradient. |

## What FlowMate already has

- One workspace-wide sprint (`SprintState`) with a free-text **goal**, length 1–4 weeks.
- **Capacity** in hours per project, with a planned-vs-capacity bar, and velocity history (`PastSprint`).
- **Labels**, workspace-wide, and `%label` in quick add.
- A per-project `usesSprints` toggle and an Overview of cards per project.

Gaps: the goal is text with no measure, there is no notion of task type, no limit on how many projects share a sprint, and nothing compares what you planned against what you intended.

## Proposal: Sprint Focus

Four small ideas, each optional and each defaulting to off.

### 1. Outcomes instead of a goal sentence
A sprint has up to three **Outcomes**, each one line with a number: "2 paying users", "6 customer conversations", "Landing page live". Each has a target and a current value you tick up by hand (or checkbox for yes/no). They sit in the sprint header as a progress strip. This replaces "Set a goal for this sprint", which is how bureaucracy-free success gets defined.

Optionally mark one **lead** (outcome) and the rest **supporting**, so there's a single answer to "did this sprint succeed?".

### 2. Task type, with a mix target
Each task gets a **type** from a small list you define in settings. Suggested default: **Build · Customers · Sales · Marketing · Ops**, grouped into two buckets you name: *Make* and *Reach*. A project can carry a default type, and `^reach` / `^build` works in quick add, so entering a task costs nothing extra.

The sprint has a **mix target** in hours, such as Make 50 / Reach 50, and the Sprints header shows it next to the capacity bar:

> Plan: Make 14h · Reach 3h  (target 50 / 50)  ⚠ Reach is light

Amber and red follow the existing capacity rules (90% / 100%). It never blocks anything.

### 3. A cap on active projects
A **project cap** per sprint (say 2). Sprint planning shows "3 projects in this sprint (cap 2)" in amber, with the lowest-planned one suggested to defer. Pinning a third project to Today only shows a toast.

### 4. Plan Reach first
In the Sprints view, **Reach tasks are planned before Make tasks**: the Reach slot is shown above Make, and empty it reads "Nothing here to reach customers yet". The point is ordering. Whatever gets decided first gets protected; whatever is added last gets cut.

### The mirror, not the cop
- **Today** gets one quiet line: "Make 3h · Reach 0h this sprint, target 50 / 50". No popups.
- **Complete sprint** shows planned mix, tracked mix and outcome results, then asks two things: *Did the outcome land?* and *Keep, change or drop it?* One screen, 30 seconds.
- **Past sprints** extend the velocity chart with the mix, so drift shows as a trend rather than a guilt moment.

## Rules that stop it becoming bureaucracy

1. Nothing blocks. Every limit is a color and a number.
2. Friction only at planning and review. Nothing extra on a task you are already doing.
3. Off by default; a sprint without outcomes works exactly as today.
4. Hand-entered numbers only. No integrations in v1.
5. Under 60 seconds to set up a sprint: three outcomes, a mix, a cap, each with a sensible default carried from the last sprint.

## Suggested build order

1. **Task type + mix bar** in the Sprints header (data: one field on `TaskItem`, a type list in the workspace). This alone shows the drift.
2. **Outcomes** in the sprint header and the Complete sprint dialog, stored on `SprintState` and `PastSprint`.
3. **Project cap** warning.
4. Reach-first ordering, Today line, mix history chart.

## Addendum: "what is the most valuable thing to pick next?"

The cost today is scrolling between projects to compare things that are not comparable. The fix is one ranked list, **Next best**, across every project, with the reason shown on each row.

### Weights at four levels, one number each
Every score in the product is a whole number from **1 to 10** (10 = most valuable). Impact is set once at the level where it is cheap, and it flows down:

| Level | Set by | Example |
|---|---|---|
| Project | you, rarely | Atlas = 9, side project = 4 |
| Milestone | you, when you create it | "First 10 paying users" = 9 |
| Type | settings | Customers = 9, Sales = 9, Build = 5, Ops = 3 |
| Task | optional override | only when this one is unusual |

A task's **impact** is its own value if set, else the milestone's, else the project's; the result is averaged with its type's value and rounded, so it stays on the 1–10 scale. Nobody has to score every ticket: most tasks inherit. This is the same idea as the existing priority field, but priority says "urgent", impact says "worth it", and the two should not be merged.

### Ranking
`score = impact × alignment ÷ effort`, then sorted. Where:
- **alignment** is a boost when the task serves a lead outcome of this sprint, and when its type bucket is behind its mix target (Reach is light, so Reach tasks float up). This ties the ranking to the Sprint Focus idea above.
- **effort** is the expected time. Cheap and valuable beats big and valuable, which is the standard WSJF/RICE shape.
- Overdue and due-today tasks keep their existing place above this list. The ranking only orders the rest.

Each row shows why: "Impact 9 · Reach is behind · 30m". An opaque score would get ignored; a visible reason can be argued with.

### Deferral as a signal
Your instinct is sound: repeated avoidance is data. Two different things look alike, though:
- **Not important** — you keep moving it because other things matter more. It should decay.
- **Avoided** — you keep moving it because it is uncomfortable. It should surface, not sink.

The tool can't tell which from the count alone, so make the count visible and ask once. The store needs a `deferCount` on `TaskItem`, bumped when a due date is pushed later, when the task is moved to Tomorrow, or when it rolls out of a sprint unfinished (Complete sprint already knows the last case). At 3 deferrals the row shows "Moved 3×" and a one-tap choice: **Drop it · Shrink it · Do it today · Still important**. Dropping is the default highlighted option for Build tasks; for Reach tasks the highlighted option is Shrink, because that is where avoidance, not irrelevance, is the likelier cause. "Shrink" splits off a 15-minute first step. Only after you answer "Not important" does the score decay.

### Can AI do the scoring and labeling?
Yes for labeling, partly for scoring, and FlowMate already has the plumbing (`AIService.generate` with Ollama or OpenAI, and the quick-add parser).

- **Type labeling (Make vs Reach, "is this marketing?")** — a good fit. It is a small classification of a short title and notes into your own type list. Run it on task creation, show the guess as a removable chip, and learn from your corrections by feeding the last handful of corrected examples into the prompt. With a local Ollama model nothing leaves the Mac.
- **Impact scoring** — worth suggesting, not worth trusting. The model can read your outcomes and propose "this task serves 'first 10 paying users', impact 8", but it doesn't know your market, and it will tend to rate vague tasks as important. Treat it as a draft you accept with one key, and show it dimmed until you do.
- **Weekly triage pass** — one call at planning time: "here are your open tasks and this sprint's outcomes; which three serve the outcome most, and which look like busywork?" This is likely the most useful use, because it runs once, at planning, where friction belongs.
- **Don't** let it re-rank silently, reorder your Today, or push notifications. A ranking that changes under you is the thing that makes people stop trusting a task tool.

The prompts need your outcomes in them, so AI features depend on the Outcomes idea above being built first.

### Build order for this addendum
1. Impact on project, milestone and type; inherit down; the **Next best** list with reasons (no AI).
2. `deferCount` and the "Moved 3×" prompt.
3. AI type labeling as a suggested chip.
4. AI weekly triage at sprint planning, then AI impact drafts.

## Spec: the 0–100 score, nudges and keep-warm

### Final score, 0–100
`score = clamp(base + alignment + nudge, 0, 100)` where
- **base** = impact (1–10) × 10 × effort factor. Effort factor: 1.0 up to 30m, 0.9 up to 1h, 0.8 up to 2h, 0.7 up to 4h, 0.6 beyond. So a 9-impact 30m task scores 90, the same task at 4h scores 63.
- **alignment** = +10 when the task serves the lead outcome, +5 when its type is behind the sprint's mix target.
- **nudge** = your manual push (below).

Every row shows the number and the split: "82 = 72 base + 10 outcome".

### Send up / send down
Each press on the same task, in the same direction, moves it further than the last:

| Press | Step |
|---|---|
| 1st | ±5 |
| 2nd | ±10 |
| 3rd and later | ±15 |

Steps add up (three sends up = +30). Pressing the opposite direction undoes the last step instead of starting a new run. Nudges clear when the task is done or the sprint is completed, so old pushes don't haunt a new sprint.

- **Send to top:** pins the task as #1 regardless of score. Several pins stack with the newest first. They show a pin mark and expire at the end of the day unless you pin again, so a pin can't silently outlive its reason.
- **Back to normal:** one action (Reset on the row, or ⌥-click) removes the nudge and the pin, so the task rejoins the ranking at its computed score.
- Send down is also a deferral: it counts toward the "Moved 3×" prompt below.

### Ten projects: how lower-ranked ones keep moving
A pure ranking starves everything outside the top two projects. The fix is a **cadence** per project, derived from its impact so you set nothing extra:

| Project impact | Should be touched |
|---|---|
| 9–10 | daily |
| 6–8 | every 2–3 working days |
| 3–5 | weekly |
| 1–2 | every two weeks |

The ranking stays honest. On top of it, the list gets a **Keep warm** row (at most two a day) for any project past its cadence, showing that project's best small task (highest score, 30m or less). It says "Orbit: untouched 6 days, due every 5". Finishing or starting that task clears it. Two caps stop it becoming noise: never more than two Keep warm rows, and a project at impact 1–2 can only appear once per cadence period. The existing "Untouched N days" on Overview already holds the data.

### Outcomes, in practice
An outcome is a sprint-level result with a number, e.g. "2 paying users by Nov 20", target 2, current 0. You link tasks to it either by hand (an "Outcome" field in the task panel) or by their milestone (a milestone can serve an outcome, so all its tasks inherit the link). Linked tasks get +10 in the ranking, so with an outcome of "first 2 paying users", "write onboarding email" ranks above "refactor settings screen" even if both have the same impact. Unlinked tasks aren't penalised, they just don't get the boost. The header shows "2 paying users 0/2", and the Complete sprint review shows which outcomes landed and how many tasks served each, so a sprint where 80% of the hours served no outcome is visible.

### Deferral, in practice
A deferral is any time you push a task later: change its due date to a later day, "→ Tomorrow", leave it unfinished when a sprint completes, or press Send down. The task keeps a count. Nothing happens at 1 or 2. At 3 the row shows "Moved 3×" and offers four answers: **Drop** (cancel it), **Shrink** (split off a 15-minute first step and keep the rest), **Do today** (pin it), **Still important** (resets the count and acknowledges the avoidance). The default highlighted answer depends on type: Build leans Drop, Reach leans Shrink, because delayed Reach work is more often discomfort than irrelevance. Only "Drop" or ignoring the prompt twice lowers the score (−10 at 4 moves, −20 at 6).

## Open questions for you

- Are the two buckets (Make / Reach) enough, or do you need to tell Sales apart from Support?
- Should the mix target be hours, or number of tasks? Hours matches capacity, but Reach work is often hard to estimate.
- Do outcomes belong to the whole sprint, or to a project within it?
- Is a 1–10 impact scale enough, or do you want to see it as a value like expected revenue?
- When you defer something three times, is it usually "not important" or "I don't want to"? That decides the default in the prompt.
- Does a 2-week sprint feel right for Reach, or would a "Reach day" each week fit better (the day-block approach some founders use ✓)?

## Sources
- Melissa Perri on the build trap: [melissaperri.com](https://melissaperri.com/blog/2014/08/05/the-build-trap), [Dragonboat summary](https://dragonboat.io/glossary/build-trap/)
- Gollwitzer & Oettingen, implementation intentions: [review (2013)](https://www.socmot.uni-konstanz.de/sites/default/files/gollwitzer_oettingen_2013-Implementation_Intentions.pdf)
- Founder time splits: [Bannerbear on 50/50](https://bannerbear.com/blog/why-you-should-do-50-coding-and-50-marketing-as-a-solo-tech-founder), [Indie Hackers threads](https://www.indiehackers.com/post/whats-new-the-perfect-building-to-marketing-ratio-b3962c31e1)
