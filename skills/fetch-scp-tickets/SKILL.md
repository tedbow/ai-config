---
name: fetch-scp-tickets
description: Fetch Jira tickets from a configured board for the current sprint. Use when triaging daily work, checking sprint tickets, or getting an overview of assigned issues.
user_invocable: true
---

# Fetch SCP Tickets

Fetch tickets from the configured Jira board for the current user's active sprint.

## Step 1: Query Jira

Use the following JQL to get tickets from the board's active sprint:

```
mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql
cloudId: {{cloud_id}}
jql: project = {{project}} AND sprint in openSprints() ORDER BY priority DESC, updated DESC
fields: ["summary", "description", "status", "issuetype", "priority", "created", "updated", "labels", "assignee"]
maxResults: 25
```

**Note**: Removed `assignee = currentUser()` to get all sprint tickets - filter by assignee when displaying.

## Step 2: Extract Drupal.org Links (Two-Phase Approach)

### Phase A: Extract from descriptions (no extra API calls)

For each ticket, extract Drupal.org issue references from the **description field**:

1. **URL patterns to match**:
   - `https://www.drupal.org/project/*/issues/NNNNNNN` → extract issue number
   - `https://drupal.org/i/NNNNNNN` → extract issue number
   - Jira smartlinks containing drupal.org URLs

2. **Summary patterns**:
   - `#NNNNNNN:` at start of summary (common pattern)

### Phase B: Fetch remote links for tickets missing a link

For tickets where **no Drupal.org link was found** in Phase A:

```
mcp__plugin_atlassian_atlassian__getJiraIssueRemoteIssueLinks
cloudId: {{cloud_id}}
issueIdOrKey: {{JIRA_KEY}}
```

**Guidelines for Phase B**:
- Only call for tickets that actually need it (no link found)
- Prioritize tickets assigned to the current user
- If you hit rate limits, stop and proceed with what you have
- Maximum 5-10 remote link calls per triage session

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

## Rate Limit Handling

If you receive a rate limit error (429 or similar):

1. **Do NOT retry immediately** - this will make it worse
2. **Present what you have** - show any tickets already fetched
3. **Offer alternatives**:
   - Provide the board URL for manual access
   - Ask user if they want to provide specific ticket keys
   - Suggest trying again in 5-10 minutes

**Example response when rate limited:**
```markdown
The Jira API is rate limited. Here's what I found before the limit:

[any tickets already fetched]

**Options:**
1. View your board directly: {{board_url}}
2. Provide specific ticket keys (e.g., SCP-123, SCP-456) for me to look up
3. Try again in a few minutes
```
