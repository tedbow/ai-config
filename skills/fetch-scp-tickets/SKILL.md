---
name: fetch-scp-tickets
description: Fetch Jira tickets from the SCP board (5081) for the current sprint. Use when triaging daily work, checking sprint tickets, or getting an overview of assigned SCP issues.
user_invocable: true
---

# Fetch SCP Tickets

Fetch tickets from the SCP board (DAT CMS Growth & Innovation) for the current user's active sprint.

## Constants

- **Cloud ID**: `e064d7a1-07ac-4eb9-ace5-67fc64ac5826`
- **Project**: SCP
- **Board**: 5081

## Step 1: Query Jira

Use the following JQL to get tickets from the SCP board's active sprint:

```
mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql
cloudId: e064d7a1-07ac-4eb9-ace5-67fc64ac5826
jql: project = SCP AND sprint in openSprints() AND assignee = currentUser() ORDER BY priority DESC, updated DESC
fields: ["summary", "description", "status", "issuetype", "priority", "created", "updated", "labels"]
maxResults: 50
```

## Step 2: Extract Drupal.org Links

For each ticket, check for Drupal.org issue references in:

1. **Summary/Description**: Look for patterns like:
   - `#NNNNNNN` (issue number)
   - `https://www.drupal.org/project/*/issues/NNNNNNN`
   - `https://drupal.org/i/NNNNNNN`

2. **Remote Links**: Fetch web links for each ticket:
   ```
   mcp__plugin_atlassian_atlassian__getJiraIssueRemoteIssueLinks
   cloudId: e064d7a1-07ac-4eb9-ace5-67fc64ac5826
   issueIdOrKey: {{JIRA_KEY}}
   ```

## Step 3: Format Output

Present tickets in a triage-friendly format:

```markdown
## SCP Sprint Tickets

**Sprint**: [sprint name if available]
**Total**: X tickets assigned

### By Status

#### Needs Action (In Progress / Ready for Dev)
| Ticket | Priority | Summary | Drupal.org |
|--------|----------|---------|------------|
| SCP-XXX | High | [summary] | #NNNNNNN |

#### In Review
| Ticket | Priority | Summary | Drupal.org |
|--------|----------|---------|------------|
| SCP-YYY | Medium | [summary] | #NNNNNNN |

#### Blocked / Waiting
| Ticket | Priority | Summary | Drupal.org |
|--------|----------|---------|------------|
| SCP-ZZZ | Low | [summary] | - |

#### Other
| Ticket | Status | Priority | Summary |
|--------|--------|----------|---------|
| SCP-AAA | Refining | TBD | [summary] |
```

## Status Groupings

Group tickets by these status categories:

| Category | Statuses |
|----------|----------|
| Needs Action | In Progress, Ready for Dev, Needs work |
| In Review | In Review, Ready for Review, Needs review, RTBC |
| Blocked | Blocked, On Hold |
| Done | Closed, Done, Ready to release |
| Other | Refining/Sizing, Open, TBD |

## Optional: Include All Sprint Tickets

If the user asks for "all sprint tickets" (not just assigned), use:

```
jql: project = SCP AND sprint in openSprints() ORDER BY assignee, priority DESC
```

## Error Handling

- If no tickets found: Report "No SCP tickets in current sprint"
- If API error: Provide direct link to board: https://acquia.atlassian.net/jira/software/c/projects/SCP/boards/5081
