# Codex task: harden and evolve `ooodnakov-config`

## Task type

Repository-wide engineering epic, to be delivered as small reviewable pull requests.

## Context

`ooodnakov-config` is already a capable cross-platform dotfiles system rather than
a collection of static files. It has a symlink manifest, Unix and PowerShell
installers, a recursive CLI specification, generated completions, dependency
metadata, local overrides, secrets rendering, desktop integrations, tests, and CI.

The next iteration should preserve those strengths while making installation safer,
the Unix and Windows implementations harder to drift apart, and the repository
easier to maintain. Treat `home/` as active configuration and `third_party/` as
reference-only material throughout this work.

## Review baseline

The following observations were made during a whole-repository review and should be
revalidated at the start of implementation:

| Area | Current strength | Improvement opportunity |
| --- | --- | --- |
| Bootstrap | Stable, thin entrypoints and dry-run support exist on Unix and Windows. | Installation is not represented as a single machine-readable plan and cannot be rolled back as one transaction. |
| Links | `scripts/link_manager.py` centralizes discovery, platform filtering, and local overrides. | Doctor and setup should consume one structured plan and report stale, shadowed, unsafe, or orphaned links consistently. |
| Dependencies | `scripts/optional-deps.toml` centralizes installers and `deps.lock.json` records pins. | Direct archive/script downloads are not uniformly integrity-verified; install methods remain duplicated in large Bash and PowerShell modules. |
| CLI | A recursive TOML spec drives help and completions. | Dispatch and behavior are still implemented separately in shell code, so spec, help, completion, and runtime behavior can drift. |
| Testing | Python tests, shell smoke tests, and a three-OS GitHub Actions matrix cover important paths. | Most install validation is dry-run based; there is no full isolated-HOME apply/idempotency/remove/restore test. |
| Repository hygiene | Local runtime and secret paths are mostly ignored. | Timestamped Niri and Noctalia backup files are tracked, while `scripts/fleet/node_modules/` is currently unignored. |
| Fleet automation | Scheduled issue planning and manual merge workflows exist. | `scripts/fleet/package.json` has ranged dependencies but no tracked Bun lockfile, tests, lint/typecheck scripts, or CI validation. |
| Security | Secrets have an explicit local-only model. | GitHub Actions use mutable major-version tags, remote installers are piped to shells in several paths, and no automated secret/dependency/action audit is present. |
| User experience | `doctor`, local preferences, unified colors, and generated completions are available. | There is no portable machine profile, structured diagnostic output, or safe export/import workflow for host choices. |
| Documentation | Architecture, reproducibility, troubleshooting, dependency, and CLI extension guides exist. | Generated and hand-written command documentation can diverge, and there is no support/version policy or end-to-end recovery guide. |

## Objective

Build a **transactional, inspectable, profile-aware configuration lifecycle** around
the existing `oooconf` command, then tighten supply-chain, CI, and repository hygiene.
The result must remain safe on Linux, Windows, and macOS and must not move host data
or secrets into tracked files.

The intended workflow is:

```text
oooconf plan --profile workstation --format json
oooconf apply --profile workstation
oooconf doctor --format json
oooconf snapshot export --output machine-profile.toml
oooconf rollback --last
```

Existing commands such as `install`, `dry-run`, `link`, `deps`, `update`, `delete`,
and `remove` must remain compatible. They may become adapters over the new lifecycle,
but must not silently change meaning.

## Required outcomes

### 1. Clean the baseline before adding features

1. Remove the tracked `*.backup-<timestamp>` files from active Niri and Noctalia
   trees after confirming the non-backup files contain the desired state.
2. Add narrowly scoped ignore rules for generated backup files and
   `scripts/fleet/node_modules/`.
3. Decide whether `deps.lock.json` is a generated, tracked artifact. It is currently
   both tracked and listed in `.gitignore`; keep it tracked and remove the ignore
   entry unless a documented migration intentionally changes the lock strategy.
4. Add a repository-hygiene test that rejects tracked runtime artifacts, timestamped
   backups, plaintext local secret files, dependency directories, and known editor
   state. Allow explicit fixtures through a small allowlist.
5. Check for redundant ignore entries and misspelled local paths, but do not broaden
   patterns in a way that could hide legitimate managed configuration.

### 2. Introduce a shared machine-readable operation plan

**Implemented:** the initial versioned planner, safety validation, `plan` command,
`dry-run` compatibility alias, and shared Unix/PowerShell link-plan consumption were
added in the follow-up implementation. Transaction execution remains intentionally
assigned to outcome 3.

Create a Python planning layer under `scripts/cli/` (or a better justified shared
location) that models all intended mutations before they occur.

At minimum, an operation must include:

