# Portable Profiles

Profiles select reusable capabilities without tracking machine paths, credentials,
or other host state. They filter the managed links used by `plan`, `apply`, and the
link phase of `install`; they do not silently install every recommended dependency.

## Built-in Profiles

| Profile | Extends | Purpose |
| --- | --- | --- |
| `minimal` | — | Shell configuration, CLI wrappers, shared environment, PowerShell, and prompt configuration |
| `terminal` | `minimal` | WezTerm, Neovim, Yazi, terminal status tools, and productivity configuration |
| `workstation` | `terminal` | The terminal profile plus desktop integrations applicable to the current platform |
| `developer` | `terminal` | The terminal profile plus developer utilities and agent configuration |

Definitions live in `home/.config/ooodnakov/profiles/*.toml`. Profiles contain only
capability names. `capabilities.toml` maps those names to managed link keys,
recommended optional dependencies, and optional platform applicability. Both the
catalog and individual profiles declare `version = 1`; incompatible format changes
must introduce a new supported schema version.

## Selection and Precedence

Selection uses this precedence, from highest to lowest:

1. an explicit `--profile NAME` option;
2. the `OOODNAKOV_PROFILE` environment variable;
3. `home/.config/ooodnakov/local/profile.toml`; and
4. no profile, which preserves the historical behavior of managing every link
   applicable to the current platform.

Examples:

```bash
oooconf plan --profile workstation
oooconf plan --profile workstation --format json
oooconf apply --profile terminal
oooconf install --profile developer
```

To configure a machine-local default, copy the tracked example:

```bash
cp ~/.config/ooodnakov/local/profile.toml.example \
  ~/.config/ooodnakov/local/profile.toml
```

The destination is ignored by git. It must contain only a profile choice:

```toml
profile = "terminal"
```

## Platform Behavior

A profile may include platform-specific capabilities. The planner reports
inapplicable capabilities as `skipped_capabilities` in JSON and as `[skip]` entries
in text output. It never silently converts a Linux desktop capability into a Windows
or macOS equivalent.

Recommended dependencies are emitted as `recommended_dependencies`. They are
informational: dependency installation continues to use the existing explicit or
interactive consent flow. This prevents selecting a profile from unexpectedly
installing packages.

## Extending Profiles

Add a capability to `capabilities.toml`, then reference its name from a profile:

```toml
version = 1

[profile]
name = "example"
extends = "terminal"
capabilities = ["developer"]
```

Profile inheritance is single-parent and deterministic. Cycles, unknown parents,
unknown capabilities, invalid platform names, malformed arrays, duplicate managed
targets, and capability link keys unavailable on the selected platform fail before
filesystem mutation.
