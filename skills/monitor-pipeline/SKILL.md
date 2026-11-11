---
name: Monitor CI Pipeline
description: This skill should be used when the user asks to "monitor a pipeline", "watch CI", "tell me when the pipeline finishes", "babysit CI", "retry the failed jobs", or wants to be notified when a GitLab or Drupal.org (git.drupalcode.org) CI pipeline completes — retrying jobs that timed out or failed at random, and optionally diagnosing and fixing failures when they come back.
version: 1.1.0
---

# Monitor CI Pipeline Skill

You are monitoring a GitLab CI pipeline (typically on `git.drupalcode.org`) in the background, retrying jobs that failed for reasons a re-run can fix, notifying the user when it finishes, and optionally diagnosing/fixing failures.

## Workflow

### 1. Resolve the Pipeline

Accept any of:

**Pipeline URL** — `https://<host>/<project_path>/-/pipelines/<pipeline_id>`
- Extract `host`, `project_path` (URL-encode `/` as `%2F` for API calls), `pipeline_id`. No MR context — use the pipeline-only path in later steps.

**MR URL or IID** — you already have `project_path` + `mr_iid`. Use the MR-context path in later steps (`drupalorg mr:status "<project_path>!<mr_iid>"`).

**Issue number or issue URL** — a bare number, a Drupal.org issue URL, or a GitLab `/-/work_items/`/`/-/issues/` URL (extract the trailing number; for GitLab URLs the project path in the URL is the canonical project). Find the open MR whose source branch starts with the issue number:
```bash
curl -s "https://<host>/api/v4/projects/<project_path_encoded>/merge_requests?state=opened&source_branch=<branch>" \
  | python3 -c "import json,sys; [print(m['iid'], m['title'], m['source_branch']) for m in json.load(sys.stdin)]"
```
If multiple MRs are open and the branch is ambiguous, ask the user which one. Once resolved you
have `project_path` + `mr_iid` — use the MR-context path below.

**API notes:**
- Pipeline status and job listings on git.drupalcode.org work **anonymously** via raw `curl`.
- `drupalorg mr:status`/`mr:logs` authenticate internally (`DRUPALORG_GITLAB_TOKEN` or `glab`
  config), so `mr:logs` gets job traces without the anonymous `401` raw `curl` hits.
- `drupalorg`'s MR commands are MR-scoped (`project-path!mr-iid`) — they don't take a bare
  pipeline ID. When only a pipeline URL is known (no MR), stay on the raw `curl` path below.
- Pipelines for issue-fork branches run under the **canonical project** (e.g. `project%2Fcanvas`),
  not the issue-fork project.

### 2. Check Current Status

If the pipeline is already finished, skip monitoring: report results immediately (see step 5).

### 3. Arm a Monitor

Use the Monitor tool (`persistent: true`).

**MR context known** (from an MR URL/IID, or resolved from an issue) — no `python3`, no raw `curl`,
just `drupalorg`. Substitute `PROJECT_PATH`, `MR_IID`:

```bash
prev=""
while true; do
  out=$(drupalorg mr:status "PROJECT_PATH!MR_IID" --format=text 2>&1 || true)
  if [ "$out" != "$prev" ]; then echo "$out"; prev="$out"; fi
  if printf '%s' "$out" | grep -qE '\b(passed|success|failed|canceled|skipped)\b'; then
    break
  fi
  sleep 60
done
```

**Pipeline-only context** (bare pipeline URL, no MR) — falls back to raw `curl`. Template —
substitute `HOST`, `PROJECT` (URL-encoded), `PIPELINE_ID`:

```bash
prev=""
while true; do
  s=$(curl -s "https://HOST/api/v4/projects/PROJECT/pipelines/PIPELINE_ID" || true)
  pstatus=$(printf '%s' "$s" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
  if [ -n "$pstatus" ] && [ "$pstatus" != "$prev" ]; then echo "pipeline PIPELINE_ID: $pstatus"; prev="$pstatus"; fi
  case "$pstatus" in
    success|failed|canceled|skipped) break;;
  esac
  sleep 60
done
```

**Job-level monitor** (use this one whenever jobs may be retried, see Step 6). The pipeline status
alone is not enough: it stays `running` while one job is retried and flips to `failed` as soon as
a blocking job fails. This variant emits one line per job state change and exits when no job is
active. Substitute `HOST`, `PROJECT` (URL-encoded), `PIPELINE_ID`:

