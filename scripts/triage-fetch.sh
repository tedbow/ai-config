#!/bin/bash
#
# Build one day's deterministic triage data. Scripts fetch, agents assess —
# this is the only thing that talks to Jira, GitLab or GitHub during triage.
#
# Writes (and nothing else writes here):
#   ~/triage/<today>/data/jira-sprint.txt   open-sprint Jira rows        [skipped by --open-only]
#   ~/triage/<today>/data/jira-links.txt    KEY | URL remote links       [skipped by --open-only]
#   ~/triage/<today>/data/gitlab-work.txt   To-Dos, assigned, reviewer, recent
#   ~/triage/<today>/data/issues/<slug>.md  compact per-issue detail
#   ~/triage/<today>/data/issue-index.txt   URL | file, for the agents
#   ~/triage/<today>/data/FETCH-INFO.txt    when, with what flags, how much
#
# Usage: triage-fetch.sh [--open-only] [--refresh] [--days N] [options]
#   --open-only       no Jira at all: safe to run from the open-source-only
#                     Claude profile
#   --refresh         refetch issue detail even when it is still fresh
#   --days N          window for done To-Dos and watched-project issues (default 2)
#   --todo-days N     window on pending To-Do creation date (default 14)
#   --comments N      comments kept per issue (default 5)
#   --max-details N   cap on per-issue detail fetches (default 60)
#   --jobs N          parallel detail fetches (default 4)
#
# Detail is fetched for: Jira tickets assigned to you (their work link), and
# every GitLab To-Do / assigned / reviewer row. Deliberately NOT for `recent`
# rows — those stay titles-only — nor for `done:` rows.
#
# Requires: $JIRA_API_TOKEN unless --open-only, plus the tools used by
# gitlab/fetch-gitlab-work.sh and scripts/fetch-issue-detail.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

OPEN_ONLY=false
REFRESH=false
DAYS=2
TODO_DAYS=14
COMMENTS=5
MAX_DETAILS=60
JOBS=4

while [ $# -gt 0 ]; do
  case "$1" in
    --open-only) OPEN_ONLY=true; shift ;;
    --refresh) REFRESH=true; shift ;;
    --days) DAYS="${2:?--days needs a number}"; shift 2 ;;
    --days=*) DAYS="${1#*=}"; shift ;;
    --todo-days) TODO_DAYS="${2:?--todo-days needs a number}"; shift 2 ;;
    --todo-days=*) TODO_DAYS="${1#*=}"; shift ;;
    --comments) COMMENTS="${2:?--comments needs a number}"; shift 2 ;;
    --comments=*) COMMENTS="${1#*=}"; shift ;;
    --max-details) MAX_DETAILS="${2:?--max-details needs a number}"; shift 2 ;;
    --max-details=*) MAX_DETAILS="${1#*=}"; shift ;;
    --jobs) JOBS="${2:?--jobs needs a number}"; shift 2 ;;
    --jobs=*) JOBS="${1#*=}"; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//;$d'; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

TRIAGE_ROOT="${TRIAGE_ROOT:-$HOME/triage}"
GITLAB_HOST="${GITLAB_HOST:-git.drupalcode.org}"
DAY="$(date +%F)"
DATA="${TRIAGE_ROOT}/${DAY}/data"
ISSUES="${DATA}/issues"
mkdir -p "$ISSUES"

step() { echo "==> $*" >&2; }
warn() { echo "WARNING: $*" >&2; }

DETAIL_ARGS=(--out "$ISSUES" --comments "$COMMENTS" --print-path)
[ "$REFRESH" = true ] && DETAIL_ARGS+=(--refresh)

# URLs queued for per-issue detail, deduped at the end.
TARGETS="$(mktemp "${TMPDIR:-/tmp}/triage-targets.XXXXXX")"
trap 'rm -f "$TARGETS"' EXIT

