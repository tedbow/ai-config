---
name: Issue Review
description: This skill should be used when the user asks to "review a drupal.org issue", "review an issue", "review a gitlab issue", "review a github pr", "check issue status", "analyze a merge request", or wants to examine a Drupal.org issue, GitLab issue, or GitHub PR's code changes, discussion, and CI status.
version: 2.1.0
---

# Issue Review Skill

You are reviewing a Drupal.org issue, GitLab issue, or GitHub PR to provide comprehensive feedback on code changes, discussion context, and CI status.

## Workflow

### 1. Get Issue Identifier

First, determine the issue source:

**GitHub PR** — input matches:
```
https://github.com/<owner>/<repo>/pull/<number>
```
Extract: `owner`, `repo`, `pr_number`.

**GitLab issue** — input matches:
```
https://<host>/<namespace>/<project>/-/work_items/<iid>
```
Examples:
- `https://git.drupalcode.org/project/canvas/-/work_items/3591459`
- `https://gitlab.com/some-org/some-project/-/work_items/456`

Extract: `host`, `project_path` (e.g., `project/canvas`), `issue_iid`.

**Drupal.org issue** — plain number or `https://drupal.org/...` URL.

**If nothing provided:**
- Get current git branch: `git rev-parse --abbrev-ref HEAD`
- Extract issue number (digits before first hyphen) → treat as Drupal.org issue
- If no match, ask user for issue number or URL

### 2. Fetch Issue Data

#### GitHub path

```bash
gh pr view {{pr_url}} --json number,title,body,state,author,reviews,statusCheckRollup,commits,comments,headRefName,baseRefName,mergeStateStatus
```

Fetch inline review comments:
```bash
gh api repos/{{owner}}/{{repo}}/pulls/{{pr_number}}/comments
```

Extract:
- title, state, description/body
- `headRefName` (source branch), `baseRefName` (target branch)
- `author`
- Reviews with reviewers, decisions (APPROVED/CHANGES_REQUESTED/COMMENTED), and comment text
- `statusCheckRollup` (CI status per check)
- Comments thread for discussion context

#### GitLab path

```bash
glab api --hostname {{host}} /projects/{{encoded_project_path}}/issues/{{issue_iid}}
```
(If 404, try `/projects/{{encoded_project_path}}/work_items/{{issue_iid}}`)

```bash
glab api --hostname {{host}} "/projects/{{encoded_project_path}}/issues/{{issue_iid}}/notes?sort=asc&per_page=100"
```

Extract:
- title, state/status, description
- Comments with authors, dates, key discussion points
- Open questions and concerns

#### Drupal.org path

```bash
do.php info {{issue_number}} --format=md --comments --mrs
```

Parse the markdown output to extract:
- **Issue metadata**: title, status, category, component, version
- **Issue summary**: description and problem statement
- **Discussion**: comments with authors, dates, and key points
- **Related issues**: dependencies, duplicates, follow-ups
- **Open questions**: unresolved discussion points
- **Concerns raised**: issues mentioned in comments

### 3. Fetch MR/PR Data

#### GitHub path

The PR itself is the code artifact. From the `gh pr view` output:
- `headRefName` = source branch
- `baseRefName` = target branch
- `state` = open/merged/closed
- `mergeStateStatus` = mergeable state (CLEAN, DIRTY, BLOCKED, etc.)

No separate MR fetch needed — proceed to Step 4.

#### GitLab path

```bash
glab api --hostname {{host}} /projects/{{encoded_project_path}}/issues/{{issue_iid}}/related_merge_requests
```

From the result, find the open MR. Then fetch full MR details:
```bash
glab api --hostname {{host}} /projects/{{encoded_project_path}}/merge_requests/{{mr_iid}}
```

Extract from MR:
- `web_url`, `diff_url` (or construct as `web_url + "/diffs"`)
- `title`, `description`, `state`
- `source_branch`, `target_branch`
- `has_conflicts`, `blocking_discussions_resolved`
- `author`

#### Drupal.org path

```bash
do.php gitlab:mrinfo {{issue_number}}
```

