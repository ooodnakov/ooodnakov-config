### Oh My Pi (omp)

- **Batch independent tool calls per turn.** Emit every read, search, grep, and status check that does not depend on another result in one assistant message. A turn with one call where three are independent is wasted latency, not caution.
- **Collapse repeated `tool.*` calls into one `eval` cell.** When the same call runs over a list of files, repos, or URLs, loop inside one Python or JS cell instead of emitting one tool call per item:

  ```py
  for path in paths:
      print(await tool.read({"path": path}))
  ```

- **Keep derived state in the kernel.** The eval runtime persists across cells: parse once, filter in Python or JS, and print only the lines that change the next decision instead of re-reading the same input.
- **Reserve discrete tool calls for decisions.** One call per real branch (edit, write, ask) is correct; one call per loop iteration is not.
- **Fan out homogeneous subagent work from eval.** Loop over the work specs and collect `await tool.task(...)` handles, then wait once for the batch rather than round-tripping per subagent.
