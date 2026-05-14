# GitHub Issue Analyzer Prompt Template

**Source:** `analyze-issues.ts` from Google Jules Skills  
**License:** Apache License 2.0

## Overview

This TypeScript function generates a detailed prompt for analyzing GitHub repository issues and producing concrete implementation tasks. It orchestrates a four-phase analysis workflow.

### Function Signature

```typescript
export function analyzeIssuesPrompt({
  issuesMarkdown,
  repoFullName,
}: AnalyzeIssuesPromptOptions): string
```

---

## Four-Phase Analysis Workflow

### Phase 1: Investigate

**Goal:** Trace reported behavior to source code at the code level.

For each issue, analysts must provide:

1. **Exact code path** — Specific files, functions, and line ranges
2. **Mechanism explanation** — Why code produces the symptom, with annotated snippets
3. **Root cause category** — Bug, missing feature, architectural gap, error handling omission, race condition, or documentation gap

**Cross-reference requirement:** Group issues sharing the same root cause or code path.

---

### Phase 2: Architect

**Goal:** Design concrete solutions with implementation details.

For each root cause group, provide:

| Component | Requirement |
|-----------|-------------|
| **Proposed implementation** | Production-ready TypeScript code (not pseudocode) |
| **Integration points** | Before/after snippets showing exact wiring |
| **Edge cases and risks** | What could go wrong, assumptions being made |
| **Test scenarios** | Specific cases validating the fix |

---

### Phase 3: Plan

**Output files:**
- `.fleet/${YYYY_MM_DD}/issue_tasks.md`
- `.fleet/${YYYY_MM_DD}/issue_tasks.json`

#### Critical: Merge Conflict Avoidance

> **Rule:** No two tasks may modify the same file, including test files.

Tasks modifying the same source file must be **merged into one task**.

#### Coupling Analysis Checklist

Before finalizing tasks, check for implicitly coupled files:
- **Test files** exercising code from multiple tasks
- **Barrel exports** (`index.ts`) re-exporting from different tasks
- **Shared utilities** imported by files in different tasks

---

### Phase 4: Dispatch

After writing output files, execute:

```bash
bun run scripts/fleet/fleet-dispatch.ts
```

---

## Critical Rules

1. **Show work in code** — Every diagnosis references specific files/functions/lines; every solution includes implementation code
2. **Never split files across tasks** — Combine related changes into single tasks
3. **Task prompts must be self-contained** — Include code snippets, diffs, acceptance criteria (agents have repo access but no analysis context)
4. **Use exact file paths** — No path guessing
5. **Mark unaddressable issues** — Note reasoning and suggested owner
6. **Order by risk** — Lowest risk tasks first for early merges
7. **Diffs must be valid** — Reflect actual codebase, not approximations
8. **Include test files in ownership matrix** — Every source file's test file must be listed
9. **Test boundary enforcement** — Agents may ONLY modify listed files; must maintain backward compatibility for unowned tests

---

## Output Schema: `issue_tasks.json`

```json
{
  "repo": "${repoFullName}",
  "analyzed_at": "ISO-8601 timestamp",
  "root_causes": [
    {
      "id": "rc-kebab-id",
      "title": "Human readable title",
      "severity": "critical | high | medium | low",
      "issues": [19, 23],
      "files": ["src/polling.ts", "src/session.ts"],
      "description": "Brief explanation",
      "solution_summary": "Proposed fix approach"
    }
  ],
  "tasks": [
    {
      "id": "task-kebab-id",
      "title": "Task title",
      "root_cause": "rc-kebab-id",
      "issues": [19, 23],
      "files": ["src/polling.ts"],
      "new_files": ["src/retry.ts"],
      "test_files": ["tests/polling.test.ts"],
      "risk": "low | medium | high",
      "prompt": "Full agent prompt with implementation details, diffs, test scenarios, and acceptance criteria"
    }
  ],
  "unaddressable": [
    {
      "issue": 18,
      "reason": "Requires backend API change",
      "suggested_owner": "Backend team"
    }
  ],
  "file_ownership": {
    "src/polling.ts": "task-kebab-id"
  }
}
```

---

## Task Prompt Requirements

Each task's `prompt` field must include:

1. Exact files to modify and create
2. Exact test files to modify (and **only** these)
3. Root cause explanation with relevant code snippets
4. Proposed implementation with full code examples
5. Before/after diffs showing integration
6. Test scenarios with expected behavior
7. Acceptance criteria the PR must meet
8. **FILE BOUNDARY rule** — Agent may ONLY modify listed files

---

## Example Root Cause Structure

```typescript
export function analyzeIssuesPrompt({
  issuesMarkdown,
  repoFullName,
}: AnalyzeIssuesPromptOptions): string {
  return `You are analyzing issues for ${repoFullName}.

## Issues to Analyze

${issuesMarkdown}

---`;
}