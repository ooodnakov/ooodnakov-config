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
- `--resolve`: let an `omp` agent repair conflicts (see below).
- `--no-push`: never push commits that exist only on the host.
- `--format text|json`: human summary or a versioned JSON document
  (`schema_version`, per-host results including `skip_reason`, and
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
   any other failure marks the host failed.
7. Restore the stash after a clean rebase, with the same conflict handling.
8. Recompute ahead/behind; push commits that only exist on the host unless `--no-push`.
9. Run `oooconf update --no-deps` in the checkout so managed links are re-applied.

Every remote git command runs with `GIT_TERMINAL_PROMPT=0`, so a missing credential
fails the host instead of hanging the run.

### Safety model

- A host skipped by dedupe or preflight never runs git or `oooconf`; `--dry-run`,
  `--no-push`, and `--resolve` do not change that.
- A conflict without `--resolve` leaves the stash in place and performs no push and no
  link refresh; inspect the host, fix it, and re-run.
- An `omp` agent runs only when `--resolve` is passed. Its prompt asks it to resolve
  the listed conflicts, stage the files, finish the rebase or stash restore, leave a
  clean tree, never `reset --hard`, and never push. The host is re-checked afterwards;
  remaining unmerged paths still count as a conflict.
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
