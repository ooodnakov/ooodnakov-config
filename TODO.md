# TODO

This file tracks deliberate follow-up work for the repo. It is ordered by impact and maintenance value rather than by rough ideas.

## Done

- [x] Add an explicit open-source license
- [x] Document the repo architecture, symlink model, and local override boundaries
- [x] Make the README prefer the auditable clone-and-run path over leading with `curl | bash`
- [x] Clarify core prerequisites and the bootstrap trust model in the docs
- [x] Add shell completion for `oooconf` (PowerShell completions added)
- [x] Implement `zsh -n` syntax validation for tracked zsh scripts in CI
- [x] Implement PowerShell parser validation for `.ps1` files in CI

## Next

- [ ] Expand CI to exercise install and doctor flows on Linux, Windows, and macOS
- [ ] Add Neovim and WezTerm config smoke checks where practical
- [x] Add a small troubleshooting guide covering bootstrap failures, missing tools, stale links, and local override conflicts
- [ ] Add pre-commit hooks for shell checks and lockfile reproducibility

## Reproducibility

- [ ] Document bare-machine prerequisites by platform in one concise table
- [ ] Formalize bootstrap verify-first flow with explicit step-by-step instructions
- [x] Add a decision matrix for dependencies: intentionally manual vs automated install
- [x] Verify lock/update-pins flow is described consistently across README and reproducibility docs

## Cross-Platform

- [ ] Audit feature parity between Unix `oooconf` and PowerShell `oooconf`:
  - Unix supports `bootstrap`, `delete`, `remove` — PowerShell does not
  - Document or close the gap
- [ ] Validate Windows path handling and symlink behavior on a fresh machine setup
- [ ] Add at least one macOS validation path before claiming active support there (currently deferred — no macOS-specific code exists)

## Maintainability

- [ ] Reduce long-term maintenance around `third_party/` snapshots, especially the large WezTerm reference tree
- [ ] Decide whether bundled fonts should stay in-repo or move to release assets/documented downloads
- [ ] Add a short contribution workflow for lock updates, docs changes, and config validation
- [ ] Review whether `AGENTS.md` should be referenced from contributor-facing docs

## Nice to Have

- [ ] Improve `oooconf --help` output with clearer command summaries and examples (currently functional but lacks examples beyond secrets)
- [ ] Expand `oooconf shell` into a small interactive-shell control surface:
  - add `doctor`
  - add `completion-cache clear`
  - add `editor [nvim|vim|hx|code|status]`
  - add `prompt [default|minimal|off|status]`
  - add toggles for `direnv`, `zoxide`, `fzf-tab`, `zsh-autosuggestions`, and `zsh-autocomplete`
- [ ] Add release notes guidance for `v*` tags and archive consumers
