# Unitodo — Optional Dependencies Automation Migration

## Objective
Make `scripts/optional-deps.toml` the authoritative source for non-minimal dependency behavior so adding a new `[[deps]]` entry is sufficient for setup flows, completions, and related tooling.

## Working Rules for This Task
- Keep this file updated as the live execution log.
- Maintain explicit statuses: `TODO`, `IN_PROGRESS`, `DONE`, `BLOCKED`.
- At most one `IN_PROGRESS` item at a time.
- Update the **Execution Log** each time a task starts/completes.

## Status Legend
- `TODO` — not started
- `IN_PROGRESS` — currently being worked
- `DONE` — completed and verified
- `BLOCKED` — waiting on clarification/constraint

## Milestones

### M0 — Planning and baseline
- [DONE] Confirm current state of dependency parsing and setup/completion consumers.
- [DONE] Identify hardcoded dependency handling in shell + PowerShell setup flows.
- [DONE] Identify hardcoded dependency key lists in generated/static completions.

### M1 — Schema and parser contract
- [DONE] Define normalized dependency schema extensions in `scripts/optional-deps.toml` for generic install behavior.
- [DONE] Extend `scripts/read_optional_deps.py` to emit normalized records consumable by all installers/completion generators.
- [DONE] Add parser validation for required fields and per-platform applicability.

### M2 — Bash setup generic dispatcher
- [DONE] Refactor `scripts/setup.sh` dependency install path to use normalized metadata + strategy handlers.
- [DONE] Remove non-minimal per-key install branches that can be represented via metadata.
- [DONE] Keep explicit minimal flow behavior intact (hardcoded minimal orchestration allowed).

### M3 — PowerShell setup generic dispatcher
- [DONE] Refactor `scripts/setup.ps1` install and presence checks to consume normalized metadata.
- [DONE] Remove non-minimal per-key handling except explicitly approved edge cases.
- [DONE] Ensure Windows-specific module installs (`posh-git`, `PSFzf`) flow through declarative strategy metadata.

### M4 — Completions + command UX
- [DONE] Update `scripts/generate_oooconf_completions.py` to consume parser output instead of ad-hoc TOML parsing.
- [DONE] Regenerate tracked completion outputs and verify dependency keys are sourced through parser data.
- [DONE] Ensure dependency descriptions in completions come from TOML metadata.

### M5 — Validation and docs
- [DONE] Run lint/format/tests relevant to modified files.
- [DONE] Validate setup script syntax checks (`bash -n scripts/setup.sh`; PowerShell if available).
- [DONE] Update docs describing dependency contract and “add entry and it works” workflow.
- [DONE] Add/strengthen drift checks that prevent dependency key hardcoding outside approved locations.

### M6 — Finalization
- [DONE] Summarize changes and migration notes.
- [DONE] Ensure this `unitodo.md` reflects final status and decisions.
- [DONE] Stage, commit, and open PR.

## Current Focus
- **Now doing:** Migration tracker finalized.
- **Next:** Optional post-M6 hardening/cleanup as needed.

## Execution Log
- 2026-04-19: Initialized detailed task tracker and baseline milestones.
- 2026-04-19: Marked baseline discovery items in M0 as DONE based on repository inspection.
- 2026-04-19: Set active work item to M1.
- 2026-04-19: Implemented normalized parser output (`normalized-json`) and key uniqueness validation in `read_optional_deps.py`.
- 2026-04-19: Switched completion generation dependency ingestion to `read_optional_deps.load_deps()`.
- 2026-04-19: Regenerated tracked zsh/PowerShell completion files from parser-backed dependency catalog.
- 2026-04-20: Added dependency `handler` metadata support in parser + setup.sh dispatcher wiring.
- 2026-04-20: Started PowerShell dispatcher migration to `handler` metadata and wired setup.ps1 handler-aware routing.
- 2026-04-20: Restored `pnpm`/`rtk` dependency entries and corrected Bitwarden/rtk URL metadata in optional-deps catalog.
- 2026-04-20: Fixed setup.sh dry-run failure by defining default Neovim version variables used by pinned install logic.
- 2026-04-20: Added dot-source guard for setup.ps1 to support syntax-check imports without executing setup actions.
- 2026-04-20: Ran optional-deps test suite successfully after restoring pnpm/rtk metadata fields used by tests.
- 2026-04-20: Added parser/completion drift tests (`tests/test_optional_deps_drift.py`) and documented M5 validation workflow.
- 2026-04-20: Rechecked M1–M4 status; marked M1 and M3 complete, kept M2 in progress for remaining bash cleanup.
- 2026-04-20: Completed M2 bash dispatcher cleanup by switching handler dispatch to dynamic function lookup.
- 2026-04-20: Finalized M6 tracker closure with migration summary and remaining optional hardening notes.
- 2026-04-20: Added unix handler implementation drift assertion and wrapper functions for handler/function-name parity.
- 2026-04-20: Wired optional-deps parser/drift tests into GitHub CI workflows (shell + windows jobs).
- 2026-04-20: Added uv bootstrap step to CI shell/windows jobs to avoid missing-uv failures.

## Decisions / Notes
- Minimal install flow may remain explicitly orchestrated by request.
- All non-minimal dependencies should move to metadata-driven behavior.
- Completion sources should derive dependency keys from parser output, not duplicated lists.

## Risks / Open Questions
- Some platform-specific installers may still require curated strategy handlers (e.g., gallery modules).
- Need to decide whether strategy names live in TOML per-platform blocks or top-level dependency fields.


## Final Migration Notes

### What is complete
- `scripts/optional-deps.toml` is now the canonical dependency catalog for setup/completions metadata.
- `scripts/read_optional_deps.py` is the canonical parser used by downstream consumers.
- Completion generation consumes parser output and is covered by drift checks.
- Bash and PowerShell setup dispatchers consume declarative `handler` metadata for specialized installers.

### Remaining follow-up (optional hardening)
- Continue reducing bespoke installer code paths where a generic manager strategy can replace custom logic.
- Keep drift tests and shell smoke checks in CI or pre-merge validation.

## Main Ways This Was Achieved

1. **Canonical metadata source**
   - Consolidated dependency metadata in `scripts/optional-deps.toml` and treated it as the single source of truth.

2. **Shared parser contract**
   - Introduced a canonical parser (`scripts/read_optional_deps.py`) with normalization, validation, and machine-consumable outputs used by downstream tools.

3. **Metadata-driven installer dispatch**
   - Replaced scattered per-key installer wiring with declarative `handler` routing in setup flows (bash + PowerShell), while preserving explicit minimal-flow behavior.

4. **Generated artifact alignment**
   - Switched completions generation to parser-backed data and regenerated tracked completion artifacts from the same catalog.

5. **Drift prevention**
   - Added dedicated drift tests plus CI wiring so parser/completions/setup behavior are continuously checked for alignment.

6. **Validation + documentation discipline**
   - Ran shell/Python/PowerShell checks throughout and updated docs/tracker entries so changes remain reproducible and auditable.
