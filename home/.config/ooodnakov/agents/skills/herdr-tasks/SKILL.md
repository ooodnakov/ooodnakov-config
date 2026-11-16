---
name: herdr-tasks
description: "Use when delegating work inside Herdr, or when the user wants to see and supervise delegated work: create a `herdr-task`, spawn its agent as a labelled herdr-core terminal using the same harness you are running in, and publish every task's result as a `herdr-artifact`."
---

# Herdr tasks and artifacts

Herdr's Tasks panel lists the tasks of a folder, the live status of each task's agent, that agent's last screen, and the artifact it published. Two commands drive it, and both talk to the same per-folder store:

- `herdr-task` — one task list per folder: `add`, `spawn`, `label`, `bind`, `set`, `list`, `show`, `rm`, `kill`.
- `herdr-artifact` — reports and notes per folder: `add`, `update`, `list`, `show`, `rm`.

Act on `--folder …`, else the current git worktree, else the cwd; `--json` for machine-readable output.

## Delegate: one task, one agent, the same harness

```sh
herdr-task add "Review the retry logic" --note "src/fetch.ts; report findings."
# prints: t-20261024-ab12cd  todo  Review the retry logic

herdr-task spawn t-20261024-ab12cd -- <your own agent CLI and prompt>
# prints: t-20261024-ab12cd  t12  Review the retry logic
```

**Spawn the harness you are running in.** Codex runs Codex (`codex exec "…"`), omp runs omp (`omp -p "…"`), Claude Code runs Claude Code (`claude -p "…"`); never assume a different one is installed, and do not mix harnesses unless the user asks. The task's agent is then an ordinary herdr-core terminal, labelled `herdr.task=<slug>#<id>`:

```sh
hc wait t12                  # until it stops working (or --output "…")
hc read t12                  # its screen, to see what it said
hc send t12 "also check the timeout"
herdr-task set t-20261024-ab12cd blocked   # when it needs the human
```

For repo work add `--worktree` (worktrunk when installed, else `git worktree add`), so parallel tasks never share a checkout; `--keep-open` keeps the terminal readable after the program exits. If you started the terminal yourself, pass `--label "$(herdr-task label <id>)"` to `hc run` and then `herdr-task bind <id> <terminal>`.

## Publish the result: every task ends in an artifact

A task is not finished until its result is an artifact — the panel's OUTPUT is only the agent's last screen; the artifact is what the human keeps and can re-read:

```sh
herdr-artifact add "Review the retry logic" --from /tmp/report.md --folder <folder>
# or, for something short: --text "Markdown…"
herdr-artifact update a-20261024-9f31c2 --from /tmp/report.md   # a later version
herdr-task set t-20261024-ab12cd done
```

Write the report to a temp file, never into the repo. Include what changed and how it was verified; keep it short. The artifact appears in the Artifacts panel beside the tasks list.

## Rules

- One task per delegated piece of work, with a note the agent can act on.
- Never invent an id: `herdr-task list` first, or use the id `add` printed.
- Keep status honest: `doing` while it runs, `blocked` when it needs the human, `done` only after the artifact exists.
- Agents you start from a task terminal are sub-agents automatically (`parent`) and count under the task.
- Don't `kill` a terminal the human opened or is typing in; the panel's Stop button is theirs.
