# Bug to file: drupalorg-cli mr:list silent wrong-data fallback

Repo: https://github.com/mglaman/drupalorg-cli

## Summary

`drupalorg mr:list <nid>` (also affects `mr:status`/`mr:logs` in the same way, since they
resolve MRs the same way) is supposed to list merge requests linked to a Drupal.org issue.
When it can't resolve the issue to a GitLab "issue fork" MR, it silently falls back to listing
**unrelated, project-wide open MRs** instead of erroring or returning empty. This can hand an
agent (or a human) the wrong MR with no signal anything went wrong.

## Repro

```bash
drupalorg mr:list 3591850 --format=json
```

Issue [#3591850](https://drupal.org/i/3591850) is "Media library modal cancel button" in the
`drupal` project. The command returned MRs #16716, #16715, #16714... — about backporting CI
jobs, menu UI, `ImageItem::getUploadValidators()` — nothing to do with the media library modal.
These are just the most-recently-updated open MRs on `project/drupal`.

Compare: `do.php info 3591850 --format=md --comments --mrs` (from
[drupal-scripts](https://github.com/tedbow/drupal-scripts)) hits the same underlying "no fork
for this issue" case and either throws (`Multiple issue forks found for issue 3591850: ...`,
when the nid is ambiguous across projects) or returns an empty MRs section (when disambiguated
via a project-qualified URL and no fork exists) — never unrelated data.

## Suggested fix

When no MR/fork can be resolved for the given nid, error or return an empty result — not a
fallback list of unrelated project MRs. If the fallback is intentional (e.g. for a bare
project-path input with no nid), it should be clearly distinguished in the output from
"these are the MRs for your issue."

## Why this matters (context)

Found while migrating `ai-config`'s Drupal.org skills (`do-issue-info`, `review-issue`,
`daily-triage`, `monitor-pipeline`) from `do.php` to `drupalorg`. Worked around it by using
`glab api .../issues/{iid}/related_merge_requests` for GitLab-hosted issue MR discovery instead
of `mr:list`, and leaving `do.php` in place for MR discovery on classic Drupal.org issues. See
[gitlab-info.md](gitlab-info.md) ("Update 2026-08-14: drupalorg CLI" section) for the full
writeup and the migration itself in the skills listed above. Once this is fixed upstream,
`mr:list`/`mr:status` become viable replacements for `do.php info --mrs` / `do.php
gitlab:mrinfo`, closing that gap.

## Also worth mentioning when filing

`mr:list`/`mr:status` return thinner fields than `do.php gitlab:mrinfo` — no `description`,
`has_conflicts`, or `blocking_discussions_resolved`. Not a bug, but worth noting as a feature
request in the same issue or a follow-up if filing separately.
