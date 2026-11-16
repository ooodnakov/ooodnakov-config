# Fleet automation

Fleet is optional Bun-based automation for turning GitHub issues into isolated Jules
tasks and reviewing the resulting pull requests. Its source lives under
`scripts/fleet/`; it is not part of normal dotfiles installation.

## Reproducible development

Dependencies and developer tools use exact versions in `package.json` and the
tracked `bun.lock`. Install and validate them with:

```console
cd scripts/fleet
bun install --frozen-lockfile
bun run lint
bun run typecheck
bun run test
```

Tests use pure inputs and in-memory state. They do not contact GitHub or Jules.

## Trust boundaries

Issue bodies and generated task prompts are untrusted data. Prompt builders escape
their closing delimiters and explicitly state that issue text cannot change policy,
expand file ownership, disable validation, or request credentials. Only PRs owned by
the Jules bot with Fleet branch prefixes are considered merge candidates.

The dispatch workflow has read-only repository and issue permissions. The merge
workflow receives only the write permissions needed to update, comment on, and merge
pull requests. Both workflows have job timeouts and install from the frozen lockfile.

## Preview and mutation

The Fleet merge workflow defaults to preview. A preview lists the PRs it would
validate but does not update branches, close PRs, add comments, or merge anything.
To enable mutation, manually dispatch **Fleet Merge** with the `apply` input checked;
this sets `FLEET_MERGE_APPLY=true` for that run.

Even in apply mode, a PR must be non-draft, confirmed mergeable, target the requested
base branch, and have at least one completed successful, skipped, or neutral check.
Repository branch protection remains the final authority and can reject the merge.

## SSH fleet sync

`oooconf fleet sync` pulls this repository's latest changes on SSH fleet hosts. It
runs locally and drives each host over `ssh`; the remote side needs only `git`,
`sh`, and `oooconf`. Changes merged through Fleet above reach the fleet this way.

```console
oooconf fleet sync [HOST...] [--all] [--repo-path PATH] [--branch NAME] [--jobs N]
                   [--resolve] [--no-push] [--format text|json] [--dry-run]
```

- `HOST...`: SSH config aliases. Without hosts and without `--all` it is a usage error.
- `--all`: every host alias from `~/.ssh/config`, `~/.ssh/config.local`, and recursively
  `Include`d files. Comments are stripped, wildcard and negated patterns are skipped, and
  missing files are not an error. Aliases are deduped twice: repeated aliases and aliases
  whose configured `HostName`/`Port` pair matches an earlier host collapse to the first
  occurrence, and each dropped alias is reported as `skipped` with reason
  `duplicate of <alias>`.
- `--repo-path PATH`: remote checkout path. Defaults to the host's
  `oooconf --print-repo-root`, then to `~/src/ooodnakov-config`.
- `--branch NAME`: remote branch. Defaults to the branch's upstream minus `origin/`,
  then to `main`.
- `--jobs N`: hosts synced in parallel (default 4).
- `--resolve`: after the fan-out, spawn one `omp` agent to repair hosts left `conflict`
  or `failed` but reachable (see Two-phase fixing below).
- `--no-push`: never push commits that exist only on the host.
- `--format text|json`: human summary or a versioned JSON document
  (`schema_version`, per-host results including `reachable`, `fix`, and `skip_reason`, and
  ok/conflict/failed/dry-run/skipped counts).
- `--dry-run`: inspect only; reports repo, branch, dirty state, and ahead/behind without
  fetching, stashing, pulling, pushing, or re-linking.

### Preflight and host dedupe

Host aliases are deduped before any `ssh` call: two aliases whose configured
`HostName`/`Port` pair is identical reach the same machine, so only the first is synced
and the rest are reported as `skipped` with reason `duplicate of <alias>`.

Each remaining host then gets exactly one preflight `ssh` call before any git command.
It reports the remote hostname, the login user, and whether the checkout exists
(`--repo-path` when given, otherwise `~/src/ooodnakov-config`). Outcomes:

