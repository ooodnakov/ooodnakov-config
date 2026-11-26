# Herdr app

This page covers the Herdr app configuration that this repo manages.

## Configuration files

The [Herdr app](https://herdr.dev) keeps its whole interface as files in `~/.config/herdr-app`, and Herdr rewrites parts of that folder on every start (`frame/`, `icons/`, `layouts/.state/`, sockets). The manifest therefore excludes the folder from autolink and links only the files this repo owns:

- `home/.config/herdr-app/settings.json` — `theme` names the managed Gruvbox pair
- `home/.config/herdr-app/keys.json` — the live key map plus `Alt+Shift+T` (Tasks) and `Alt+Shift+A` (Artifacts): a key runs one command, so the tab bar's mod combines the `layout.select` and `layout.show` a panel open needs; both work in `main-panels`
- `home/.config/herdr-app/themes/gruvbox-{dark,light}.json` — the palettes, selectable in Settings → Look
- `home/.config/herdr-app/mods/oo-tasks/` — the Tasks panel
- `home/.config/herdr-app/mods/oo-artifacts/` — the Artifacts panel
- `home/.config/herdr-app/mods/oo-agent-head/` — the thin header above the agent terminal, naming the selected task and linking back to Tasks
- `home/.config/herdr-app/mods/tabs-panels/` — a clone of Herdr's tab bar with Tasks and Artifacts buttons beside Files and Changes, top right
- `home/.config/herdr-app/layouts/main-panels.json` (with `main-panels.svg`) — a clone of Herdr's `main` whose right-hand panel stack holds Files, Changes, Tasks, Artifacts and an `oo-agent` column (the `oo-agent-head` header above a `{ "agent": "focused" }` block); the top-right buttons switch between them and toggle the panel
- `home/.config/herdr-app/layouts/tasks.json` (with `tasks.svg`) — a focused layout with only Tasks beside Artifacts; `Ctrl+Shift+L` cycles layouts

Both are clones: Herdr never updates clones, so after a Herdr update that changes `main` or the tab bar, duplicate the shipped file again (`layout.clone`, `mod.clone`), re-apply the two edits (the extra `panel-body` children; the two `panelButton` lines, the `workspace.panels` merge and the `nextCommand()` loop that serves the panel keys in the tab bar's `init`), and copy the result back into the repo.

## Panels and commands

Panels read the per-folder JSON lists that two commands write, both linked into `~/.local/bin` beside `oooconf`. Windows cannot execute the extensionless Python scripts directly, so `herdr-task.ps1`/`herdr-task.cmd` and `herdr-artifact.ps1`/`herdr-artifact.cmd` are linked beside them and run them with `python` (3.8+ on `PATH`): `herdr-task` and `herdr-artifact` work in PowerShell and cmd as usual. A panel writes only through the same compare-and-set: the Tasks header adds a task (the list and, for a folder the index has no slug for yet, `index.json`; `herdr-task add` through `hc exec` on a remote machine), a task's detail sets its status with a chip per state (`herdr-task set` remotely), offers **Mark done** when its agent finished, and **Delete** removes it (`herdr-task rm` remotely); an artifact's detail has **Copy path**, which copies the latest version's file to the clipboard, and **Delete** (`herdr-artifact rm` remotely; the local compare-and-set leaves that artifact's version files on disk).

- `herdr-task add "Split the importer" --note "Then run the tests" [--after <id>]`, `herdr-task list [--ready]`, `herdr-task set <id> doing|blocked|done`, `herdr-task show <id>`, `herdr-task rm <id>`, `herdr-task dep <id> <blocker>…`, `herdr-task undep <id> <blocker>…` — dependencies are ids a task waits for; `--ready` keeps only tasks whose dependencies are all done, the panel shows `after N` and a DEPENDS ON block, `spawn` refuses while any remains (override with `--force`), cycles and self-references are rejected, and removing a task drops it from everyone's list. The Done group header's **Clear done** deletes the whole group after one confirmation.
- `herdr-task spawn <id> -- <program> [args…]` — starts the task's agent as a Herdr terminal (`hc run --keep --bg`, labelled `herdr.task=<slug>#<id>`, status becomes `doing`); `--keep-open` leaves the terminal inspectable after the program exits (it runs `sh -c '<command>; exec "${SHELL:-sh}"'`), `--worktree [path]` makes `herdr/<id>` in its own worktree at `path` (default `<repo>-wt/<id>` beside the repo), spawns there and records `branch`, `worktree` and `worktree_tool` on the task, and `--dry-run` prints the worktree and hc commands instead of running them; `herdr-task label <id>` prints that label for a terminal you start yourself, `herdr-task bind <id> <terminal>` attaches one, `herdr-task kill <id>` ends it

`--worktree` goes through [worktrunk](https://github.com/max-sixty/worktrunk) whenever it is installed — `git-wt` on Windows (`wt` there is Windows Terminal), `wt` elsewhere — using `switch --create <branch> --path <path> --no-cd`; otherwise it falls back to `git worktree add -b`. The spawn does not tell the agent about worktrunk: the worktree is a real worktrunk one, so `wt list`/`git-wt list` shows it, `home/.config/ooodnakov/agents/common-text.md` already tells agents to use worktrunk for worktree work, and worktrunk's own agent plugin (`git-wt config plugins oh-my-pi install`) makes detection native.

- `herdr-artifact add "Weekly report" --from report.md` (or `--text "…"`), `herdr-artifact update <id> --from report.md`, `herdr-artifact list`, `herdr-artifact show <id>`, `herdr-artifact rm <id>`

Both act on `--folder …`, else the current git worktree, else the cwd, and print JSON with `--json`. Data lives under the store root — `$XDG_DATA_HOME/ooodnakov/herdr`, else `~/.local/share/ooodnakov/herdr` (`index.json` maps a folder to its slug; `tasks/` and `artifacts/` hold the lists; artifact versions keep their last 20 contents). On first use a command records the resolved root in `~/.config/ooodnakov/herdr-data`; the mods, which cannot read the environment, read that pointer first and fall back to `~/.local/share/ooodnakov/herdr`. `OODNAKOV_HERDR_DATA` overrides the root for a command without rewriting the pointer, so the mods keep reading the recorded location. Every write takes a lock and replaces the file atomically. A space on another machine reads that machine's lists over the herdr-core link, so the commands and mods must be linked there too (the normal `oooconf link apply` does it); the panels probe once per machine and show `herdr-task missing on <machine>` or `no store yet` instead of an empty list.

## Working with a task agent

A task can carry an agent: the Tasks panel finds it by its `herdr.task` label (or the address bound to the task), shows the terminal's live status and how many sub-agents it started (`parent`), and its detail rewrites the task's status with a chip per state (todo, doing, blocked, done). When the task has a terminal, the detail also has these actions:

- **Panel** — `layout.select` on the stack's `oo-agent` child (the `oo-agent-head` header above a `{ "agent": "focused" }` block), then `agent.focus`: the agent's live terminal fills the panel, keyboard included, while the Tasks list is one tab away. Terminals that report no status (a plain shell) can't sit in an agent block, so Panel falls back to `terminal.peek`.
- The header names the task whose agent is shown and its **← Tasks** chip selects the `oo-tasks` stack child again. The Tasks panel publishes the selection as shared `oo-tasks.selected` (`{ id, title }`) when a task opens or Panel runs, and clears it on back, delete, or a folder change; `oo-agent-head` only reads it.
- **Pane** — `terminal.keep`: the agent as an ordinary pane, e.g. beside the tasks list.
- **Stop** — `terminal.kill`.
- **Mark done** — only while a live agent reports `done` or `idle` on a `doing` task: the chip moves it to `done` (compare-and-set rewrite with a fresh `updated`). The panel never changes a status on its own, and shows no chip when there is no live agent.
- **Delete** — asks first, then removes the task; a running agent is left alone (Stop it separately).

Below the agent block, **OUTPUT** shows the tail of that terminal's screen — `hc read <terminal>`, last 120 lines, rendered as Markdown — read once when you open the task and again with the **Read** chip. It works after the agent exits too: a finished terminal stays readable until the core drops it, which is how a finished task shows what its agent ended with. Text is read-only and never written to the task file.

The spawned terminal is an ordinary herdr-core terminal, so `hc read/send/keys/wait <terminal>` work on it too. [`home/.config/ooodnakov/agents/skills/herdr-tasks/SKILL.md`](../home/.config/ooodnakov/agents/skills/herdr-tasks/SKILL.md) teaches agents to delegate this way.

Herdr watches `mods/` through the managed symlinks unevenly: after editing a mod in the repo, switch layouts (`Ctrl+Shift+L`) to start it fresh; restarting Herdr is not needed. `herdr-app check ~/.config/herdr-app/mods/oo-tasks` validates a mod before you rely on it.
