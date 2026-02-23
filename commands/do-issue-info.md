Gets the basic information for a drupal.org issue: $ARGUMENTS

1. Get the issue details by running this command:
    ```
    do.php info [ISSUE_NUMBER] --format=md --comments --mrs
    ```
2. If there are any errors fetching the issue details, stop and report the error.
3. Check if `--related` flag was passed in $ARGUMENTS:
   - If YES: After summarizing the main issue, check the `field_issue_related_links` field in the response
   - For each related issue number found, run the command again WITHOUT the `--related` flag:
     ```
     do.php info [RELATED_ISSUE_NUMBER] --format=md --comments --mrs
     ```
   - Append a "Related Issues Details" section at the end with the summaries of each related issue
   - If NO: Skip this step
4. Summarize the issue, using the format below. When referencing other issues mentioned in the issue or comments provide urls those issues.

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

## Related MR details
<!-- If there are any MRs mentioned in comments that were not returned under the "merge requests" of the command response detail them here -->

---

# Related Issues Details
<!-- Only include this section if --related flag was passed -->
<!-- For each issue in field_issue_related_links, include the full summary following the same format as above -->

## Related Issue #[RELATED_ISSUE_NUMBER_1]

[Full summary of related issue following the same format as the main issue]

## Related Issue #[RELATED_ISSUE_NUMBER_2]

[Full summary of related issue following the same format as the main issue]
