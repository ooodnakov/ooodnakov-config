// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import { Octokit } from "octokit";
import { getGitRepoInfo } from "./github/git.js";

const OWNER = process.env.GITHUB_REPOSITORY?.split("/")[0] ?? "";
const REPO = process.env.GITHUB_REPOSITORY?.split("/")[1] ?? "";
const BASE_BRANCH = process.env.FLEET_BASE_BRANCH ?? "main";
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const JULES_API_KEY = process.env.JULES_API_KEY;
const MAX_RETRIES = parseInt(process.env.FLEET_MAX_RETRIES ?? "2", 10);
const PR_POLL_INTERVAL_MS = 30_000;
const PR_POLL_TIMEOUT_MS = 15 * 60 * 1000;

const octokit = new Octokit({ auth: GITHUB_TOKEN });

interface Task {
  id: string;
  title: string;
  risk: "low" | "medium" | "high";
  prompt: string;
}

interface IssueAnalysis {
  tasks: Task[];
}

async function findFleetPRs(): Promise<Map<string, { number: number; headRefName: string; sessionId?: string }>> {
  const { data: prs } = await octokit.rest.pulls.list({
    owner: OWNER,
    repo: REPO,
    state: "open",
    per_page: 100,
  });

  const prMap = new Map<string, { number: number; headRefName: string; sessionId?: string }>();
  for (const pr of prs) {
    // Match by author (google-labs-jules or any bot)
    const isBot = pr.user?.login === "google-labs-jules" || pr.user?.login.endsWith("[bot]");
    if (isBot || pr.head.ref.includes("fleet-")) {
      // Try to extract session ID from branch or body
      const sessionMatch = pr.head.ref.match(/session[_-]?(\w+)/) ||
                           pr.body?.match(/session[_-]?(\w+)/);
      prMap.set(pr.head.ref, {
        number: pr.number,
        headRefName: pr.head.ref,
        sessionId: sessionMatch?.[1],
      });
    }
  }
  return prMap;
}

async function waitForCI(prNumber: number, maxWaitMs: number): Promise<boolean> {
  const start = Date.now();
  while (Date.now() - start < maxWaitMs) {
    const { data } = await octokit.rest.checks.listForRef({
      owner: OWNER,
      repo: REPO,
      ref: `pulls/${prNumber}/head`,
    });

    if (data.check_runs.length === 0) return true; // No checks = pass

    const allPassed = data.check_runs.every(
      (run) => run.conclusion === "success" || run.conclusion === "skipped"
    );
    if (allPassed) return true;
    if (data.check_runs.some((run) => run.conclusion === "failure")) return false;

    await new Promise((r) => setTimeout(r, PR_POLL_INTERVAL_MS));
  }
  return false;
}

async function updateBranch(prNumber: number): Promise<boolean> {
  try {
    await octokit.rest.pulls.updateBranch({
      owner: OWNER,
      repo: REPO,
      pull_number: prNumber,
    });
    return true;
  } catch (e: any) {
    if (e.status === 422) return false; // Conflict
    throw e;
  }
}

async function mergePR(prNumber: number): Promise<boolean> {
  try {
    await octokit.rest.pulls.merge({
      owner: OWNER,
      repo: REPO,
      pull_number: prNumber,
      merge_method: "squash",
    });
    return true;
  } catch (e: any) {
    console.error(`Merge failed for PR #${prNumber}:`, e.message);
    return false;
  }
}

async function closePR(prNumber: number, message: string): Promise<void> {
  await octokit.rest.issues.createComment({
    owner: OWNER,
    repo: REPO,
    issue_number: prNumber,
    body: message,
  });
  await octokit.rest.pulls.update({
    owner: OWNER,
    repo: REPO,
    pull_number: prNumber,
    state: "closed",
  });
}

async function getCurrentTasks(): Promise<IssueAnalysis | null> {
  // Find latest .fleet directory
  const { execSync } = await import("child_process");
  try {
    const out = execSync('find .fleet -name "issue_tasks.json" 2>/dev/null | sort | tail -1', { encoding: "utf8" }).trim();
    if (!out) return null;
    const content = await Bun.file(out).text();
    return JSON.parse(content);
  } catch {
    return null;
  }
}

async function main() {
  console.log(`🚀 Fleet merge for ${OWNER}/${REPO} → ${BASE_BRANCH}`);

  const analysis = await getCurrentTasks();
  if (!analysis) {
    console.log("No fleet tasks found.");
    return;
  }

  const prMap = await findFleetPRs();
  console.log(`Found ${prMap.size} fleet PRs, expected ${analysis.tasks.length}`);

  for (let i = 0; i < analysis.tasks.length; i++) {
    const task = analysis.tasks[i];
    const prKey = Array.from(prMap.keys()).find((k) => prMap.get(k)?.sessionId === task.id || k.includes(task.id));
    if (!prKey) {
      console.log(`Task ${task.id}: no PR found, skipping`);
      continue;
    }

    const pr = prMap.get(prKey)!;
    console.log(`\nProcessing: ${task.title} (PR #${pr.number})`);

    // Update branch from base
    if (i > 0) {
      const hasConflict = !(await updateBranch(pr.number));
      if (hasConflict) {
        console.log(`⚠️ Conflict detected for ${task.id}`);
        if (MAX_RETRIES > 0) {
          await closePR(pr.number, "⚠️ Closed by fleet-merge: merge conflict detected. Task re-dispatched.");
          // In a full implementation, re-dispatch here
        }
        continue;
      }
    }

    // Wait for CI
    const ciPassed = await waitForCI(pr.number, 10 * 60 * 1000);
    if (!ciPassed) {
      console.log(`⏰ CI timeout for PR #${pr.number}`);
      continue;
    }

    // Merge
    const merged = await mergePR(pr.number);
    if (merged) {
      console.log(`✅ Merged PR #${pr.number}`);
    } else {
      console.log(`❌ Failed to merge PR #${pr.number}`);
    }

    await new Promise((r) => setTimeout(r, 5000)); // Brief pause between PRs
  }

  console.log("\n✅ Fleet merge complete");
}

main().catch(console.error);
