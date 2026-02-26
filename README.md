# ai-config

Claude Code configuration: agents, skills, and hooks.

This is very much a scratch my own itch repository. Use at own risk.

## Setup

### 1. Configure Local Settings

Copy `.local.md.example` files to `.local.md` and fill in your values:

```bash
cp skills/fetch-scp-tickets/fetch-scp-tickets.local.md.example skills/fetch-scp-tickets/fetch-scp-tickets.local.md
cp agents/daily-triage/daily-triage.local.md.example agents/daily-triage/daily-triage.local.md
```

Edit each `.local.md` file with your Atlassian/Jira configuration:
- `cloud_id`: Your Atlassian Cloud ID (find via `mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources`)
- `project`: Your Jira project key (e.g., `SCP`)
- `board_id`: Your Jira board ID (from board URL)
- `board_url`: Full URL to your Jira board (for fallback links)

### 2. Install do.php

Ensure `do.php` is in your PATH.
See https://github.com/tedbow/drupal-scripts
