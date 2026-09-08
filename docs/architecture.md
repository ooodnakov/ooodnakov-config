# Architecture

## Goals

This repo keeps the active tracked config small, reproducible, and portable across Linux, Windows, and macOS machines.

The tracked base config is intended to be safe to clone onto a new machine without carrying over secrets, host-specific paths, or runtime state.

## Layout

- `home/`: active tracked config that gets linked into the user profile
- `scripts/setup/`: Unix and PowerShell setup, delete, minimal setup, and CLI dispatcher scripts
- `scripts/setup/lib/`: sourced Bash and dot-sourced PowerShell modules that hold setup UI, optional dependency, installer, symlink, doctor, completion, summary, and `oooconf` helper logic while preserving the public entrypoint paths
- `scripts/cli/`: recursive CLI spec, completion generation, shared UI helpers, and agent-management tooling
- `scripts/generate/`: generated artifact and secrets rendering helpers
- `scripts/update/`: dependency pin audit/update workflows
- `scripts/fleet/`: TypeScript/Bun automation for multi-agent GitHub issue workflows
- `docs/`: reproducibility notes, architecture, CLI extension guidance, and import audit records
- `fonts/meslo/`: bundled prompt and terminal fonts used by the tracked defaults
- `third_party/`: reference-only upstream trees and local snapshots for audit or extraction work

Only `home/` is treated as managed active config. `third_party/` is kept for comparison and targeted imports, not as a live runtime tree.

Fleet automation is isolated from the setup lifecycle. Its exact dependencies and
tooling are captured by `scripts/fleet/package.json` and `scripts/fleet/bun.lock`.
Pure policy functions enforce issue selection, prompt-data boundaries, trusted branch
names, and merge eligibility without requiring GitHub or Jules in tests. The merge
workflow has separate read-only preview and explicitly selected mutation jobs;
repository branch protection remains authoritative.

Cross-platform lifecycle validation copies the repository into a temporary test
root and assigns every HOME, XDG, state, cache, and backup path beneath the test
directory. Network installs are explicitly disabled. A pytest-only transaction
failure hook exercises journal recovery without exposing a production CLI option.

## Install Model

The repo uses a symlink-first install model.

On Unix-like systems:

- `scripts/setup/ooodnakov.sh` is the dispatcher behind `home/.config/ooodnakov/bin/oooconf`
- `scripts/setup/setup.sh` links tracked files from `home/` into XDG and home-directory targets such as `~/.config/zsh`, `~/.config/wezterm`, `~/.config/yazi`, `~/.config/niri`, `~/.config/hypr`, `~/.config/pypr`, `~/.config/nvim`, `~/.config/task`, and `~/.config/ooodnakov`; it also links managed Taskwarrior config to legacy `~/.taskrc`
- `home/.config/ooodnakov/bin/oooconf` is linked into `~/.local/bin/oooconf` and `home/.config/ooodnakov/bin/o` into `~/.local/bin/o`
- replaced files are moved into timestamped backups under `~/.local/state/ooodnakov-config/backups/`
- logs are written to `~/.local/state/ooodnakov-config/logs/`

On Windows:

