# TODO

This file tracks deliberate follow-up work for the repo. It is ordered by impact and maintenance value rather than by rough ideas.

## Done

- [x] Add an explicit open-source license
- [x] Document the repo architecture, symlink model, and local override boundaries
- [x] Make the README prefer the auditable clone-and-run path over leading with `curl | bash`
- [x] Clarify core prerequisites and the bootstrap trust model in the docs

## Next

- [ ] Expand CI to exercise install and doctor flows on Linux, Windows, and macOS
- [ ] Add stronger validation for managed config:
  - `zsh -n` for tracked zsh entrypoints
  - PowerShell analysis beyond parser-only validation
  - Neovim and WezTerm config smoke checks where practical
- [ ] Add a small troubleshooting guide covering bootstrap failures, missing tools, stale links, and local override conflicts
- [ ] Add pre-commit hooks for shell checks and lockfile reproducibility

## Reproducibility

- [ ] Document bare-machine prerequisites by platform in one concise table
- [ ] Tighten bootstrap safety further with a documented verify-first flow and clearer trust language
- [ ] Decide which dependencies are intentionally manual versus candidates for automated install
- [ ] Confirm the lock/update-pins flow is described consistently across README, reproducibility docs, and release notes

## Cross-Platform

- [ ] Audit feature parity between Unix `oooconf` and PowerShell `oooconf`
- [ ] Validate Windows path handling and symlink behavior on a fresh machine setup
- [ ] Add at least one macOS validation path before claiming active support there

## Maintainability

- [ ] Reduce long-term maintenance around `third_party/` snapshots, especially the large WezTerm reference tree
- [ ] Decide whether bundled fonts should stay in-repo or move to release assets/documented downloads
- [ ] Add a short contribution workflow for lock updates, docs changes, and config validation
- [ ] Review whether `AGENTS.md` should be referenced from contributor-facing docs

## Nice to Have

- [ ] Improve `oooconf --help` output with clearer command summaries and examples
- [ ] Consider shell completion for `oooconf`
- [ ] Add release notes guidance for `v*` tags and archive consumers
