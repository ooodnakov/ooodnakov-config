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