- `home/.config/ooodnakov/bin/oooconf.ps1` dispatches to `scripts/setup/ooodnakov.ps1` before and after install
- `scripts/setup/setup.ps1` creates the corresponding managed links
- `oooconf.ps1`/`oooconf.cmd` and short wrappers `o.ps1`/`o.cmd` are linked into `$HOME\.local\bin`
- backups and logs live under `$HOME\.local\state\ooodnakov-config\`

The install flow is intentionally idempotent. Re-running `oooconf install` should converge the machine back to the tracked state without duplicating managed artifacts.

The public setup and CLI scripts (`setup.sh`, `setup.ps1`, `ooodnakov.sh`, and `ooodnakov.ps1`) are kept as entrypoints that initialize repository paths, environment-derived flags, and top-level dispatch. Their implementation details are split into mirrored Bash/PowerShell modules under `scripts/setup/lib/`; these files are sourced or dot-sourced by the entrypoints and are not meant to run setup actions by themselves.

## CLI Surface

The versioned recursive contract in `scripts/cli/oooconf-cli-spec.toml` gives every
command node a stable handler ID and explicit platform support. Native Bash and
PowerShell entrypoints remain the runtime UX; contract tests compare their public
commands and global options with the spec and verify every declared leaf is
reachable. Completion files and `docs/cli-reference.md` are generated from the same
contract, while operational examples remain hand-authored.

There are two phase-1 entrypoints before install:

- Unix: `./home/.config/ooodnakov/bin/oooconf`
- Windows: `.\home\.config\ooodnakov\bin\oooconf.ps1`

After install, the unified `oooconf` command and short alias `o` are available from `~/.local/bin` on both platforms.

Primary commands:

- `install`: apply managed config and optional dependency installs
- `update`: fast-forward the repo and rerun install
- `deps`: interactive picker to install optional dependencies
- `completions`: regenerate tracked autogen zsh completions from the shared manifest and regenerate `oooconf` command completions
- `dry-run`: preview planned changes without mutating the system
- `doctor`: validate managed links and key tools
- `plan`: produce a deterministic, validated text or versioned JSON description of intended operations
- `apply`: transactionally apply managed links with locking and an atomic journal
- `rollback --last`: reverse the latest eligible managed-link transaction without overwriting user changes
- `delete` and `remove`: remove managed links, optionally restoring backups
- `lock`: regenerate dependency lock artifacts
- `update-pins`: audit pinned refs against upstream and optionally apply updates
- `secrets`: sync and manage local environment secrets using Bitwarden
- `env`: safely upsert machine-local variables in both shell env files, with optional Bitwarden upload
- `agents`: detect, sync, install, update, and configure shared AI coding agent policy/MCP/provider/skill settings
- `shell`: inspect and update local shell preference modes

## Dependency Model

Pinned third-party shell dependencies are installed outside the repo into user-local state instead of being committed into the active tracked tree.

Optional dependencies are defined in `scripts/optional-deps.toml` — a single TOML file that both Unix and PowerShell setup scripts read through `scripts/cli/read_optional_deps.py`. Each entry specifies per-platform install methods (apt, brew, choco, winget, cargo, PowerShell Gallery, GitHub release archives, npm/corepack, uv, curl, or custom handlers), so adding or removing an optional dep is a one-file change with platform install info ready for reuse.

Autogenerated third-party zsh completion definitions are centralized in `scripts/generate/tool-completions.toml` and generated by `scripts/generate/generate_tool_completions.py`, which is called by both setup implementations. The manifest uses argv arrays plus explicit filters for tools with noisy or non-fpath-safe output, so setup avoids shell-string parsing and stale local completion files are pruned.

The project-owned `oooconf` command completions are generated separately from the recursive command tree in `scripts/cli/oooconf-cli-spec.toml`, the tracked top-level command list in `scripts/cli/oooconf-commands.txt`, and dependency-key metadata in `scripts/optional-deps.toml` by `scripts/cli/generate_oooconf_completions.py`. Each TOML command node owns its description, options, values, shared `value_set` references, option-specific value sets, and nested `subcommands`, so adding a deeper command does not require depth-specific Python changes.

This gives two properties:

- the working config remains small and readable
- installs stay reproducible because setup pins upstream refs and regenerates `deps.lock.json`

Python scripts under `scripts/generate/`, `scripts/update/`, and `scripts/cli/` own generated docs, lockfile generation, completion generation, secrets rendering, and pin-update workflows so Unix and PowerShell entrypoints share the same implementation.

`scripts/cli/operation_plan.py` is the shared, side-effect-free planning boundary for
setup. It validates dependency keys and link preconditions, rejects duplicate or
out-of-root targets, and emits deterministic schema-versioned JSON. Each operation
declares its platform, source/target where applicable, privilege and network needs,
preconditions, postconditions, a redacted summary, and rollback capability. The Bash
and PowerShell setup implementations consume its internal validated link stream,
while `oooconf plan` exposes text and JSON formats to users and automation.
Public JSON contracts are retained under `scripts/cli/schemas/`; profile metadata is
introduced by `operation-plan-v2.schema.json`, while the version 1 schema remains
available to existing consumers. Incompatible changes require another schema version
rather than silently changing a published contract.

`scripts/cli/transaction_apply.py` executes the reversible link subset of the plan.
It validates the complete link plan before mutation, obtains a cross-process lock,
and atomically records each completed `mkdir`, `backup`, and `link` operation under
the XDG state directory. Failures trigger reverse-order rollback. Explicit rollback
removes only links still pointing to their recorded sources and restores a backup
only when its original target is absent; user-modified targets therefore stop
rollback and require manual recovery. Stale process locks are reclaimed only when
their recorded owner no longer exists.

Journals and transaction backups form one recovery record and have no automatic
age-based pruning. An incomplete journal may be the only reliable description of a
partial apply, while a completed journal identifies the backups needed by rollback.
Cleanup is therefore an explicit operator action after health checks: review and
remove that journal's backup paths before removing its terminal journal record.

The existing `install` command remains the full setup orchestrator and delegates its
managed-link phase to this transaction executor. Package installations, remote
checkout updates, completion generation, and plugin-manager changes retain their
declared unavailable or subsystem-specific rollback semantics.

Structured operational inspection lives in `scripts/cli/lifecycle_tool.py`. It is
the shared Bash/PowerShell implementation of `doctor`, `status`, and snapshot
export/import. Diagnostics use the versioned
`scripts/cli/schemas/diagnostics-v1.schema.json` contract. Snapshot fields and
preference values are explicit allowlists; applying a snapshot first validates and
builds a link plan, then delegates mutations to the transaction executor.

Portable capability profiles live under
`home/.config/ooodnakov/profiles/`. `capabilities.toml` maps portable capability
names to manifest link keys, dependency recommendations, and platform applicability;
the other TOML files define inheritance and capability composition. Profile
resolution is shared by planning and transactional apply. Explicit CLI selection
overrides `OOODNAKOV_PROFILE`, which overrides the ignored local `profile.toml`.
With no selection, the unfiltered historical install behavior is preserved.

## Local Override Precedence

Tracked portable environment belongs in:

- `home/.config/ooodnakov/env/common.sh`
- `home/.config/ooodnakov/env/common.ps1`

Machine-specific or secret values belong in ignored local files such as:

- `~/.config/ooodnakov/local/env.zsh`
- `~/.config/ooodnakov/local/env.ps1`
- `~/.config/ooodnakov/local/wezterm.lua`
- `~/.config/task/local/taskrc`
- `~/.ssh/config.local`

Tracked secret references belong in:

- `home/.config/ooodnakov/secrets/env.template`

Agent-wide shared policy and structured MCP/skills/provider data belongs in:

- `home/.config/ooodnakov/agents/config.json`
- `home/.config/ooodnakov/agents/common-text.md`
- `home/.config/ooodnakov/agents/common-data.json`

The design rule is simple: if a value is secret, internal, machine-only, or not safe across Linux, Windows, and macOS, it belongs in a local override instead of tracked base config.

`oooconf secrets login` configures the CLI against the intended Bitwarden-compatible server and supports both email/password and API key (`BW_CLIENTID`/`BW_CLIENTSECRET`) flows. `oooconf secrets unlock` prints shell code that exports `BW_SESSION` in the caller's shell, and `oooconf secrets sync` then resolves the tracked template into local plaintext env files for Zsh and PowerShell. The initial backend is `Bitwarden CLI` with `bw://item/<item-id>/...` references, which keeps the source of truth outside git while preserving reproducible local file locations.