```bash
prev=""
while true; do
  cur=$(curl -s "https://HOST/api/v4/projects/PROJECT/pipelines/PIPELINE_ID/jobs?per_page=100" | python3 -c "
import json,sys
js=json.load(sys.stdin)
for j in sorted(js, key=lambda j:j['name']):
    if j['status'] not in ('success','skipped','manual'):
        print(j['id'], j['name'], j['status'], j.get('failure_reason') or '', 'allow_failure=%s' % j['allow_failure'])
if not any(j['status'] in ('running','pending','created','waiting_for_resource','preparing','scheduled') for j in js):
    print('ALL_JOBS_SETTLED')
" 2>/dev/null || true)
  if [ -n "$cur" ] && [ "$cur" != "$prev" ]; then
    comm -13 <(printf '%s\n' "$prev") <(printf '%s\n' "$cur")
    prev="$cur"
  fi
  if printf '%s' "$cur" | grep -q ALL_JOBS_SETTLED; then break; fi
  sleep 60
done
```

The jobs list returns only the latest attempt of each job. Add `&include_retried=true` to see
earlier attempts (to tell "already retried" from "never retried").

**Script gotchas (learned the hard way):**
- A monitor expires after at most 30 minutes (`timeout_ms: 1800000`). Re-arm it on expiry and
  after every retry, because the script exits each time all jobs settle.
- Do NOT name a shell variable `status` — read-only in zsh; the monitor dies with `read-only variable: status`.
- `curl ... || true` so one failed request doesn't kill the loop.
- 60s poll interval — remote API, respect rate limits.
- The script exits on terminal state; that exit is itself a notification. Job details are fetched
  separately in Step 5, not inside the loop.

### 4. Schedule a Fallback Heartbeat

If running inside a `/loop` dynamic session, call ScheduleWakeup with `delaySeconds` 1200–1800 as a fallback in case the monitor dies silently. The monitor notification is the primary wake signal.

When the pipeline reaches a terminal state: stop the loop (`ScheduleWakeup {stop: true}`) and TaskStop the monitor if it is still running.

### 5. Report Results

On completion:
- **Success**: report it plainly, including pipeline URL.
- **Failed jobs (MR context known)**: fetch names + trace excerpts in one call — this also covers
  Step 7's trace-fetch, no separate auth-gated request needed:
```bash
drupalorg mr:logs "PROJECT_PATH!MR_IID" --format=json
```
  `mr:logs` doesn't report `allow_failure` or per-job `web_url`, so check those separately:
```bash
curl -s ".../pipelines/<id>/jobs?per_page=100" | python3 -c "
import json,sys
for j in json.load(sys.stdin):
    if j['status']=='failed':
        print(j['name'], 'allow_failure:', j['allow_failure'], j['web_url'])"
```
- **Failed jobs (pipeline-only context)**: no MR to scope `mr:logs` to — list jobs and check
  `allow_failure` the same way:
```bash
curl -s ".../pipelines/<id>/jobs?per_page=100" | python3 -c "
import json,sys
for j in json.load(sys.stdin):
    if j['status'] not in ('success','skipped','manual'):
        print('job:', j['name'], j['status'], j['web_url'], 'allow_failure:', j['allow_failure'])"
```
- A pipeline can be **green overall with failed `allow_failure: true` jobs** — still surface those to the user.
- **Check for pre-existing failures**: compare against the target branch's (e.g. `1.x`) recent pipeline for the same job before treating a failure as a branch regression. A job that also fails (or was skipped) on the target branch is not this MR's problem.

### 6. Retry Failed Jobs (default)

Retry by default. Skip this step only when the user said not to retry, or when the superseded
check below fails. Tell the user about every retry: job name, old and new job ID, and the reason.

**6a. Superseded check — do this before every retry.** Do not retry a job in a pipeline that a
newer push has replaced. Compare the monitored pipeline with the newest one for the same MR or ref:

```bash
# MR context
curl -s "https://HOST/api/v4/projects/PROJECT/merge_requests/MR_IID" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['sha'], (d.get('head_pipeline') or {}).get('id'))"
# Pipeline-only context: newest pipeline for the same ref
curl -s "https://HOST/api/v4/projects/PROJECT/pipelines?ref=REF&per_page=1" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])"
```