Parse the JSON output to extract:
- `web_url`: URL to the MR page
- `diff_web_url`: URL to view the diff
- `title`: MR title
- `description`: MR description
- `state`: opened/merged/closed
- `source_branch`: branch with changes
- `target_branch`: usually the main branch
- `has_conflicts`: boolean for merge conflicts
- `blocking_discussions_resolved`: boolean for unresolved discussions
- `author`: MR author information

**If no open MRs found (either path):**
- Inform user that there are no open merge requests
- Provide issue URL
- Stop here

**Save the target branch** from MR data for later use (e.g., `1.x`, `2.x`, `11.x`).

### 4. Checkout the MR/PR Branch Locally

#### GitHub path

```bash
gh pr checkout {{pr_url}}
```

#### GitLab path

From within the project repo directory:
```bash
GITLAB_HOST={{host}} glab mr checkout {{mr_iid}}
```

#### Drupal.org path

```bash
do.php mr-checkout {{issue_number}}
```

This command will:
- Update the local target branch from origin (or pull if currently on it)
- Add the fork as a remote if needed
- Fetch and checkout the MR branch

### 5. Analyze Code Changes

Analyze the merge request using local git and files:

**Get the diff against target branch:**
```bash
git diff origin/{{target_branch}}...HEAD
```

**For a summary of changed files:**
```bash
git diff origin/{{target_branch}}...HEAD --stat
```

**Read specific changed files** using the Read tool for full context.

**Analyze the changes:**
- Provide a **high-level summary** focusing on architecture and approach
- Identify the **nature of changes**: new feature, bug fix, refactoring, API change
- Review **architectural patterns**: design decisions, code structure, API design
- Assess **test coverage**: are tests added/updated appropriately?
- Check **documentation**: inline comments, docblocks, README updates
- Note **potential concerns**: security, performance, maintainability, BC breaks

**Run local code quality checks (optional but recommended):**
```bash
# PHP CodeSniffer
../../../vendor/bin/phpcs -s . --standard=phpcs.xml --basepath=.

# PHPStan
../../../vendor/bin/phpstan analyze --memory-limit=256M --configuration=phpstan.neon .
```

**Use reference materials:**
- Consult `${CLAUDE_PLUGIN_ROOT}/skills/review-issue/references/review-guidelines.md` for Drupal-specific review criteria
- Check `${CLAUDE_PLUGIN_ROOT}/skills/review-issue/references/common-issues.md` for common pitfalls

**Keep analysis concise:**
- Focus on high-level architectural concerns
- Don't provide line-by-line commentary unless critical
- User can drill deeper into specific files if needed

### 6. Check CI Status

#### GitHub path

CI status is already available from `statusCheckRollup` in the `gh pr view` output. Extract:
- Overall rollup state (SUCCESS/FAILURE/PENDING)
- Per-check name and conclusion

No browser automation needed.

#### GitLab path

Since pipeline data is not available via the GitLab API for git.drupalcode.org, use browser automation to check CI status:

**Steps:**
1. Open a browser and navigate to the MR page: `{{mr_data.web_url}}`
2. Get a snapshot/state of the page
3. Parse the page for CI indicators:
   - Look for pipeline status: "Pipeline #XXX passed", "failed", "running"
   - Check for CI badges or pipeline indicators
   - Note any failed jobs or error messages
   - Identify if tests are still running

**Handle failures gracefully:**
- If browser automation fails or page structure is unclear, fall back to manual check
- Provide URL: `{{mr_data.web_url}}/-/pipelines`
- Note: "Unable to automatically check CI status, please verify manually"

#### Drupal.org path

Same browser automation approach as GitLab path above.

### 7. Generate Review Summary

Display a comprehensive review summary in the terminal:

