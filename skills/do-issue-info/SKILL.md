---
name: Get Issue Information
description: This skill should be used when the user asks to "get issue info", "fetch issue details", "show issue information", or wants to view comprehensive information about a Drupal.org issue, GitLab issue, or GitHub PR including comments, merge requests, and related issues.
version: 2.1.0
---

# Get Issue Information Skill

You are fetching and summarizing comprehensive information about a Drupal.org issue, GitLab issue, or GitHub PR, including its description, comments, merge requests, and optionally related issues.

## Workflow

### 0. Detect Issue Type

Determine whether this is a GitHub PR, GitLab issue, or Drupal.org issue:

**GitHub PR** — input matches:
```
https://github.com/<owner>/<repo>/pull/<number>
```
Examples:
- `https://github.com/acquia/drupal-recommended-project/pull/123`

Extract from URL:
- `owner` (e.g., `acquia`)
- `repo` (e.g., `drupal-recommended-project`)
- `pr_number` (e.g., `123`)

**GitLab issue** — input matches:
```
https://<host>/<namespace>/<project>/-/work_items/<iid>
https://<host>/<namespace>/<project>/-/issues/<iid>
```
Examples:
- `https://git.drupalcode.org/project/canvas/-/work_items/3591459`
- `https://git.drupalcode.org/project/canvas/-/issues/3591459`
- `https://gitlab.com/some-org/some-project/-/work_items/456`

Extract from URL:
- `host` (e.g., `git.drupalcode.org`)
- `project_path` (e.g., `project/canvas`) — URL-encode slashes as `%2F` for API calls
- `issue_iid` (e.g., `3591459`)

**Drupal.org issue** — input matches one of:
- a plain number (e.g., `3503194`)
- `https://www.drupal.org/project/<project>/issues/<number>` (`www.` optional)
- `https://drupal.org/i/<number>` (`www.` optional)

Extract the issue number.

**If no input provided:**
- Get current git branch: `git rev-parse --abbrev-ref HEAD`
- Extract issue number (digits at start before first hyphen) → treat as Drupal.org issue, **unless** the repo belongs to a project whose issue queue has migrated to GitLab work items (e.g. canvas — check the git remote host/project). In that case treat it as a GitLab work item: use `https://git.drupalcode.org/<project_path>/-/work_items/<number>` and `project#nid` refs for `drupalorg`.
- If no match, ask user for issue number or URL

### 1. Get Issue Number/URL and Flags

- Check if user requested related issues (e.g., "with related issues", "include related", or `--related` flag)
- GitLab and GitHub issues: ignore `--related` flag (not applicable)

### 2. Fetch Issue Data

#### GitHub path

Fetch PR metadata, review comments, and timeline comments:
```bash
gh pr view {{pr_url}} --json number,title,body,state,author,reviews,statusCheckRollup,commits,comments,headRefName,baseRefName,mergeStateStatus
```

Fetch inline review comments:
```bash
gh api repos/{{owner}}/{{repo}}/pulls/{{pr_number}}/comments
```

**If there are errors fetching PR details:** stop immediately and report the error.

#### GitLab path

For `git.drupalcode.org` hosts, fetch issue metadata and comments in one call:
```bash
drupalorg issue:show {{issue_url}} --format=llm --with-comments
```
For other hosts (e.g. `gitlab.com`), use `glab` as below — `drupalorg` only covers Drupal.org's GitLab instance.

Fetch issue metadata (other hosts only):
```bash
glab api --hostname {{host}} /projects/{{encoded_project_path}}/issues/{{issue_iid}}
```
(If that returns 404, try `/projects/{{encoded_project_path}}/work_items/{{issue_iid}}`)

Fetch comments/notes (other hosts only):
```bash
glab api --hostname {{host}} "/projects/{{encoded_project_path}}/issues/{{issue_iid}}/notes?sort=asc&per_page=100"
```

Find linked merge requests (all GitLab hosts, including `git.drupalcode.org`):
```bash
glab api --hostname {{host}} /projects/{{encoded_project_path}}/issues/{{issue_iid}}/related_merge_requests
```
Use this endpoint rather than `drupalorg mr:list` for MR discovery — `mr:list` resolves through a
GitLab "issue fork" and silently falls back to listing unrelated project-wide MRs when no fork
matches this issue, instead of erroring.

**If there are errors fetching issue details:** stop immediately and report the error.

#### Drupal.org path

```bash
do.php info {{issue_number}} --format=md --comments --mrs
```

**If there are any errors fetching the issue details:**
- Stop immediately
- Report the error to the user
- Do not proceed to next steps

### 3. Find Linked PRs/MRs (GitHub path)

From the `gh pr view` output, the PR itself is the code artifact. Extract:
- `headRefName` (branch with changes)
- `baseRefName` (target branch)
- `state` (open/merged/closed)
- `statusCheckRollup` (CI status)
- `reviews` (review decisions and comments)

