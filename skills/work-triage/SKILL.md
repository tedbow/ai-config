---
name: Work Triage Issue
description: This skill should be used when the user runs "/work-triage SCP-XXX" or asks to "work on a triaged issue". Thin worker entry for a parallel triage session — reads today's triage file, resolves the ticket's issue URL and role, then hands off to work-on-mr or review-issue. Skips the full daily-triage assessment.
version: 1.0.0
args:
  - name: jira_key
    description: The Jira ticket key to work on, e.g. SCP-123
    required: true
---

# Work Triage Issue Skill

Thin worker entry for **parallel triage work**. The daily-triage agent has already run in another session and written today's triage folder. This skill picks ONE ticket, resolves its issue + role from that folder, and jumps straight to the right work skill — no re-assessment.

Assumes: the user has already `cd`'d into a free clone (Drupal or SaaS). This skill checks out the correct branch inside whatever clone is current.

## Step 1: Resolve the Triage Folder

```bash
ls ~/triage/$(date +%F)/triage.md 2>/dev/null
```

- **Exists** → Read `~/triage/$(date +%F)/triage.md`
- **Missing** → Tell the user no triage has run today. Suggest running the Daily Triage agent first, then STOP.

## Step 2: Find the Ticket Row

From `triage.md`, find the row for `{{jira_key}}` in the assessment table. Extract:

- **Issue** — the Drupal.org issue number, GitLab work_items URL, or GitHub PR URL
- **Role** — Contributor or Reviewer
- **Notes** — any discrepancies or reviewer feedback flagged

If the ticket key is not in `triage.md`, tell the user and STOP — they may have the wrong key or need to re-run triage.

## Step 3: Open the Per-Ticket Work Log

Path: `~/triage/$(date +%F)/{{jira_key_lowercase}}.md` (e.g. `scp-123.md`).

- **If missing** — create it with a stub:
  ```markdown
  # {{JIRA_KEY}}

  - Jira: {{JIRA_KEY}}
  - Issue: {{issue_url}}
  - Role: {{role}}
  - Status: in-progress

  ## Log
  - started

  ## Notes
  ```
- **If exists** — Read it. Another session (or an earlier run) may have left state. Continue from where it left off; append to the Log, do not overwrite prior entries.

**You are the sole writer of this file.** Rewrite the whole file on each update (append to Log/Notes in memory, then write). No other worker touches this ticket's file.

## Step 4: Hand Off by Role

### Role = Contributor

```
Skill: work-on-mr
args: {{issue_url_or_number}}
```

work-on-mr checks out the MR/PR branch in the current clone, explains context, asks what to change, implements, runs phpcs/phpstan/phpunit.

### Role = Reviewer

```
Skill: review-issue
args: {{issue_url_or_number}}
```

review-issue fetches the issue + MR, analyzes changes, checks CI, drafts a review.

## Step 5: Log Progress

As work proceeds, update `{{jira_key_lowercase}}.md` Log with timestamped entries and set Status. Use the same status vocabulary as the triage agent:

| Event | Status |
|---|---|
| Starting work | `in-progress` |
| Review posted | `review-posted` |
| Code pushed | `pushed` |
| Jira updated | `jira-updated` |
| Blocked | `blocked — [reason]` |
| Complete | `done` |

Record open questions and reviewer feedback in Notes — richer than the Jira status field, and it survives this session ending.

## Important Notes

- **Do NOT re-run the daily-triage assessment.** triage.md is the source of truth for issue URL + role. Trust it.
- **Do NOT touch `triage.md`** — the triage session owns it, you'd race. Only write your own `{{jira_key_lowercase}}.md`.
- **One ticket per session.** Parallel = many terminals, each in its own clone, each running this skill for a different ticket. Branch isolation comes from separate clones, not worktrees.
- If the branch checkout fails because the current clone is dirty or on another ticket's branch, report it and let the user pick a different clone.
