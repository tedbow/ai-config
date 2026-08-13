# GitLab / Drupal.org issue tooling

How to read and write Drupal.org issues (`git.drupalcode.org` work items) without
burning permission prompts or reaching for the wrong tool.

Written after a session where "create the follow-up issue for <work_item_url>" was
done entirely with raw `glab api` piped through `python3 -c`, triggering a permission
prompt on nearly every call — when a single `do.php` command would have covered all
of the reading with zero prompts.

## Rule 1: reads go through `do.php`

```bash
php ~/projects/drupal-scripts/do.php info <issue-url-or-number> --format=md --comments --mrs
```

Works for **both** old-style Drupal.org issue numbers and new GitLab work items
(`IssueInfo` calls `isGitLabIssue()` and branches to `executeGitLab()` via `GitLabTrait`).

One call returns: title, status, labels, milestone, description, all issue comments,
and — with `--mrs` — each related MR's URL, state, author, and **comment threads**.
That is enough to reconstruct a whole issue discussion including MR review notes.

Verified: covers everything needed to write a follow-up issue.

Known omissions — fall through to `glab api` for these:
- MR *description* body (only the discussion threads come back)
- MR diffs / commits
- anything that writes

Allowed by `Bash(do.php *)` and `Bash(php */do.php *)`. Never prompts.

## Rule 2: `glab api` for gaps and all writes

`Bash(glab api *)` is allowed, including `--method POST` / `PUT`. Writes go through
unprompted, so **confirm with the user before any public write** — creating an issue,
posting a comment, or changing labels on drupal.org is outward-facing.

Host flag is required; drupalcode is not the default host:

```bash
glab api --hostname git.drupalcode.org "projects/project%2Fcanvas/issues/3591784" | jq '.title'
```

Project path is URL-encoded (`project%2Fcanvas`). Work items answer on the `/issues/`
endpoint — `/work_items/` returns 404 on the REST API.

### Verified write recipes

Build the JSON body with `jq` and feed it over stdin. This avoids every shell-quoting
problem with multi-paragraph markdown bodies, and `jq` is allowed.

Create an issue (body read from a file with `--rawfile`):

```bash
jq -n --arg t 'Issue title' --rawfile d body.md \
  '{title:$t, description:$d, labels:"category::task,priority::normal,translation,v1.x-dev", milestone_id:123}' \
  | glab api --hostname git.drupalcode.org --method POST \
      -H "Content-Type: application/json" --input - \
      "projects/project%2Fcanvas/issues" \
  | jq -r '.iid, .web_url'
```

`milestone_id` is the project-level milestone **id** (e.g. `123`), not its `iid`.
`labels` is a single comma-separated string.

Post a comment:

```bash
jq -n '{body:"..."}' | glab api --hostname git.drupalcode.org --method POST \
  -H "Content-Type: application/json" --input - \
  "projects/project%2Fcanvas/issues/<iid>/notes"
```

Add or remove labels without clobbering the rest:

```bash
jq -n '{remove_labels:"Needs followup"}' | glab api --hostname git.drupalcode.org --method PUT \
  -H "Content-Type: application/json" --input - \
  "projects/project%2Fcanvas/issues/<iid>"
```

## Rule 3: parse with `jq`, never `python3 -c`

Two independent reasons:

1. **Permissions.** The permission check splits a pipeline and matches each segment
   separately. `glab api ... | python3 -c "..."` prompts on the `python3` segment even
   though `glab api` is allowed. Same for `| head`, `| tail`, `| wc` — none are in the
   allow list.
2. **Security.** `Bash(python3 -c ...)` is unconstrained arbitrary code execution: it
   can read `~/.config/glab-cli/config.yml` (GitLab tokens, plaintext), and `os.system()`
   shells straight past the deny list (`git push` is denied; `python3 -c
   'import os;os.system("git push --force")'` is not). Deliberately **not** added to the
   allow list. `jq` cannot exec or write files.

The right fix is the right tool, not a wider allow list.

## Permission model gotchas

- Active config dir this machine: `CLAUDE_CONFIG_DIR=/Users/ted.bowman/.claude-mine`.
- `~/.claude/settings.json` and `~/.claude-mine/settings.json` are near-duplicates that
  have drifted. `~/.claude/settings.local.json` (which allows `python3 -c ' *`,
  `glab auth *`, `rtk glab *`) is **inactive** — there is no `settings.local.json` in
  `.claude-mine`. Rules that appear to exist may not be loaded.
- Pipelines are matched per segment. One unlisted segment prompts for the whole command.

## TODO — changes still needed

- [ ] **Always-on tool rule.** The `do.php` guidance currently lives only inside
      `skills/do-issue-info/SKILL.md`, so it is invisible unless that skill triggers —
      and it triggers only on "get issue info"-shaped prompts. Any other drupal.org task
      (create an issue, add a label, read MR notes) misses it. Add a pointer to this file
      under `## Tool Guidelines` in `~/.claude-mine/CLAUDE.md`, next to the playwright-cli
      entry that already works this way.

- [ ] **New skill: `create-followup-issue`.** Nothing covers this workflow today; grep for
      "follow-up" across `skills/` finds only passing mentions. Steps it should encode:
      read the parent with `do.php info --comments --mrs`; extract the agreed scope from
      the issue comments and MR threads; search open issues for a duplicate; draft with
      the Drupal template (Overview / Proposed resolution / Remaining tasks / User
      interface changes) plus the AI-disclosure line; confirm with the user; create via
      the `glab api` recipe above; comment the link on the parent; remove the parent's
      `Needs followup` label.

- [ ] **Cross-link from `do-issue-info`.** Add a line pointing at this file so the
      `glab api` recipes and the `python3` prohibition are reachable from the skill too.

- [ ] **Consider `do.php issue:create`.** `drupal-scripts` has no write commands at all.
      An `issue:create` (and `issue:comment`, `issue:label`) would make the whole
      follow-up workflow one allowed, prompt-free tool. Lower priority — `glab api` already
      works — but it would remove the hand-built JSON.

- [ ] **Reconcile the two settings.json files.** Decide whether `~/.claude` or
      `~/.claude-mine` is canonical and delete or symlink the other. Right now it is not
      obvious which rules are live.

- [ ] **`glab:glab` plugin skill is unusable.** Invoking it fails before it loads:
      its frontmatter runs `` !`glab mr create --help` ``, which is not an allowed pattern,
      so the skill errors out with "Shell command permission check failed". Either allow
      `Bash(glab mr *)` or treat this file as the reference instead of that skill.

## Reference: worked example

Follow-up created this way on 2026-08-10:
parent https://git.drupalcode.org/project/canvas/-/work_items/3591784 →
follow-up https://git.drupalcode.org/project/canvas/-/work_items/3591932
