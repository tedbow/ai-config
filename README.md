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

Some agents and skills need your Jira cloud ID, project key, etc. These are stored in a gitignored `.env` file and injected into templates via a build step.

```bash
cp .env.example .env
# Edit .env with your values
./build.sh
```

This generates the following files from their `.tmpl` sources:
- `agents/daily-triage/AGENT.md`
- `skills/fetch-scp-tickets/SKILL.md`
- `jira/fetch-sprint.sh` (todo Update to not need build🤦🏼)

Re-run `./build.sh` after editing `.env` or any `.tmpl` file. Generated files are gitignored — never edit them directly.

To find your Cloud ID, use `mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources`.

### 3. Install do.php and drupalorg

Some skills require both CLIs in your PATH.

- `drupalorg`: https://github.com/mglaman/drupalorg-cli — used for issue/comment fetching
  (`drupalorg issue:show`) and MR pipeline status/logs (`drupalorg mr:status`, `drupalorg
  mr:logs`) once you know an MR's iid.
- `do.php`:(todo Remove this dependency in favor of drupalorg for everything) https://github.com/tedbow/drupal-scripts — still used for MR discovery on classic
  Drupal.org issues (`do.php info --mrs`, `do.php gitlab:mrinfo`, `do.php mr-checkout`).
