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
- `jira/fetch-activity.sh` ← `fetch-activity.sh.tmpl`

These are gitignored. The `.tmpl` files are the source of truth.

`scripts/*.sh` are committed directly (not templated) — they source `.env`
at runtime via `scripts/lib.sh` instead.

## Triage data layer

**Rule: scripts fetch, agents assess.** Everything that talks to Jira, GitLab
or GitHub during triage lives in a committed script. Agents read the files those
scripts produce and never run the fetch CLIs themselves — that is what keeps a
triage run bounded and repeatable.

One entry point builds a day's data:

```bash
scripts/triage-fetch.sh [--open-only] [--refresh] [--days N]
```

```
~/triage/YYYY-MM-DD/data/
  jira-sprint.txt     KEY | STATUS | PRIORITY | TYPE | ASSIGNEE | WORK_LINK | SUMMARY
  jira-links.txt      KEY | URL   (remote links, for rows the sprint fetch could not resolve)
  gitlab-work.txt     SOURCE | KIND | REF | STATE | UPDATED | URL | TITLE
  issues/<slug>.md    compact per-issue detail (description + MRs + last 5 comments)
  issue-index.txt     URL | file
  FETCH-INFO.txt      when, with what flags, how much
```

`--open-only` skips Jira entirely, so the open-source-only Claude profile can
build its own data without ever touching the gateway.

Pieces, callable on their own:

| Script | Does |
|---|---|
| `gitlab/fetch-gitlab-work.sh` | To-Dos, issues assigned to me, MRs I review, recently updated watched projects. No Jira. |
| `scripts/fetch-issue-detail.sh <url-or-number>` | One compact file for a Drupal.org issue, GitLab work item/issue/MR, or GitHub PR. |
| `scripts/triage-fetch.sh` | Runs both into `~/triage/<today>/data/`. |

`gitlab/fetch-gitlab-work.sh` is **committed, not templated** — like `scripts/*.sh`
it reads `.env` at runtime through `scripts/lib.sh`. Only `jira/*.sh` are generated.

Issue URLs are reproduced verbatim from whatever source produced them; a
`/-/work_items/` URL is never rewritten to `drupal.org/i/` or vice versa. The
one exception is completing a host-relative link Jira stored as
`/project/canvas/-/work_items/N`, where the path is left untouched.