- stable operation ID;
- kind (`mkdir`, `backup`, `link`, `unlink`, `download`, `install`, `render`, or
  `command`);
- platform and profile applicability;
- source and target where relevant;
- whether elevated privileges or network access are required;
- preconditions and expected postconditions;
- redacted human summary;
- rollback action or an explicit explanation of why rollback is unavailable.

Requirements:

- `oooconf plan` prints a readable plan by default and supports `--format json`.
- Plan JSON has a versioned schema and deterministic ordering.
- `oooconf dry-run` becomes a compatibility alias for the appropriate plan mode.
- Unix and PowerShell consume the same plan rather than independently discovering
  links and dependency choices.
- Plan generation has no side effects and never resolves or prints secret values.
- Refuse path traversal, targets outside approved roots, and unsafe replacement of a
  non-link unless the operation includes a backup.
- Preserve local link overrides and all current platform filters.

Do not rewrite every installer in Python in the first pull request. A plan operation
may initially call an existing shell implementation, provided its inputs and
postconditions are explicit and tested.

### 3. Make apply transactional and idempotent

**Implemented for the managed-link transaction boundary:** `apply`, exclusive
cross-process locking, atomic journals, automatic failure rollback, safe explicit
`rollback --last`, idempotent no-op behavior, incomplete-transaction doctor checks,
and output/journal redaction are now present. The existing full `install` workflow
delegates its managed-link phase to the transaction executor; package managers and
external plugin/tool state retain their explicitly unavailable rollback semantics.

Add `oooconf apply`, backed by a transaction journal in the existing XDG state
directory. Each run must record only non-secret metadata needed to diagnose or undo
the run.

Required behavior:

- Acquire a cross-process lock so two apply/update processes cannot mutate the same
  home concurrently.
- Validate the entire plan before the first mutation.
- Journal each completed operation atomically.
- On failure, report the failed operation and offer or automatically perform rollback
  according to an explicit, documented policy.
- `oooconf rollback --last` reverses reversible operations from the latest eligible
  transaction without deleting user-created files.
- A second identical apply reports no changes and creates no unnecessary backups.
- Interruptions leave a journal that `doctor` can detect and explain.
- Logs and JSON output redact values, tokens, session IDs, and sensitive command-line
  arguments.

Keep `oooconf install` as a stable alias or wrapper. Its existing optional-dependency
selection flags and non-interactive behavior must continue to work.

### 4. Add portable profiles without tracking host state

**Implemented:** tracked capability and profile catalogs, inheritance validation,
cycle and unknown-capability errors, platform skip reporting, dependency
recommendations, ignored machine-local defaults, explicit/environment/local
precedence, and no-profile backward compatibility now cover planning, transactional
apply, and the managed-link phase of install.

Add a tracked profile catalog, for example
`home/.config/ooodnakov/profiles/*.toml`, with conservative reusable bundles:

- `minimal`: shell, CLI wrappers, shared environment, and SSH include;
- `terminal`: minimal plus WezTerm, Neovim, Yazi, prompt, and CLI utilities;
- `workstation`: terminal plus platform-appropriate desktop integrations;
- `developer`: terminal plus developer and agent tooling.

Profile requirements:

- Profiles select capabilities, not absolute host paths or secrets.
- Profiles may extend another profile, but cycles and unknown capabilities fail with
  actionable errors.
- Platform-inapplicable capabilities are shown as skipped, not silently ignored.
- A machine-local default profile is stored under the ignored local configuration
  tree.
- Explicit command-line choices override the local default.
- Existing installs with no profile retain their current behavior.
- Profile schema, precedence, and examples are documented.

### 5. Add snapshots and structured diagnostics

**Implemented:** versioned text/JSON doctor and status reports now expose stable
check IDs, severity, remediation, and documented exit rules. Portable allowlisted
TOML snapshots support export, validation/preview, and transactional application;
secret-sentinel tests protect diagnostic output, snapshots, and journals.

Implement:

- `oooconf doctor --format text|json` with stable check IDs, severity, remediation,
  and exit-status rules;
- `oooconf status --format text|json` summarizing profile, managed links, dependency
  availability, incomplete transactions, and generated-artifact drift;
- `oooconf snapshot export`, which writes a portable TOML document containing only
  safe preferences and capability selections;
- `oooconf snapshot inspect FILE`, which validates and previews an import; and
- `oooconf snapshot apply FILE`, which routes through `plan` and `apply`.

Snapshots must exclude environment values, Bitwarden sessions, agent credentials,
SSH private material, machine paths, histories, logs, and cache contents. Add tests
that seed sentinel secrets and prove none appear in text output, JSON output,
journals, or snapshots.

