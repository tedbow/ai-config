# Plan: One-command daily triage with deterministic data, canvas queue, and herdr-launched workers

## Context

`todo/improve-workflow.md` asks for: one command to start the day, triage that also covers the Drupal Canvas GitLab queue (assigned / mentioned, not just Jira), predictable low-token behaviour (scripts fetch, agents assess), automatic site setup when a ticket is worked, and the triage agent spinning up per-ticket worker agents it can check on. The two Claude profiles must stay separated: `claude-work` (gateway, may see Jira + proprietary GitHub) runs the main triage; `claude-mine` (personal, open source only) runs Canvas triage and open-source workers, and never reads Jira text.

Decisions already made (from Q&A):
- Workers run as **interactive Claude sessions in herdr spaces**, one workspace per ticket, started by the triage agent via the `herdr` CLI. Verified: `herdr workspace create --cwd --env --label`, `herdr agent start <name> --kind claude --pane <id> -- <args>`, `herdr agent prompt|wait|read|list`, `herdr pane run`.
- Canvas scope: assigned to me + GitLab To-Dos (mentioned/review_requested/etc.) + recently updated canvas issues (titles only, no detail fetch).
- Jira boundary: `claude-mine` workers get a **stub** with issue URL + role + any non-private context the GitLab issue lacks. If the GitLab issue can't stand on its own, the `claude-work` triage proposes a GitLab comment/description update for the human to approve.
- Proprietary clones: a small pool under `~/sites/` (`haas-main` is the pristine source; `haas-drupal-2`, `haas3` exist). Launcher claims a free clone, creates a new one from `haas-main` when none are free (cap 4). Note: `~/sites/haas-drupal` and `~/sites/haas-drupal-2` share ddev name `haas`; the pool gives each clone a unique ddev project name.

Follow-up improvements discussed after the first draft (to fold in):
- **Work modes** per ticket: `reply` (draft comment inline, no worker/site), `review` (API diff review, no site), `review+test` (site), `develop` (site). Triage proposes the mode; only the last two provision a site.
- Reuse before create: existing herdr workspace labelled with the ticket, existing site via `find-dev-folder.sh`.
- YAML-frontmatter stubs; "decisions first" presentation; midday delta via `fetch-activity.sh`; fetch done To-Dos for last N days; dedupe Jira vs canvas rows by URL; `site:gc` (now in the focused plan above).
- Provisioning uses `do.php site:clone` (focused plan) instead of `site:setup`.

## Target layout

```
~/triage/YYYY-MM-DD/
  data/                      # written ONLY by scripts (deterministic)
    jira-sprint.txt          # fetch-sprint.sh rows                       [work-only]
    gitlab-work.txt          # todos + assigned issues + reviewer MRs + recent canvas [open]
    issues/<slug>.md         # per-issue compact detail (fetch-issue-detail.sh)
  canvas.md                  # written by claude-mine canvas-triage agent (open)
  triage.md                  # written by claude-work daily-triage agent
  tickets/
    scp-693.md               # stub (triage writes once) -> worker log (worker sole writer)
    canvas-3592103.md        # same for non-Jira canvas issues
```

Stub format (what a worker, incl. claude-mine, is allowed to read):
```markdown
# SCP-693
- Issue: https://git.drupalcode.org/project/canvas/-/work_items/3591909
- Role: Contributor
- Profile: mine            # or work
- Site: ~/sites/SCP-693-3591909-no-pub   # filled by provision-site.sh
- Herdr: w1X               # filled by launch-worker.sh
- Status: in-progress
## Context            # ONLY non-private info the GitLab issue lacks; empty for GitHub tickets
## Log
## Notes
```

## Phase A — Deterministic data layer (scripts, no agent changes yet)

1. **`gitlab/fetch-gitlab-work.sh`** (committed, no template; host `git.drupalcode.org`, username from `.env` `GITLAB_USERNAME`, canvas project from `.env` `GITLAB_WATCH_PROJECTS=project/canvas`). Uses `glab api --hostname` + jq, same style as `jira/fetch-sprint.sh.tmpl`. Emits pipe rows:
   `SOURCE | KIND | REF | STATE | UPDATED | URL | TITLE`
   - `todo`: `/todos?state=pending` (SOURCE = action_name: mentioned, review_requested, build_failed, unmergeable, assigned, directly_addressed)
   - `assigned`: `/issues?scope=assigned_to_me&state=opened`
   - `reviewer`: `/merge_requests?scope=all&reviewer_username=$GITLAB_USERNAME&state=opened`
   - `recent`: `/projects/<id>/issues?state=opened&updated_after=<N days>` per watched project (`--days`, default 2)
   - Dedupe by URL, keep the most specific SOURCE. Must not need any Jira env.
