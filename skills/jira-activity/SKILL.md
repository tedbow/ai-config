---
name: jira-activity
description: Show recent Jira activity for the current user — assignee changes I made, status/column moves I made, tickets assigned to me, issues I created. Default 24h; pass a timeframe like 4h or 2d.
version: 1.0.0
user_invocable: true
args:
  - name: timeframe
    description: How far back to look. Format Nh or Nd. Examples: 4h, 2h, 1d, 2d. Defaults to 24h if omitted.
    required: false
---

# Jira Activity Skill

Show the current user's recent Jira activity, grouped by action type.

## Step 1: Check prerequisites

Verify the script exists:

```bash
ls ~/projects/ai-config/jira/fetch-activity.sh
```

If missing, tell the user:
```
Run ./build.sh from ~/projects/ai-config/ first to generate fetch-activity.sh.
```
Then stop.

Verify `JIRA_API_TOKEN` is set:

```bash
echo "${JIRA_API_TOKEN:+set}"
```

If output is not `set`, tell the user:
```
JIRA_API_TOKEN is required. Export it before running:
  export JIRA_API_TOKEN=your_token_here
```
Then stop.

## Step 2: Run the activity script

Use the timeframe argument if provided, otherwise default to `24h`:

```bash
~/projects/ai-config/jira/fetch-activity.sh {{timeframe or "24h"}}
```

## Step 3: Present output

The script outputs markdown directly. Present it as-is.

If the output contains only the header line with no sections beneath it, report:
> No Jira activity found in the last {{timeframe}}.

## Error Handling

- **Script exits non-zero**: Surface the error message verbatim.
- **curl errors**: Token may be expired or domain unreachable — show the error.
- **jq not installed**: Suggest `brew install jq` (macOS) or `apt install jq` (Linux).
- **JQL not supported**: The script auto-falls back for known unsupported operators; any remaining JQL errors surface in the output.
