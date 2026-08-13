---
name: find-dev-folder
description: This skill should be used when the user asks to "find the dev folder for X", "find local site for ticket", "where's my local copy of issue N", or wants to locate the local development directory/directories for a Drupal.org issue, GitLab (git.drupalcode.org) issue, or Jira ticket.
version: 1.0.0
---

# Find Dev Folder

Locate the local development folder(s) for a Drupal.org issue, GitLab
issue/work item, or Jira ticket. Folders under `SITES_DIR` (configured in
`.env`) are named with the issue's Jira key and/or numeric issue ID, e.g.
`SCP-693-3591909-no-pub`, `3583043-config-lang`, `FR-4962`.

The actual folder search is a dumb string match — `scripts/find-dev-folder.sh`
just lists folders whose name contains any of the terms it's given (with
`--list`; without it, the script is also usable interactively from a
terminal to pick a match and cd into it). This skill's job is figuring out
which term(s) to pass it: for a Jira ticket, a folder may be named only with
its *linked* Drupal.org/GitLab issue number, not the Jira key itself, so
both need to be tried.

## Workflow

### 1. Identify the search term(s)

Determine what kind of reference the user gave, and collect one or more
plain search terms from it:

**Drupal.org issue** — input matches:
- a plain number (e.g. `3591909`)
- `https://www.drupal.org/project/<project>/issues/<number>` (`www.` optional)
- `https://drupal.org/i/<number>` (`www.` optional)

Term = the issue number.

**GitLab issue/work item** (some Drupal.org projects, e.g. Canvas/Experience
Builder, use `git.drupalcode.org` instead of the classic issue queue) — input
matches:
```
https://<host>/<namespace>/<project>/-/work_items/<iid>
https://<host>/<namespace>/<project>/-/issues/<iid>
https://<host>/<namespace>/<project>/-/merge_requests/<iid>
```
Examples:
- `https://git.drupalcode.org/project/canvas/-/work_items/3591838`

Term = the numeric `iid`. Folders are named with this number exactly like a
Drupal.org issue number (e.g. `3591838-brandkit`).

**Jira ticket** — input matches:
- a bare key, e.g. `SCP-693`, `FR-4962` (case-insensitive)
- a Jira browse URL, e.g. `https://<domain>/browse/SCP-693`

Term = the key itself (uppercased). Additionally, try to find the ticket's
linked Drupal.org/GitLab issue so folders named only with that number are
still found:
1. Fetch the ticket's description and scan it for a Drupal.org or GitLab
   URL matching the patterns above (same two-phase approach as
   `skills/fetch-scp-tickets`: check the description text/links first).
2. If nothing found in the description, fall back to remote links: run
   `jira/get_link <KEY>` (from the repo root) or call the
   `getJiraIssueRemoteIssueLinks` MCP tool, and scan those URLs the same way.
3. If a linked issue number is found, add it as a second term.
4. If no linked issue can be found, proceed with just the Jira key as the
   term — don't block on this.

**No explicit key/number** (e.g. the user only describes the issue in
words): ask the user for a Jira key, Drupal.org issue number/URL, or GitLab
issue URL — the script only matches literal strings, it can't search by
description.

### 2. Run the script

From the repo root, always with `--list` (plain output, no interactive
prompt/subshell — that mode is only for direct terminal use):
```bash
scripts/find-dev-folder.sh --list <term> [<term> ...]
```
Pass every term gathered in step 1 in a single call.

### 3. Report results

- **One match**: give the full path.
- **Multiple matches**: list all paths, note more than one local folder
  exists for this issue.
- **No match** (script exits 1): say no folder was found under `SITES_DIR`
  for the given term(s), and suggest checking spelling or whether a local
  checkout exists at all.

## Error Handling

- **Script reports `.env` not found**: tell the user to copy `.env.example`
  to `.env` and set `SITES_DIR`.
- **Script reports `SITES_DIR` not set/found**: `SITES_DIR` in `.env` is
  missing or points to a nonexistent directory — ask the user to fix it.
- **Jira linked-issue lookup fails** (API error, rate limit, missing
  `JIRA_API_TOKEN`): don't block — proceed with just the Jira key as the
  search term and note in the response that the linked-issue lookup was
  skipped.