2. **`scripts/fetch-issue-detail.sh <url-or-number> [--out dir]`** — dispatcher that replaces the agent-side Step 3 fetching. By URL type: drupal.org → `do.php info N --format=md --comments --mrs`; `git.drupalcode.org` work_items/issues → `drupalorg issue:show --format=llm --with-comments` + `glab api .../related_merge_requests` (+ MR head pipeline status); GitHub PR → `gh pr view --json …`. Writes `data/issues/<slug>.md`, truncating comments to the last N (`--comments 5`) to bound tokens. Idempotent (skips if file fresh unless `--refresh`).
3. **`scripts/triage-fetch.sh [--open-only] [--refresh] [--days N]`** — builds `~/triage/$(date +%F)/data/`:
   - without `--open-only`: `jira/fetch-sprint.sh` → `jira-sprint.txt`; `scripts/get_link.sh` fallback for assigned rows with empty WORK_LINK (replaces agent Step 2).
   - always: `fetch-gitlab-work.sh` → `gitlab-work.txt`.
   - detail fetch for: assigned Jira tickets' work links + every `todo`/`assigned`/`reviewer` row. Not for `recent` rows.
   - Reuse `scripts/lib.sh` for `.env`. Add `GITLAB_USERNAME`, `GITLAB_WATCH_PROJECTS`, `HAAS_SOURCE_CLONE`, `HAAS_POOL_MAX` to `.env.example`; `build.sh` unchanged (these are runtime vars, not template vars).

## Phase B — Agents read files, never fetch

4. **New `agents/canvas-triage/AGENT.md`** (plain, not templated, zero Jira references). Input: `data/gitlab-work.txt` + `data/issues/*.md` for GitLab rows. Output: `canvas.md` with a table `Ref | Why (assigned/mentioned/review_requested/recent) | Kind | State | MR/CI | Suggested role | Suggested action`, a "Needs your decision" list, and "Recently updated (titles only)". Runs headless: `claude-mine -p --agent canvas-triage "…"`. No AskUserQuestion, no external writes.
5. **Rewrite `agents/daily-triage/AGENT.md.tmpl`**:
   - Step 0 unchanged (existing-file prompt). Steps 1–3 become "read `data/jira-sprint.txt`, `data/issues/*.md`, and `canvas.md` if present". Remove all fetch commands and the MCP remote-links step; if `data/` is missing, tell the user to run `triage-fetch.sh` and stop.
   - Keep role detection, discrepancy detection, Checkpoint 1 table, Links rules (verbatim URL rule), Checkpoint 2 confirmations, Jira write actions via MCP.
   - Add a **Canvas section** merging `canvas.md` rows that have no Jira ticket.
   - Add **profile column**: GitHub/proprietary → `work`; GitLab/drupal.org → `mine`.
   - Replace copy/paste launcher lines with: write `tickets/<id>.md` stubs for assigned + user-selected tickets (including `## Context` for GitLab-backed Jira tickets where the GitLab issue lacks needed non-private info), then AskUserQuestion multi-select "Which workers should I launch now?" → run `scripts/launch-worker.sh <id>` per pick. Also flag "GitLab issue is thin → propose this comment" items for approval (post via `glab` after confirmation).
   - Add **Monitor step**: `scripts/triage-status.sh` to summarise worker states; `herdr agent wait <name> --until blocked --timeout …` / `herdr agent read` when asked "check on workers"; relay what the worker is blocked on. Never prompts a worker to take an external action on the user's behalf.
6. **Update `skills/work-triage/SKILL.md`**: accept `SCP-NNN` or a canvas issue id/URL; read ONLY `tickets/<id>.md` (never `triage.md`); assume cwd is the provisioned site; hand off to `work-on-mr` / `review-issue` as today; sole writer of its stub; stop and ask (so herdr shows `blocked`) before any push/comment/Jira change — already the behaviour of the downstream skills.

## Phase C — Provisioning and launching workers