- `ssh` fails: the host is `failed` with error `ssh <host>: ...`.
- the login user is `root`: `skipped` with reason `root user`.
- the checkout is missing: `skipped` with reason `<path> not found`.
- the remote hostname is this machine's short hostname (case-insensitive, domain
  stripped) or `localhost`/`127.0.0.1`: `skipped` with reason `local machine`.

Skipped hosts issue no git or `oooconf` command at all and count as success for exit
codes. Preflight failures are ordinary failures, not skips.

### Per-host pipeline

1. Preflight: verify `ssh`, the login user, the checkout path, and machine identity.
2. Resolve the repo path and verify it is a git checkout.
3. Resolve the branch and record whether the tree is dirty.
4. Stash local work (`git stash push -u`).
5. `git fetch --prune origin <branch>` then `git pull --rebase origin <branch>`.
6. On a pull failure, treat unmerged paths and an in-progress rebase as a conflict;
   any other failure marks the host failed. The per-host pass never spawns an agent:
   with `--resolve` it still returns `conflict`, and repair happens afterwards.
7. Restore the stash after a clean rebase, with the same conflict handling.
8. Recompute ahead/behind; push commits that only exist on the host unless `--no-push`.
9. Run `oooconf update --no-deps` in the checkout so managed links are re-applied.

Every remote git command runs with `GIT_TERMINAL_PROMPT=0`, so a missing credential
fails the host instead of hanging the run.

### Two-phase fixing

With `--resolve` and without `--dry-run`, the fan-out finishes first and `apply_fixes`
then repairs the hosts that are still broken. A host needs fixing when its status is
`conflict`, or `failed` while reachable (a host whose `ssh` preflight failed is left
alone).

- Exactly one host needs fixing: `omp -p <prompt>` runs on that host.
- Two or more hosts need fixing: one local `omp -p <prompt>` runs in this repo and is
  told to drive each host over `ssh`.

Either prompt embeds a status block per host: host, status, branch, repo, the
dirty/stashed/behind/ahead/pushed/linked flags, the error, the conflicting paths, and the
last 8 log lines. After the agent exits, each repaired host is completed here: the stash
is restored (`git stash pop`), commits that exist only on that host are pushed unless
`--no-push`, and `oooconf update --no-deps` re-applies managed links. A stash pop that
conflicts again leaves the host `conflict` with no push and no update. Results carry
`fix=remote-agent` or `fix=local-agent` (also in JSON).

### Safety model

- A host skipped by dedupe or preflight never runs git or `oooconf`; `--dry-run`,
  `--no-push`, and `--resolve` do not change that.
- A conflict without `--resolve` leaves the stash in place and performs no push and no
  link refresh; inspect the host, fix it, and re-run.
- An `omp` agent runs only when `--resolve` is passed, and only after the fan-out: the
  per-host pass itself never spawns one. One pending host is repaired by `omp -p` on that
  host; two or more are repaired by one local `omp -p` that `ssh`es into each of them.
  Both prompts embed a per-host status block (host, status, branch, repo,
  dirty/stashed/behind/ahead/pushed/linked, error, conflicts, last 8 log lines) and ask
  the agent to resolve conflicts, stage the files, finish the rebase or stash restore,
  push commits that only exist on the host, leave a clean tree, never `reset --hard`, and
  never force-push. Completion then restores the stash, pushes host-only commits, and
  runs `oooconf update --no-deps`; a failing stash pop leaves the host `conflict` with no
  push and no update. The result records `fix=remote-agent` or `fix=local-agent`.
- Pushing is limited to commits already made on that host; the sync itself never
  rewrites history.
- `--dry-run` is read-only, and `--no-push` keeps the host's commits local.

### Exit codes

- `0`: every host is `ok`, `dry-run`, or `skipped`.
- `2`: at least one host is `conflict`.
- `1`: any host `failed`, or there was nothing to do.

The text summary ends with `ok`, `conflict`, `failed`, `skipped`, and `dry-run` counts;
JSON entries carry the same `status` values plus `skip_reason`.

### Examples

```console
oooconf fleet sync --all --format json
oooconf fleet sync orange site
oooconf fleet sync --all --resolve
```
