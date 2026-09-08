# Snapshots and structured diagnostics

`oooconf doctor` and `oooconf status` share one versioned diagnostic model. Both
accept `--format text|json`; the JSON contract is
`scripts/cli/schemas/diagnostics-v1.schema.json`. Check IDs remain stable within a
schema version and every check includes status, severity, a message, and optional
remediation. `doctor` exits non-zero when any check has `error` status. `status`
reports the same facts but exits successfully when it can produce a report.

The current stable checks are:

- `profile.selection` — active portable profile, if any;
- `links.managed` — correct and total managed-link counts;
- `dependencies.available` — availability of profile recommendations;
- `transactions.incomplete` — interrupted or rollback-failed transactions; and
- `generated.drift` — tracked generated files that differ from the checkout.

Examples:

```console
oooconf doctor --format json --profile terminal
oooconf status --format text
```

## Portable snapshots

A snapshot is deliberately a small TOML allowlist, not a home-directory archive.
It records schema version 1, a validated profile, its capability names, and supported
UI/shell preference enums. It never reads or writes arbitrary environment values.
Consequently it excludes Bitwarden sessions, tokens, agent credentials, SSH keys,
absolute machine paths, histories, logs, and caches.

```console
oooconf snapshot export --profile terminal --output terminal.toml
oooconf snapshot inspect terminal.toml
oooconf snapshot inspect terminal.toml --format json
oooconf snapshot apply terminal.toml
```

Export requires an explicit or machine-local default profile. Inspection validates
the complete document before showing the selected capabilities, safe preferences,
and number of planned link operations. Unknown tables, preferences, enum values, or
a capability list that no longer matches the profile are rejected.

Apply validates the snapshot, builds the same side-effect-free link plan used by
`oooconf plan`, then invokes the transactional link executor. Safe preferences and
the machine-local default profile are written only after link application succeeds.
Normal transaction locking, journaling, automatic recovery, and rollback semantics
therefore continue to apply.
