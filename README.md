# ai-config

Claude Code configuration: agents, skills, and hooks.

This is very much a scratch my own itch repository. Use at own risk.

## Setup

### 1. Symlink into ~/.claude

```bash
ln -s /path/to/ai-config/skills ~/.claude/skills
ln -s /path/to/ai-config/agents ~/.claude/agents
```

### 2. Configure Atlassian/Jira Settings

Some agents and skills use `{{cloud_id}}`, `{{project}}`, `{{board_id}}`, and `{{board_url}}` placeholders.

Add your values to `~/.claude/CLAUDE.md`:

```markdown
## Atlassian Config
- cloud_id: YOUR_CLOUD_ID
- project: YOUR_PROJECT_KEY
- board_id: YOUR_BOARD_ID
- board_url: https://YOUR_ORG.atlassian.net/jira/software/c/projects/YOUR_PROJECT/boards/YOUR_BOARD_ID
```

To find your Cloud ID, use `mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources`.

### 3. Install do.php

Some skills require `do.php` in your PATH.
See https://github.com/tedbow/drupal-scripts
