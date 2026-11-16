---
name: herdr-tasks
description: "Use when delegating work to a background or sub-agent inside Herdr, or when the user wants to see and supervise that work in Herdr's Tasks panel: create the task with `herdr-task`, spawn the agent in a labelled herdr-core terminal, and report status back to the task."
---

# Herdr tasks

The human watches Herdr's Tasks panel; each task row can show the agent working on it (live status, sub-agent count) and open that agent's terminal to inspect or intervene. Your job is to make the work visible: one task per delegated piece, one labelled terminal per task agent.

## Delegate

```sh
herdr-task add "Review the retry logic" --note "Focus on src/fetch.ts; report findings as an artifact."
# prints: t-20261024-ab12cd  todo  Review the retry logic

herdr-task spawn t-20261024-ab12cd -- claude -p "Review the retry logic in src/fetch.ts"
# prints: t-20261024-ab12cd  t12  Review the retry logic
```

`spawn` runs `hc run --keep --bg --json --label herdr.task=<slug>#<id> --cwd <folder> -- <argv>` and stores the terminal address on the task. It starts in the task's folder (a git worktree root when there is one); pass `--cwd` to change that and `--dry-run` to see the command. `--keep-open` keeps the terminal after the program exits (`sh -c '<command>; exec "${SHELL:-sh}"'`), and `--worktree [path]` makes `herdr/<id>` in its own worktree (default `<repo>-wt/<id>` beside the repo) and spawns there, so parallel edits never share a checkout. It uses worktrunk when installed (`git-wt` on Windows, `wt` elsewhere) and falls back to `git worktree add -b`; either way the agent works in that worktree and should use worktrunk's commands (`wt list`, `wt switch`) for further worktree work, as the shared agent instructions already say.

Then treat the terminal like any herdr-core terminal:

```sh
hc wait t12                 # until the agent stops working
hc read t12                 # its screen, to see what it said
hc send t12 "also check the timeout"   # talk to it
herdr-task set t-20261024-ab12cd done  # or blocked / doing
herdr-task kill t-20261024-ab12cd      # end the agent, if it must stop
```

## Start the terminal yourself

If you already have a terminal (or another tool started it), label it and bind it:

```sh
hc run --bg --json --label "$(herdr-task label t-20261024-ab12cd)" -- claude -p "…"
herdr-task bind t-20261024-ab12cd t12
```

`herdr-task label <id>` prints `herdr.task=<slug>#<id>`; the panel matches the label, so `bind` is only needed when the label was not passed.

## Rules

- One task per piece of delegated work, with a note the reviewer can act on: the panel is the human's view, not yours.
- Never invent an id: `herdr-task list` first (or read the id printed by `add`).
- Keep status honest: `doing` while the agent runs, `blocked` when it needs the human, `done` when you have the result.
- Agents you start with `hc run` from a task terminal are sub-agents automatically (`parent`); they count under the task.
- Don't `kill` a terminal the human opened or is typing in; the panel's Stop button is theirs.
