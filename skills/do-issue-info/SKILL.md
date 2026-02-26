---
name: Get Drupal.org Issue Information
description: This skill should be used when the user asks to "get issue info", "fetch issue details", "show issue information", or wants to view comprehensive information about a Drupal.org issue including comments, merge requests, and related issues.
version: 1.0.0
---

# Get Drupal.org Issue Information Skill

You are fetching and summarizing comprehensive information about a Drupal.org issue, including its description, comments, merge requests, and optionally related issues.

## Workflow

### 1. Get Issue Number and Flags

**If user provided issue number:**
- Use the provided issue number
- Check if user requested related issues (e.g., "with related issues", "include related", or `--related` flag)

**If no issue number provided:**
- Get current git branch: `git rev-parse --abbrev-ref HEAD`
- Extract issue number from branch name (e.g., "3571460-fix-bug" → 3571460)
- Look for pattern: digits at start of branch name before first hyphen
- If no issue number found, inform user and ask for issue number

### 2. Fetch Issue Data

Execute the `do.php info` command to get issue details:

```bash
do.php info {{issue_number}} --format=md --comments --mrs
```

**If there are any errors fetching the issue details:**
- Stop immediately
- Report the error to the user
- Do not proceed to next steps

### 3. Check for Related Issues

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

### 4. Generate Issue Summary

Summarize the issue using the format below. When referencing other issues mentioned in the issue or comments, provide URLs to those issues.

```markdown
# Issue Summary

## Core Details
- **Issue**: [ISSUE_NUMBER] - [ISSUE_TITLE]
- **Status**: `[ISSUE_STATUS]` | **Priority**: `[ISSUE_PRIORITY]` | **Category**: `[ISSUE_CATEGORY]`
- **Tags**: `[ISSUE_TAGS]`

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
<!-- Only include this section if user requested related issues -->
<!-- For each issue in field_issue_related_links, include the full summary following the same format as above -->

## Related Issue #[RELATED_ISSUE_NUMBER_1]

[Full summary of related issue following the same format as the main issue]
```

## Error Handling

- **Issue not found**: Verify issue number and check drupal.org connectivity
- **Fetch errors**: Report the error and stop processing
- **Related issue fetch fails**: Note the failure but continue with main issue summary
- **Branch has no issue number**: Ask user to provide issue number

## Tips

- Provide URLs for all issue references (format: `https://drupal.org/i/{{issue_number}}`)
- Summarize comments focusing on key technical points and decisions
- Identify unresolved questions that still need attention
- List all participants who contributed to the discussion
- When user requests related issues, provide full context for each related issue
- If issue number not provided, try to extract from current git branch