## Runtime State

Runtime state is intentionally untracked.

Examples:

- zsh history under `~/.local/state/ooodnakov-config/zsh/`
- zsh completion dumps under `~/.cache/ooodnakov-config/zsh/`
- setup logs and backups under `~/.local/state/ooodnakov-config/`
- local shell preferences, rendered env files, agent local data, and WezTerm overrides under `~/.config/ooodnakov/local/`
- Taskwarrior sync credentials and private overrides under `~/.config/task/local/taskrc`

This prevents mutable local artifacts from leaking back into the reproducible source tree.

## Third-Party Reference Trees

`third_party/` exists for two reasons:

- upstream auditability
- selective extraction of ideas from larger external trees

Changes should normally land in `home/` or `scripts/`, not by replacing active config with reference snapshots.

## Validation

Current validation focuses on:

- shell syntax checks on Linux and macOS (`bash -n` on entrypoints and `scripts/setup/lib/*.sh`)
- `shellcheck` on Linux and macOS
- PowerShell parser validation on Windows
- lock artifact reproducibility checks on Linux and macOS
- cross-platform smoke checks for `oooconf install --dry-run`, `oooconf doctor` (expected failure on a fresh HOME), and `oooconf lock`

When bootstrap or setup behavior changes, these checks should be updated alongside the relevant docs so the repo stays reproducible and explainable.
