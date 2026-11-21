### Antigravity (agy)

- **Search narrowly before reading.**
  Use `rg -l`, `rg -n`, or `fd` to pinpoint exact files and line numbers before
  calling `read_file`. Read only files on the direct call chain or slated for
  edits; avoid speculative bulk parallel `read_file` calls (at most 3 uncertain
  files per turn; batching confirmed small files you must inspect is fine).

- **Slice large files instead of reading them whole.**
  For files over ~350 lines, locate target symbols with `rg -n` first and pass
  `StartLine`/`EndLine` to read focused ranges (~150-250 lines per call) unless
  you are refactoring or reviewing the entire file.

- **Bound raw shell output at the source.**
  Because search runs through `run_command`, prefer compact tool-native limits
  (`rg -l`, `rg -n -m 20`, `fd --max-results 50`, `git diff --stat` followed by
  path-scoped `git diff -- <path>`) over unbounded dumps that hit truncation and
  force overflow log re-reads. Never truncate `git diff` during pre-commit or
  final verification review.

- **Preserve prefix-cache locality before spawning subagents.**
  Keep focused codebase exploration in the main session; subagents cold-start
  without the main prefix cache and often duplicate file reads. Delegate
  exploration to `research` (or another subagent) only for broad, independent
  scans whose raw output should stay out of a long-lived main session.

- **Respect asynchronous completion.**
  Wait for automatic completion notifications from background tasks and
  subagents; do not poll in a loop or rerun commands merely to check status.