# Same precedence as jira/fetch-sprint.sh: a Drupal.org issue beats a GitLab
# work item/MR beats a GitHub PR. URLs are never rewritten between forms.
first_work_link() {
  jq -R -s -r '
    [ splits("\\s+") ] | map(select(length > 0)) as $u
    | ( $u | map(select(test("drupal\\.org/i/[0-9]+|drupal\\.org/project/[^ ]+/issues/[0-9]+"))) | .[0] ) as $d
    | ( $u | map(select(test("/-/work_items/[0-9]+|/-/issues/[0-9]+|/-/merge_requests/[0-9]+"))) | .[0] ) as $g
    | ( $u | map(select(test("github\\.com/[^ ]+/pull/[0-9]+"))) | .[0] ) as $h
    | ( $d // $g // $h // "" )
  '
}

# ------------------------------------------------------------------- Jira ---

JIRA_ROWS=0
JIRA_RESOLVED=0

if [ "$OPEN_ONLY" = true ]; then
  step "skipping Jira (--open-only)"
  rm -f "${DATA}/jira-sprint.txt" "${DATA}/jira-links.txt"
else
  if [ -z "${JIRA_API_TOKEN:-}" ]; then
    echo "ERROR: JIRA_API_TOKEN not set. Export it, or run with --open-only." >&2
    exit 1
  fi
  if [ ! -x "${REPO_ROOT}/jira/fetch-sprint.sh" ]; then
    echo "ERROR: ${REPO_ROOT}/jira/fetch-sprint.sh missing. Run ./build.sh." >&2
    exit 1
  fi

  step "fetching Jira open sprint"
  "${REPO_ROOT}/jira/fetch-sprint.sh" > "${DATA}/jira-sprint.txt"
  JIRA_ROWS=$(wc -l < "${DATA}/jira-sprint.txt" | tr -d ' ')

  # Who am I? Needed to tell assigned rows from everyone else's.
  ME="${JIRA_DISPLAY_NAME:-}"
  if [ -z "$ME" ]; then
    AUTH=$(printf '%s' "${JIRA_EMAIL}:${JIRA_API_TOKEN}" | base64)
    ME=$(curl -s -H "Authorization: Basic ${AUTH}" -H "Accept: application/json" \
           "https://${JIRA_DOMAIN}/rest/api/3/myself" | jq -r '.displayName // ""')
    [ -n "$ME" ] || warn "could not resolve your Jira display name; set JIRA_DISPLAY_NAME in .env"
  fi
  step "assigned rows are those for: ${ME:-<unknown>}"

  : > "${DATA}/jira-links.txt"
  PATCHED="$(mktemp "${TMPDIR:-/tmp}/triage-sprint.XXXXXX")"

  while IFS= read -r line; do
    key=$(printf '%s' "$line" | awk -F' \\| ' '{print $1}')
    assignee=$(printf '%s' "$line" | awk -F' \\| ' '{print $5}')
    work_link=$(printf '%s' "$line" | awk -F' \\| ' '{print $6}' | tr -d ' ')
    mine=false

    # Jira stores some links host-relative ("/project/canvas/-/work_items/N").
    # Complete them with the GitLab host — the path itself is untouched, so a
    # work_items link stays a work_items link.
    if [ -n "$work_link" ] && [ "${work_link#/}" != "$work_link" ]; then
      work_link="https://${GITLAB_HOST}${work_link}"
      line=$(printf '%s' "$line" | awk -F' \\| ' -v OFS=' | ' -v r="$work_link" '{$6=r; print}')
    fi
    [ -n "$ME" ] && [ "$assignee" = "$ME" ] && mine=true

    # Remote-link fallback: only for my own rows that the sprint fetch could
    # not resolve from the description. This replaces the agent's old Step 2.
    if [ "$mine" = true ] && [ -z "$work_link" ]; then
      if links=$("${SCRIPT_DIR}/get_link.sh" "$key" 2>/dev/null); then
        if [ -n "$links" ]; then
          while IFS= read -r url; do
            [ -n "$url" ] && printf '%s | %s\n' "$key" "$url"
          done <<< "$links" | awk '!seen[$0]++' >> "${DATA}/jira-links.txt"
          resolved=$(printf '%s' "$links" | first_work_link)
          if [ -n "$resolved" ]; then
            line=$(printf '%s' "$line" | awk -F' \\| ' -v OFS=' | ' -v r="$resolved" '{$6=r; print}')
            JIRA_RESOLVED=$((JIRA_RESOLVED + 1))
            step "  ${key}: resolved work link from remote links"
          fi
        fi
      else
        warn "get_link.sh failed for ${key}"
      fi
      work_link=$(printf '%s' "$line" | awk -F' \\| ' '{print $6}' | tr -d ' ')
    fi

    # Only my tickets get their issue fetched in detail.
    [ "$mine" = true ] && [ -n "$work_link" ] && printf '%s\n' "$work_link" >> "$TARGETS"

    printf '%s\n' "$line" >> "$PATCHED"
  done < "${DATA}/jira-sprint.txt"

  mv "$PATCHED" "${DATA}/jira-sprint.txt"
fi

# ----------------------------------------------------------------- GitLab ---

step "fetching GitLab work (days=${DAYS}, todo-days=${TODO_DAYS})"
"${REPO_ROOT}/gitlab/fetch-gitlab-work.sh" --days "$DAYS" --todo-days "$TODO_DAYS" \
  > "${DATA}/gitlab-work.txt"
GITLAB_ROWS=$(wc -l < "${DATA}/gitlab-work.txt" | tr -d ' ')

# To-Do / assigned / reviewer rows get detail. `recent` stays titles-only and
# `done:` is already handled work, so neither is fetched.
awk -F' \\| ' '
  $1 ~ /^todo:/ || $1 == "assigned" || $1 == "reviewer" { print $6 }
' "${DATA}/gitlab-work.txt" >> "$TARGETS"

# ----------------------------------------------------------------- detail ---

QUEUE="$(mktemp "${TMPDIR:-/tmp}/triage-queue.XXXXXX")"
awk 'NF && $0 ~ /^https?:\/\// && !seen[$0]++' "$TARGETS" > "$QUEUE"
QUEUED=$(wc -l < "$QUEUE" | tr -d ' ')

if [ "$QUEUED" -gt "$MAX_DETAILS" ]; then
  warn "${QUEUED} issues queued, fetching the first ${MAX_DETAILS} (--max-details)"
  head -n "$MAX_DETAILS" "$QUEUE" > "${QUEUE}.capped" && mv "${QUEUE}.capped" "$QUEUE"
  QUEUED="$MAX_DETAILS"
fi

step "fetching detail for ${QUEUED} issues (jobs=${JOBS})"
: > "${DATA}/issue-index.txt"
if [ "$QUEUED" -gt 0 ]; then
  # One line per issue: URL | file. Failures are reported and skipped; a single
  # unreachable issue must not lose the rest of the day's data.
  xargs -P "$JOBS" -I{} bash -c '
    url="$1"; shift
    if path=$("$0" "$url" "$@" 2>/dev/null); then
      printf "%s | %s\n" "$url" "$path"
    else
      printf "%s | FAILED\n" "$url"
    fi
  ' "${SCRIPT_DIR}/fetch-issue-detail.sh" {} "${DETAIL_ARGS[@]}" < "$QUEUE" \
    | LC_ALL=C sort >> "${DATA}/issue-index.txt" || true
fi
rm -f "$QUEUE"

# grep -c prints 0 and exits 1 when nothing matches, so swallow the status
# rather than appending a second count.
DETAIL_OK=$(grep -cv ' | FAILED$' "${DATA}/issue-index.txt" 2>/dev/null || true)
DETAIL_FAILED=$(grep -c ' | FAILED$' "${DATA}/issue-index.txt" 2>/dev/null || true)
DETAIL_OK=${DETAIL_OK:-0}
DETAIL_FAILED=${DETAIL_FAILED:-0}
[ "$DETAIL_FAILED" -gt 0 ] && warn "${DETAIL_FAILED} issue(s) could not be fetched; see ${DATA}/issue-index.txt"

# ------------------------------------------------------------------- info ---

{
  printf 'fetched: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'flags: open-only=%s refresh=%s days=%s todo-days=%s comments=%s\n' \
    "$OPEN_ONLY" "$REFRESH" "$DAYS" "$TODO_DAYS" "$COMMENTS"
  printf 'jira-sprint rows: %s (work links resolved from remote links: %s)\n' "$JIRA_ROWS" "$JIRA_RESOLVED"
  printf 'gitlab-work rows: %s\n' "$GITLAB_ROWS"
  printf 'issue detail files: %s (failed: %s)\n' "$DETAIL_OK" "$DETAIL_FAILED"
  printf 'issues dir bytes: %s\n' "$(find "$ISSUES" -name '*.md' -type f -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')"
} > "${DATA}/FETCH-INFO.txt"

step "done: ${DATA}"
cat "${DATA}/FETCH-INFO.txt" >&2