7. **`scripts/haas-clone.sh list|claim <ticket>|release <ticket>|create`** — pool of proprietary ddev clones. Claim = write `.triage-claim` (ticket, date) in a clone whose tree is clean (`git status --porcelain` empty) and has no live claim; `create` = `git clone ~/sites/haas-main ~/sites/haas-N` + `ddev config --project-name haas-N` + copy of local settings, capped by `HAAS_POOL_MAX`. `list` shows claim/branch/ddev state.
8. **`scripts/provision-site.sh <ticket-id>`** — reads the stub; GitLab/drupal.org: `scripts/find-dev-folder.sh --list <key> <iid>` first; otherwise `do.php site:clone <KEY>-<iid>-<slug> --issue-url=<url>` (focused plan), falling back to `--branch=<default>` when there is no MR yet. GitHub: `haas-clone.sh claim` then `gh pr checkout` (or create branch). Writes `- Site:` into the stub. Runs in the foreground of the launcher so composer/ddev time is outside any agent.
9. **`scripts/launch-worker.sh <ticket-id>`** — `provision-site.sh` → `herdr workspace create --cwd <site> --label <id> --env CLAUDE_PROFILE=<mine|work> --no-focus` → `herdr agent start <id> --kind claude --pane <root_pane> -- "/work-triage <id>"` → write `- Herdr: <workspace_id>` into the stub. Agent names must match `[a-z][a-z0-9_-]{0,31}` (`scp-693`, `canvas-3592103`). Fallback if `agent start` fails: `herdr pane run <pane> "claude-<profile> \"/work-triage <id>\""` then `herdr agent rename <pane> <id>`.
10. **`~/.zshrc` change (manual, user-owned file)**: make `claude()` dispatch on `$CLAUDE_PROFILE` (`mine` → `claude-mine "$@"`, `work` → `claude-work "$@"`, unset → current error message). Required because `herdr agent start --kind claude` types the bare `claude` command. Document in README; do not commit the file.
11. **`scripts/triage-status.sh`** — joins `tickets/*.md` (Status, Herdr id) with `herdr agent list` JSON → one line per ticket: `id | role | profile | status | herdr state | site`. Used by the triage agent's monitor step and directly by the user.

## Phase D — The one command

12. **`scripts/triage-day.sh [--refresh] [--open-only]`**:
    1. `triage-fetch.sh` (same flags).
    2. `claude-mine -p --agent canvas-triage` → `canvas.md` (skip if present and not `--refresh`).
    3. `exec claude-work --agent daily-triage` in the current pane (interactive).
    With `--open-only` it skips Jira and step 3 runs `claude-mine --agent canvas-triage` interactively instead, so a pure open-source day never touches the gateway.
13. Update `CLAUDE.md` (repo) with the layout above, the data/agent split rule ("scripts fetch, agents assess"), the profile boundary, and the three entry points (`triage-day.sh`, `launch-worker.sh`, `triage-status.sh`). Run `link-skills.sh` after adding `agents/canvas-triage`. Delete `todo/improve-workflow.md` items as they land (or move to a `done` note).

## Files

- New: `gitlab/fetch-gitlab-work.sh`, `scripts/fetch-issue-detail.sh`, `scripts/triage-fetch.sh`, `scripts/haas-clone.sh`, `scripts/provision-site.sh`, `scripts/launch-worker.sh`, `scripts/triage-status.sh`, `scripts/triage-day.sh`, `agents/canvas-triage/AGENT.md`
- Modified: `agents/daily-triage/AGENT.md.tmpl`, `skills/work-triage/SKILL.md`, `.env.example`, `CLAUDE.md`, (manual) `~/.zshrc`
- Reused: `jira/fetch-sprint.sh.tmpl`, `scripts/get_link.sh`, `scripts/find-dev-folder.sh`, `scripts/lib.sh`, `~/projects/drupal-scripts/do.php site:setup` (`SiteSetup.php`), `drupalorg`, `glab`, `gh`, `herdr`

## Verification

1. `scripts/triage-fetch.sh --open-only --days 3` → inspect `~/triage/<today>/data/gitlab-work.txt` (expect todo rows incl. `review_requested` for canvas!1802) and `data/issues/*.md` sizes are bounded.
2. `scripts/triage-fetch.sh` (full) → `jira-sprint.txt` present; no Jira content under `data/issues/` for GitHub tickets beyond PR metadata.
3. `claude-mine -p --agent canvas-triage` → `canvas.md` produced with no Jira keys in it (`grep -c SCP- canvas.md` = 0).
4. `scripts/triage-day.sh` → `triage.md` written, canvas section present, stubs created for selected tickets, no network fetch commands appear in the agent transcript.
5. `scripts/launch-worker.sh canvas-<iid>` on a known canvas issue with an MR → `herdr workspace list` shows the new space with the site as cwd, `herdr agent list` shows `canvas-<iid>`, stub has `Site:` and `Herdr:`; the worker reaches `blocked` at its first question and `triage-status.sh` reports it.
6. `scripts/launch-worker.sh SCP-<n>` for a GitHub ticket → `haas-clone.sh list` shows the claim, PR branch checked out, worker launched with `CLAUDE_PROFILE=work`.
7. Token check: compare `triage.md` run cost before/after via `/cost` for one day; the agent transcript should contain only `Read` of `data/` files plus `herdr`/`launch-worker` calls.
