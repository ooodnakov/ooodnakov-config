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
import { cachePlugin } from "./cache-plugin.js";
import { getGitRepoInfo } from "./git.js";

/** Octokit with built-in ETag caching */
export const CachedOctokit = Octokit.plugin(cachePlugin) as typeof Octokit;

export interface IssueLike {
  pull_request?: unknown;
  locked?: boolean;
  draft?: boolean;
}

/** Apply deterministic safety filtering before issue text reaches a prompt. */
export function selectIssues<T extends IssueLike>(issues: T[], limit = 30): T[] {
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
    throw new Error("issue limit must be an integer from 1 to 100");
  }
  return issues.filter((issue) => !issue.pull_request && !issue.locked && !issue.draft).slice(0, limit);
}

/** Fetch open issues from the current repository */
export async function getIssues(options?: { perPage?: number; state?: "open" | "closed" | "all" }) {
  const repoInfo = await getGitRepoInfo();
  const octokit = new CachedOctokit({
    auth: process.env.GITHUB_TOKEN,
  });

  const { data } = await octokit.rest.issues.listForRepo({
    owner: repoInfo.owner,
    repo: repoInfo.repo,
    state: options?.state ?? "open",
    per_page: options?.perPage ?? 30,
  });

  return selectIssues(data, options?.perPage ?? 30);
}

export { cachePlugin } from "./cache-plugin.js";
