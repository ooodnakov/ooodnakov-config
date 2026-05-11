# Completions Refactor TODO

Track every task required to move `oooconf` completions from fixed-depth hardcoding to a recursive command-tree framework.

## Core tasks

- [x] Convert the CLI spec TOML to recursive command tables.
- [x] Add shared definitions and reference them by name instead of hardcoded command-name checks.
- [x] Replace fixed-depth CLI parser dataclasses with recursive dataclasses.
- [x] Add parser validation for aliases, shared value sets, completers, and shell-safe name collisions.
- [x] Refactor the Zsh generator around depth-agnostic tree walking.
- [x] Refactor the PowerShell generator around depth-agnostic path resolution.
- [x] Regenerate tracked completion outputs.
- [x] Add a thorough parser/generator test suite, including deep command trees.
- [x] Update docs for the recursive completion source of truth.
- [x] Run project validation checks.

## Issues found while iterating

- [x] Preserve existing option-value completions such as `--region`, `--shell`, `--method`, and `--backend` while moving positional value sets to `value_set`.
- [x] Keep dependency keys sourced from `scripts/optional-deps.toml` so optional dependency metadata remains single-source while still exposing `deps_keys` as a shared completion definition.

## Completion notes

- Implemented without adding a Jinja2 dependency; the generator now uses small renderer functions over a flattened recursive tree.
- `deps_keys` remains hydrated from `scripts/optional-deps.toml`, preserving the optional dependency catalog as the dependency metadata source of truth while allowing commands to reference it as a shared `value_set`.
- Existing drift tests were updated to assert the new recursive node output instead of the removed sub-subcommand metadata maps.