If the newest pipeline ID differs from the monitored one, a commit was pushed and a different run
started. Retry nothing in the old pipeline, stop its monitor, tell the user, and monitor the new
pipeline instead. A merge-request pipeline's ref is `refs/merge-requests/<iid>/merge`, which gives
the MR IID when only a pipeline URL was supplied.

**6b. Decide per failed job** from `failure_reason` and the trace:

| Failure | Action |
|---|---|
| `job_execution_timeout`, `runner_system_failure`, `stuck_or_timeout_failure`, `scheduler_failure`, `api_failure` — in any job, including PHPUnit, lint and build | Retry. These are infrastructure failures, not test results. Stop after three such failures of the same job and report. |
| `script_failure` in a browser suite (Playwright, Cypress) | Read the trace and list the failing tests. Retry once. |
| `script_failure`, same test fails in two full runs | Check the same job on the target branch and in earlier pipelines of this MR. If the test both fails and passes there with no related change, and the branch does not touch that code, retry one more time. Otherwise stop. |
| `script_failure`, same test fails in three full runs | Stop retrying and report. This is not random for this pipeline. |
| `script_failure` in PHPUnit, lint, PHPStan, build (the job ran to the end and reported a failure; not a timeout) | Do not retry. These are deterministic; report and go to Step 7 if the user asked for a fix. |
| An already-retried job (a newer attempt exists) | Leave it alone; watch the newer attempt. |

Classify by `failure_reason` first and by job type second: a PHPUnit job that hit the time limit
is a timeout and is retried (the Canvas `PHPUnit-Kernel` job did this and passed on a later run).

Compare failing test names between attempts, not only the job status. Fetch traces with `glab`
(anonymous requests get `401`):

```bash
glab api --hostname HOST "projects/PROJECT/jobs/JOB_ID/trace" > JOB_ID.log
sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' JOB_ID.log | grep -E '✘|[0-9]+ (failed|flaky)|Error:'
```

**6c. Retry.** Needs Developer access or higher; confirm once with
`glab api --hostname HOST "projects/PROJECT"` (`permissions.project_access.access_level` ≥ 30).

```bash
glab api --hostname HOST --method POST "projects/PROJECT/jobs/JOB_ID/retry" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id'), d.get('name'), d.get('status'), d.get('message') or '')"
```

Then re-arm the job-level monitor from Step 3.

**6d. Aggregator jobs run last.** Some jobs fail only because an upstream job failed, and they
record that at the time they ran. Retry them after every upstream job has passed, never before.
Example (Canvas): `playwright: [n/6]` is `allow_failure: true` so that `playwright-reports` still
runs and builds the report, and `playwright-reports` then counts failed shards through the GitLab
API and exits 1. A failed shard therefore still blocks the pipeline, one job later. For green, all
six shards must pass and `playwright-reports` must be re-run afterwards. So do not skip a retry
only because the failed job says `allow_failure: true`; check whether a later job depends on it.

**6e. Finish.** When every job has passed, confirm the pipeline status is `success` and report it
with the pipeline URL. When a job is stopped under 6b, report the failing test, the error, how
many attempts failed, and what the target branch shows.

### 7. Diagnose and Fix (only if the user asked)

- If MR context is known, the trace excerpts from Step 5's `mr:logs` call are usually enough. For
  the pipeline-only path (or if `mr:logs` doesn't cover a specific job), fetch the trace with
  `glab` auth or ask the user to paste it — raw job trace endpoints return `401` anonymously.
- Diagnose root cause before editing; the failure may be environment-specific. Example: the `drupal.todoCurrentIssue` PHPStan rule only fires in CI because it reads `CI_MERGE_REQUEST_SOURCE_BRANCH_NAME` — simulate locally with `CI_MERGE_REQUEST_SOURCE_BRANCH_NAME=<branch> composer run lint`.
- Hand off to the "Work on Merge Request" skill flow for implementing fixes.
- NEVER push without human approval.

## Error Handling

- **Monitor exits non-zero**: Read its output file, fix the script (see gotchas), re-arm.
- **Pipeline not found / 404**: verify project path encoding and that the pipeline belongs to the canonical project, not the issue fork.
- **401 on trace**: expected anonymously; use `glab` or ask the user.
