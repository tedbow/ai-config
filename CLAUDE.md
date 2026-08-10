# ai-config

Claude Code skills, agents, and scripts for daily workflow automation.

## Build Step

Generated files (agents, skills, scripts) are produced from `.tmpl` templates + a gitignored `.env` file. Never edit generated files directly — edit the `.tmpl` source.

### First-time setup
```bash
cp .env.example .env
# Fill in your values
./build.sh
```

### After editing `.env` or any `.tmpl` file
```bash
./build.sh
```

### What's generated
- `agents/daily-triage/AGENT.md` ← `AGENT.md.tmpl`
- `skills/fetch-scp-tickets/SKILL.md` ← `SKILL.md.tmpl`
- `jira/fetch-sprint.sh` ← `fetch-sprint.sh.tmpl`
- `jira/get_link` ← `get_link.tmpl`

These are gitignored. The `.tmpl` files are the source of truth.