### 6. Harden dependency and bootstrap integrity

**Implemented:** direct release archives now carry pinned SHA-256 metadata, are
downloaded to temporary files, verified before installation, and extracted through
path-traversal and unsafe-link guards. Mutable installer exceptions are explicit in
the generated lock, Actions are commit-SHA pinned with Dependabot updates, release
archives publish checksums, and CI runs secret and static security scans.

1. Extend dependency metadata and lock generation to support SHA-256 checksums for
   directly downloaded release artifacts on every supported architecture.
2. Download to a temporary file, verify, then extract or execute. Never pipe a newly
   downloaded script directly into a shell when a verified artifact or package
   manager route is available.
3. For upstreams that do not publish checksums, document the exception and pin the
   exact immutable version or commit. Make such exceptions visible in lock output.
4. Add archive extraction guards against absolute paths, `..` traversal, and unsafe
   symlinks.
5. Pin GitHub Actions to full commit SHAs with update comments, and automate update
   proposals through Dependabot or Renovate.
6. Add a CI secret scan and a lightweight static security check. Configure explicit
   exclusions for intentional examples rather than ignoring entire active trees.
7. Preserve the current bootstrap trust guidance and add checksum/signature guidance
   for release archives.

### 7. Bring Fleet automation under the same reproducibility standard

**Implemented:** Fleet dependencies and development tools are exactly pinned in a
tracked Bun lockfile and installed frozen in CI. Biome lint, TypeScript checks, and
offline unit tests cover issue filtering, prompt boundaries, branch names, ETag
caching, trusted PR selection, and merge eligibility. Workflows now have explicit
permissions and timeouts, while merge is preview-only unless manually opted in.

1. Generate and commit a Bun lockfile and use frozen-lockfile installation in CI.
2. Pin exact dependency versions unless there is a documented reason for a range.
3. Add `lint`, `typecheck`, and `test` scripts to `scripts/fleet/package.json`.
4. Unit-test issue selection, prompt construction, branch naming, cache behavior, and
   merge eligibility without contacting GitHub or Jules.
5. Add timeouts and least-privilege permissions to both Fleet workflows.
6. Ensure untrusted issue text is clearly delimited as data in prompts and cannot
   alter workflow policy.
7. Default merge automation to a preview and require explicit opt-in for mutation;
   retain branch protection as the final authority.

### 8. Expand cross-platform validation

**Implemented:** an isolated, network-disabled lifecycle test now covers plan,
snapshot templates, transactional apply/idempotency/backup, text and JSON doctor,
remove, delete/restore, and injected-failure rollback on Linux, macOS, and Windows.
CI also parses all maintained shell and PowerShell entrypoints, validates structured
files and generated artifacts, enforces a 50% Python coverage floor, and tests Python
3.12 plus 3.13.

Create isolated temporary-home integration tests that exercise this lifecycle:

1. render a plan;
2. apply managed links and local-file templates;
3. apply again and assert idempotency;
4. replace one target with a user file and assert backup behavior;
5. run doctor in text and JSON modes;
6. remove links without restore;
7. reapply, then delete with restore;
8. inject a mid-transaction failure and verify rollback/recovery.

Run the applicable test on Ubuntu, macOS, and Windows. Tests must never write to the
runner's real profile and must disable network installs. Also:

- Parse every maintained PowerShell script, not just the two entrypoints.
- Syntax-check and ShellCheck every maintained Bash script, including sourced
  modules and managed hooks/plugins where applicable.
- Validate tracked JSON, TOML, YAML, KDL, and Lua with suitable parsers or focused
  smoke tests.
- Check that generated completions, command lists, dependency locks, and generated
  docs have no diff.
- Add Python coverage reporting with a practical initial floor; ratchet it upward
  rather than choosing an unrealistic threshold.
- Test Python 3.12 as the pinned runtime and one newer supported Python version if
  the declared range remains open-ended.

### 9. Reduce future CLI drift

**Implemented:** the versioned recursive spec now declares stable handler IDs and
platforms, validates native dispatcher parity, and generates the dedicated CLI
reference without replacing hand-authored examples.

Extend the recursive CLI specification so it can validate, not merely describe, the
runtime surface.

- Give every command node a stable handler ID and declared platform support.
- Add a test that every leaf command has a handler on each declared platform.
- Add a test that dispatchers expose no undocumented public commands or options.
- Generate the command reference section of the README or a dedicated CLI reference
  from the same spec.
- Keep examples hand-authored and test them separately; generated documentation
  should not erase useful operational guidance.
- Add a schema-version field and a migration policy to the CLI spec.

This is validation and incremental consolidation, not a requirement to replace the
shell entrypoints or remove their platform-native UX.