### 4. Check for Related Issues (Drupal.org only)

Check if the user requested related issues information:

**If related issues were requested:**
1. After summarizing the main issue, examine the `field_issue_related_links` field in the response
2. For each related issue number found, run the command again:
   ```bash
   do.php info {{related_issue_number}} --format=md --comments --mrs
   ```
3. Append a "Related Issues Details" section at the end with the summaries of each related issue

**If related issues were NOT requested:**
- Skip fetching related issue details

### 5. Generate Issue Summary

Summarize the issue using the format below. When referencing other issues mentioned in the issue or comments, provide URLs to those issues.

For GitLab issues, use the full work_items URL as the issue URL (e.g., `https://git.drupalcode.org/project/canvas/-/work_items/3591459`).
For GitHub PRs, use the full PR URL (e.g., `https://github.com/owner/repo/pull/123`). The "Merge Requests" section becomes "Pull Request" with CI status from `statusCheckRollup` and review status from `reviews`.

```markdown
# Issue Summary

## Core Details
- **Issue**: [ISSUE_NUMBER] - [ISSUE_TITLE]
- **Status**: `[ISSUE_STATUS]` | **Priority**: `[ISSUE_PRIORITY]` | **Category**: `[ISSUE_CATEGORY]`
- **Tags**: `[ISSUE_TAGS]`
- **URL**: [ISSUE_URL]

## Timeline & Participants
- **Created by**: [ISSUE_AUTHOR] on [CREATION_DATE]
- **Last updated**: [LAST_UPDATED_DATE] by [LAST_UPDATED_AUTHOR]
- **Comments**: [NUMBER_OF_COMMENTS] comments from [LIST_OF_UNIQUE_USERS_WHO_COMMENTED]

## Related Issues
- [RELATED_ISSUE_1_URL]: [RELATED_ISSUE_1_TITLE]
- [RELATED_ISSUE_2_URL]: [RELATED_ISSUE_2_TITLE]

---

# Issue Description

[ISSUE_DESCRIPTION]

---

# Comments Summary

**Total Comments**: [NUMBER_OF_COMMENTS]

## Notable Comments

1. **[COMMENT_AUTHOR_1]** _([COMMENT_DATE_1])_:

   [COMMENT_SUMMARY_1]

2. **[COMMENT_AUTHOR_2]** _([COMMENT_DATE_2])_:

   [COMMENT_SUMMARY_2]

## Open Questions & Unresolved Issues

> Items that still need attention or decision:

- [UNRESOLVED_PROBLEM_1]
- [UNRESOLVED_PROBLEM_2]

---

# Merge Requests

**Total MRs**: [NUMBER_OF_MRS]

## Issue MR Details

### 1. [MR_1_TITLE]
- **URL**: [MR_1_URL]
- **Author**: [MR_1_AUTHOR] | **Date**: [MR_1_DATE]
- **Status**: `[MR_1_STATUS]`
- **Participants**: [USERNAME_1], [USERNAME_2], [USERNAME_3]
<!-- This value is returned directly as "mr_participants" -->

**Description**:
[MR_1_DESCRIPTION]

**Technical Details**:
[MR_1_TECH_DETAILS]

**Discussion Summary**:
[MR_1_COMMENTS_SUMMARY]

## Related MR Details
<!-- If there are any MRs mentioned in comments that were not returned under the "merge requests" of the command response, detail them here -->

---

# Related Issues Details
<!-- Only include this section if user requested related issues (Drupal.org only) -->
<!-- For each issue in field_issue_related_links, include the full summary following the same format as above -->

## Related Issue #[RELATED_ISSUE_NUMBER_1]

[Full summary of related issue following the same format as the main issue]
```

## Error Handling

- **Issue not found**: Verify issue number/URL and check connectivity
- **Fetch errors**: Report the error and stop processing
- **Related issue fetch fails**: Note the failure but continue with main issue summary
- **Branch has no issue number**: Ask user to provide issue number or URL

## Tips

- Preserve the source URL verbatim — never rewrite a `git.drupalcode.org/.../-/work_items/N` (or `/-/issues/N`) URL into `drupal.org/i/N` form, or vice versa. When fetched data provides a canonical `web_url`, output that.
- For classic Drupal.org issues, provide URLs in format: `https://drupal.org/i/{{issue_number}}`
- For GitLab issues/work items, use the full `/work_items/` URL
- For GitHub PRs, use the full `https://github.com/owner/repo/pull/N` URL
- Summarize comments focusing on key technical points and decisions
- Identify unresolved questions that still need attention
- List all participants who contributed to the discussion
- When user requests related issues (Drupal.org only), provide full context for each related issue
- If issue number not provided, try to extract from current git branch
