---
name: Monitor CI Pipeline
description: This skill should be used when the user asks to "monitor a pipeline", "watch CI", "tell me when the pipeline finishes", "babysit CI", or wants to be notified when a GitLab or Drupal.org (git.drupalcode.org) CI pipeline completes — optionally diagnosing and fixing failures when they come back.
version: 1.0.0
---

# Monitor CI Pipeline Skill

You are monitoring a GitLab CI pipeline (typically on `git.drupalcode.org`) in the background, notifying the user when it finishes, and optionally diagnosing/fixing failures.

## Workflow

### 1. Resolve the Pipeline

Accept any of:

**Pipeline URL** — `https://<host>/<project_path>/-/pipelines/<pipeline_id>`
- Extract `host`, `project_path` (URL-encode `/` as `%2F` for API calls), `pipeline_id`. Done.

**MR URL or IID** — resolve the head pipeline:
```bash
curl -s "https://<host>/api/v4/projects/<project_path_encoded>/merge_requests/<mr_iid>" | python3 -c "
import json,sys
m=json.load(sys.stdin)
p=m.get('head_pipeline')
print(p['id'], p['status'], p['sha'][:8], p['web_url'])"
```

**Issue number or issue URL** — a bare number, a Drupal.org issue URL, or a GitLab `/-/work_items/`/`/-/issues/` URL (extract the trailing number; for GitLab URLs the project path in the URL is the canonical project). Find the open MR whose source branch starts with the issue number:
```bash
curl -s "https://<host>/api/v4/projects/<project_path_encoded>/merge_requests?state=opened&source_branch=<branch>" \
  | python3 -c "import json,sys; [print(m['iid'], m['title'], m['source_branch']) for m in json.load(sys.stdin)]"
```
Then resolve the head pipeline as above. If multiple MRs are open and the branch is ambiguous, ask the user which one.

**API notes:**
- Pipeline status and job listings on git.drupalcode.org work **anonymously**.
- Job **traces** return `401` anonymously — fetch with `glab` auth or ask the user to paste the failure.
- Pipelines for issue-fork branches run under the **canonical project** (e.g. `project%2Fcanvas`), not the issue-fork project.

### 2. Check Current Status

If the pipeline is already finished, skip monitoring: report results immediately (see step 5).

### 3. Arm a Monitor

Use the Monitor tool (`persistent: true`). Template — substitute `HOST`, `PROJECT` (URL-encoded), `PIPELINE_ID`:

```bash
prev=""
while true; do
  s=$(curl -s "https://HOST/api/v4/projects/PROJECT/pipelines/PIPELINE_ID" || true)
  pstatus=$(printf '%s' "$s" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
  if [ -n "$pstatus" ] && [ "$pstatus" != "$prev" ]; then echo "pipeline PIPELINE_ID: $pstatus"; prev="$pstatus"; fi
  case "$pstatus" in
    success|failed|canceled|skipped)
      curl -s "https://HOST/api/v4/projects/PROJECT/pipelines/PIPELINE_ID/jobs?per_page=100" | python3 -c "
import json,sys
for j in json.load(sys.stdin):
    if j['status'] not in ('success','skipped','manual'):
        print('job:', j['name'], j['status'], j['web_url'])" 2>/dev/null || true
      break;;
  esac
  sleep 60
done
```

**Script gotchas (learned the hard way):**
- Do NOT name a shell variable `status` — read-only in zsh; the monitor dies with `read-only variable: status`.
- `curl ... || true` so one failed request doesn't kill the loop.
- 60s poll interval — remote API, respect rate limits.
- The script exits on terminal state after listing non-passing jobs; that exit is itself a notification.

### 4. Schedule a Fallback Heartbeat

If running inside a `/loop` dynamic session, call ScheduleWakeup with `delaySeconds` 1200–1800 as a fallback in case the monitor dies silently. The monitor notification is the primary wake signal.

When the pipeline reaches a terminal state: stop the loop (`ScheduleWakeup {stop: true}`) and TaskStop the monitor if it is still running.

### 5. Report Results

On completion:
- **Success**: report it plainly, including pipeline URL.
- **Failed jobs**: list them with URLs. Before diagnosing, check each failed job's `allow_failure` flag:
```bash
curl -s ".../pipelines/<id>/jobs?per_page=100" | python3 -c "
import json,sys
for j in json.load(sys.stdin):
    if j['status']=='failed':
        print(j['name'], 'allow_failure:', j['allow_failure'])"
```
- A pipeline can be **green overall with failed `allow_failure: true` jobs** — still surface those to the user.
- **Check for pre-existing failures**: compare against the target branch's (e.g. `1.x`) recent pipeline for the same job before treating a failure as a branch regression. A job that also fails (or was skipped) on the target branch is not this MR's problem.

### 6. Diagnose and Fix (only if the user asked)

- Fetch the failed job trace (needs `glab` auth) or ask the user to paste it.
- Diagnose root cause before editing; the failure may be environment-specific. Example: the `drupal.todoCurrentIssue` PHPStan rule only fires in CI because it reads `CI_MERGE_REQUEST_SOURCE_BRANCH_NAME` — simulate locally with `CI_MERGE_REQUEST_SOURCE_BRANCH_NAME=<branch> composer run lint`.
- Hand off to the "Work on Merge Request" skill flow for implementing fixes.
- NEVER push without human approval.

## Error Handling

- **Monitor exits non-zero**: Read its output file, fix the script (see gotchas), re-arm.
- **Pipeline not found / 404**: verify project path encoding and that the pipeline belongs to the canonical project, not the issue fork.
- **401 on trace**: expected anonymously; use `glab` or ask the user.