### 10. Complete operational documentation

**Implemented:** lifecycle, profiles, integrity, Fleet, CLI contracts, tested versus
best-effort platform support, and guarded transaction-journal retention and cleanup
are documented in the operational and contributor guides listed below.

Update at least:

- `README.md` for the new lifecycle and profiles;
- `docs/architecture.md` for planning, transactions, journals, and handler mapping;
- `docs/reproducibility.md` for checksums, Fleet locking, and profile semantics;
- `docs/troubleshooting.md` for interrupted apply and rollback;
- `docs/dependency-lock.md` through its generator;
- `docs/cli-extension-guide.md` for handler IDs and schema changes;
- `docs/contributing.md` for the expanded validation matrix; and
- `AGENTS.md` if authoritative paths or completion requirements change.

Add a short support matrix that distinguishes tested, best-effort, and unsupported
OS/shell/architecture combinations. Document journal retention and safe cleanup.

## Suggested delivery plan

Use separate pull requests with independently useful outcomes:

1. **Hygiene and guardrails**: remove backups, fix ignores, add artifact tests, lock
   Fleet dependencies, and expand syntax/static validation.
2. **Plan model**: add schemas, deterministic JSON, safety validation, and adapt
   `dry-run` without changing install behavior.
3. **Transactional apply**: add locking, journal, idempotency, recovery, and rollback.
4. **Profiles**: add capability catalog, precedence, platform reporting, and docs.
5. **Diagnostics and snapshots**: add JSON contracts, redaction tests, and safe
   export/import.
6. **Supply-chain hardening**: checksum metadata, secure extraction, action pinning,
   and automated update/security checks.
7. **CLI convergence**: handler mapping, parity tests, and generated reference docs.

Every pull request must preserve existing public entrypoints and include migration
notes if it changes tracked schemas or generated files.

## Acceptance criteria

The epic is complete when all of the following are true:

- A clean clone has no tracked timestamped backups or unignored dependency/runtime
  directories.
- `oooconf plan --format json` is deterministic, versioned, side-effect free, and
  secret free on all three operating systems.
- `oooconf apply` is locked, journaled, idempotent, and recoverable; rollback is
  covered by integration tests.
- Existing `install`, `dry-run`, `deps`, `link`, `delete`, and `remove` workflows
  remain compatible.
- Profiles compose portable capabilities while local defaults remain ignored.
- Snapshot and diagnostic JSON formats are documented and protected by contract
  tests.
- Every direct binary/archive download is verified or has an explicit documented
  exception.
- Fleet installs from a frozen lockfile and passes lint, typecheck, and unit tests.
- CI validates generated artifacts and full isolated-HOME lifecycles on Linux,
  macOS, and Windows.
- Help, completions, handler mappings, and generated command documentation agree.
- No secret sentinel used in tests appears in output, plans, snapshots, logs, or
  journals.
- All relevant documentation is updated in the same pull request as behavior.

## Required validation commands

Run the existing checks throughout implementation, plus new commands introduced by
the work:

```bash
uv run ruff check --select I --fix
uv run ruff check
uv run ruff format
uv run pytest
bash tests/test_shell.sh
bash -n scripts/setup/setup.sh
bash -n scripts/setup/ooodnakov.sh
bash -n scripts/setup/delete.sh
bash -n scripts/setup/minimal-setup.sh
```

When available, also run ShellCheck across maintained shell files, parse all active
PowerShell files, run the Fleet lint/typecheck/test suite, and execute the isolated
integration test for the host platform. Regenerate locks, completions, and generated
documentation, then require a clean `git diff`.

## Constraints and non-goals

- Do not edit `third_party/` as active configuration.
- Do not commit secrets, resolved vault values, hostnames, internal URLs, or
  machine-specific absolute paths.
- Do not replace symlink-first management with copied config files.
- Do not remove Unix or PowerShell entrypoints in favor of a Python-only user
  experience.
- Do not require network access for plan, doctor, status, snapshot inspection, or
  tests.
- Do not automatically install every optional dependency merely because a profile
  references a capability; preserve preview and consent behavior.
- Do not make a broad formatter pass over vendored, snapshot, generated, or unrelated
  active configuration.
- Do not combine the entire epic into one unreviewable pull request.

## Codex execution notes

Before each implementation slice, inspect applicable `AGENTS.md` files, confirm the
working tree, and identify generated artifacts. Prefer tests first for path safety,
redaction, idempotency, interrupted transactions, profile cycles, and platform
filtering. Use temporary homes in tests and never exercise real package installation.
At the end of each slice, show the exact validations run, note environment-based
skips, commit with the repository's conventional style, and provide a focused pull
request description with migration and rollback notes.
