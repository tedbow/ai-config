---
name: fetch-scp-tickets
description: Fetch Jira tickets from a configured board for the current sprint. Use when triaging daily work, checking sprint tickets, or getting an overview of assigned issues. Requires fetch-scp-tickets.local.md configuration.
user_invocable: true
---

# Fetch SCP Tickets

Fetch tickets from the configured Jira board for the current user's active sprint.

## Configuration

**Read configuration from `fetch-scp-tickets.local.md` in this skill's directory.**

The `.local.md` file should contain YAML frontmatter with:
- `cloud_id`: Your Atlassian Cloud ID
- `project`: Your Jira project key
- `board_id`: Your Jira board ID
- `board_url`: Direct URL to your Jira board (for error handling fallback)

## Step 1: Query Jira

Use the following JQL to get tickets from the board's active sprint:

```
mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql
cloudId: {{cloud_id}}
jql: project = {{project}} AND sprint in openSprints() AND assignee = currentUser() ORDER BY priority DESC, updated DESC
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
   cloudId: {{cloud_id}}
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
jql: project = {{project}} AND sprint in openSprints() ORDER BY assignee, priority DESC
```

## Error Handling

- If no tickets found: Report "No tickets in current sprint"
- If API error: Provide direct link to board using `{{board_url}}` from configuration
