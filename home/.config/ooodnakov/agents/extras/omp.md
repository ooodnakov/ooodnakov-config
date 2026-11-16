### Oh My Pi (omp)

- **Optimize useful progress per round trip, not raw call count.**
  Keep ordinary single operations direct; use eval when aggregation or
  persistent state provides a concrete benefit.

- **Batch independent operations.**
  Use supported parallel calls for independent reads and searches.
  Awaited loops are sequential. Bound concurrency; keep dependent reads,
  writes, and checks ordered.

- **Delegate substantial independent slices only.**
  Submit one task call with tasks[]. Give each slice explicit ownership,
  requirements, and acceptance criteria. Continue local work; wait only
  when genuinely blocked.

- **Prefer native tools for files and code intelligence.**
  Use bash for execution and pipelines. Set bash.cwd rather than
  repeatedly prefixing local commands with cd; never assume cwd persists.

- **Recover from evidence.**
  Follow the currently mounted tool schemas. After failure, inspect the
  error and correct its cause; do not repeat unchanged failing calls.

- **Respect asynchronous execution.**
  Consume automatic completion messages. Do not poll or rerun commands
  merely to retrieve their output.

- **Reuse derived state without trusting stale snapshots.**
  Keep parsed data in the eval kernel. Refresh after mutations or
  external changes; repeat setup only after kernel loss.

- **Control output deliberately.**
  Return evidence needed for the next decision, not entire intermediate
  structures. Preserve relevant errors and diagnostics.