```markdown
## Issue Review: {{issue_identifier}}

### Issue Details
- **Title**: {{title}}
- **Status**: {{status}} | **Category**: {{category}}
- **URL**: {{issue_url}}

### Merge Request
- **URL**: {{mr_url}}
- **State**: {{state}}
- **Source → Target**: {{source_branch}} → {{target_branch}}
- **Has Conflicts**: {{has_conflicts}}
- **Blocking Discussions Resolved**: {{blocking_discussions_resolved}}

### Code Changes Summary
{{high-level analysis of diff}}

**Nature of changes**: {{feature/bugfix/refactoring/etc}}
**Architecture**: {{design patterns, approach taken}}
**Test coverage**: {{assessment of tests}}
**Documentation**: {{assessment of docs}}

### Discussion Summary
{{key points from comments}}

**Open questions**:
- {{list of unresolved questions}}

**Concerns raised**:
- {{list of concerns from discussion}}

### GitLab CI Status
{{pipeline status from Playwright check}}

- Pipeline: {{status}}
- Failed jobs: {{if any}}
- {{or "Check manually at {{mr_url}}/-/pipelines"}}

### Review Findings

**Overall Assessment**: {{summary judgment}}

**Strengths**:
- {{positive aspects}}

**Concerns**:
- {{issues to address}}

**Suggestions**:
- {{recommendations for improvement}}
```

### 8. Offer to Post Response

Use AskUserQuestion to ask if user wants to post their review. Options depend on issue type:

**GitHub PR:**
```
options:
  - label: "Post comment to GitHub PR"
    description: "Add review comment to the GitHub pull request"
  - label: "Approve PR"
    description: "Submit an approving review"
  - label: "Request changes"
    description: "Submit review requesting changes"
  - label: "No, just show summary"
    description: "Don't post, just display the review summary"
```

**GitLab issue:**
```
options:
  - label: "Post to GitLab MR"
    description: "Add review comment to the GitLab merge request"
  - label: "No, just show summary"
    description: "Don't post, just display the review summary"
```

**Drupal.org issue:**
```
options:
  - label: "Post to Drupal.org issue"
    description: "Add review comment to the Drupal.org issue queue"
  - label: "Post to GitLab MR"
    description: "Add review comment to the GitLab merge request"
  - label: "Post to both"
    description: "Add review comments to both Drupal.org and GitLab"
  - label: "No, just show summary"
    description: "Don't post, just display the review summary"
```

If user selects "No, just show summary", stop here.

### 9. Post Response (if requested)

#### Post to GitHub PR

```bash
# Comment only:
gh pr comment {{pr_url}} --body "{{review_text}}"

# Or with review decision:
gh pr review {{pr_url}} --comment --body "{{review_text}}"
gh pr review {{pr_url}} --approve --body "{{review_text}}"
gh pr review {{pr_url}} --request-changes --body "{{review_text}}"
```

#### Post to Drupal.org (Drupal.org issues only)

Use browser automation to navigate and post comment:

1. **Navigate to issue**: Open `https://drupal.org/i/{{issue_number}}`
2. **Get page snapshot** to find the comment form
3. **Fill and submit comment**:
   - Click to focus the comment textarea
   - Type the review text
   - Click to submit the comment
   - Handle login if needed (prompt user to login first)

#### Post to GitLab MR

Use browser automation to navigate and post MR comment:

1. **Navigate to MR**: Open `{{mr_data.web_url}}`
2. **Get page snapshot** to find the comment form
3. **Fill and submit comment**:
   - Click to focus the comment textarea
   - Type the review text
   - Click to submit the comment
   - Handle authentication if needed

#### Confirmation

After posting, confirm success:
- "Review posted to GitHub PR: {{pr_url}}" (GitHub)
- "Review posted to Drupal.org: https://drupal.org/i/{{issue_number}}" (Drupal.org)
- "Review posted to GitLab: {{mr_data.web_url}}" (GitLab)
- Note any errors encountered

## Error Handling

- **Branch has no issue number**: Ask user to provide issue number, GitLab URL, or GitHub PR URL
- **Issue not found**: Verify issue number/URL and check connectivity
- **No open MRs**: Inform user, provide issue URL, stop workflow (Drupal.org/GitLab; N/A for GitHub — PR is the artifact)
- **Browser automation fails**: Fall back to manual URLs, continue with review
- **Cannot post comment**: Provide instructions for manual posting

## Tips

- Keep code analysis high-level and architectural
- Reference Drupal best practices from bundled guidelines
- Be constructive in feedback - suggest improvements
- Note both strengths and concerns
- Consider backwards compatibility implications
- Check for Drupal coding standards adherence
- Verify API changes are documented
