#!/bin/bash
#
# Deterministic GitLab work fetch for the triage data layer.
#
# Collects everything on the user's GitLab plate in one pass and prints clean
# pipe-delimited rows. Agents read these rows; they never call glab themselves.
#
# Touches NO Jira anything — safe to run from the open-source-only profile.
#
# Sources (in dedupe-priority order, most specific first):
#   1. pending To-Dos      /todos?state=pending          SOURCE = todo:action_name
#   2. assigned issues     /issues?scope=assigned_to_me  SOURCE = assigned
#   3. reviewer MRs        /merge_requests?reviewer_...   SOURCE = reviewer
#   4. done To-Dos (N d)   /todos?state=done             SOURCE = done:action_name
#   5. watched projects    /projects/<p>/issues?updated_after=<N days>  SOURCE = recent
#
# Rows are deduped by URL, keeping the most specific SOURCE, then ordered by
# that priority and by UPDATED descending.
#
# Output (one line per item), pipe-delimited:
#   SOURCE | KIND | REF | STATE | UPDATED | URL | TITLE
#
#   SOURCE   why it is on the list (see above). To-Do rows carry a todo:/done:
#            prefix because action_name itself can be "assigned", which would
#            otherwise be indistinguishable from the assigned-to-me scope.
#   KIND     issue | mr | <lowercased GitLab target type>
#   REF      GitLab full reference, e.g. project/canvas#3592103, project/canvas!1802
#   STATE    opened | closed | merged | locked
#   UPDATED  ISO timestamp trimmed to minutes
#   URL      target web_url, VERBATIM — work_items URLs stay work_items URLs
#   TITLE    pipes/tabs/newlines squashed to spaces
#
# Usage: fetch-gitlab-work.sh [--days N] [--todo-days N] [--max-rows N]
#   --days N        window for done To-Dos and watched-project issues (default 2)
#   --todo-days N   window on pending To-Do creation date (default 14). The
#                   To-Do list is a never-expiring backlog — hundreds of rows
#                   going back years — so it is always age-bounded.
#   --max-rows N    hard cap on emitted rows (default 200). Rows are dropped
#                   from the least specific / oldest end, with a warning.
#
# Reads GITLAB_HOST, GITLAB_USERNAME, GITLAB_WATCH_PROJECTS from the repo .env.
# Requires an authenticated `glab` for GITLAB_HOST, plus jq.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../scripts/lib.sh"

DAYS=2
TODO_DAYS=14
MAX_ROWS=200
while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="${2:?--days needs a number}"; shift 2 ;;
    --days=*) DAYS="${1#*=}"; shift ;;
    --todo-days) TODO_DAYS="${2:?--todo-days needs a number}"; shift 2 ;;
    --todo-days=*) TODO_DAYS="${1#*=}"; shift ;;
    --max-rows) MAX_ROWS="${2:?--max-rows needs a number}"; shift 2 ;;
    --max-rows=*) MAX_ROWS="${1#*=}"; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//;$d'; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

for pair in "days:$DAYS" "todo-days:$TODO_DAYS" "max-rows:$MAX_ROWS"; do
  if ! [[ "${pair#*:}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --${pair%%:*} must be a non-negative integer, got: ${pair#*:}" >&2
    exit 1
  fi
done

GITLAB_HOST="${GITLAB_HOST:-git.drupalcode.org}"
if [ -z "${GITLAB_USERNAME:-}" ]; then
  echo "ERROR: GITLAB_USERNAME not set in ${ENV_FILE}" >&2
  exit 1
fi

# BSD date (macOS) first, GNU date second.
iso_days_ago() {
  date -u -v-"$1"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "$1 days ago" +%Y-%m-%dT%H:%M:%SZ
}
CUTOFF="$(iso_days_ago "$DAYS")"
TODO_CUTOFF="$(iso_days_ago "$TODO_DAYS")"

# api <path> [<label>] — print the JSON array, or warn and print [] on failure.
# A single failing source must not lose the rest of the day's rows.
api() {
  local path="$1" label="${2:-$1}" out
  if ! out=$(glab api --hostname "$GITLAB_HOST" --paginate "$path" 2>&1); then
    echo "WARNING: ${label}: glab api failed: ${out}" >&2
    echo '[]'
    return 0
  fi
  if ! printf '%s' "$out" | jq -e -s 'length > 0 and (all(type == "array"))' >/dev/null 2>&1; then
    echo "WARNING: ${label}: unexpected response: $(printf '%s' "$out" | head -c 200)" >&2
    echo '[]'
    return 0
  fi
  printf '%s' "$out"
}

# Shared jq helpers. Emits 4 tab-separated columns so the shell can sort and
# dedupe without re-parsing the pipe row:
#   PRIORITY \t URL \t UPDATED \t "SOURCE | KIND | REF | STATE | UPDATED | URL | TITLE"
JQ_LIB='
  def clean: (. // "") | tostring | gsub("[|\n\r\t]"; " ") | gsub(" {2,}"; " ")
    | sub("^ +"; "") | sub(" +$"; "");
  def kind($t):
    if $t == "MergeRequest" then "mr"
    elif ($t | test("Issue|WorkItem")) then "issue"
    else ($t // "" | ascii_downcase) end;
  def stamp: (. // "") | tostring | .[0:16];
  def row($prio; $source; $kind; $ref; $state; $updated; $url; $title):
    [ ($prio | tostring), $url, $updated,
      ([$source, $kind, $ref, $state, $updated, $url, ($title | clean)] | join(" | "))
    ] | join("\t");
'

rows() {
  # 1. Pending To-Dos, age-bounded (see --todo-days).
  api "todos?state=pending&per_page=100" "pending todos" | jq -r --arg cutoff "$TODO_CUTOFF" "${JQ_LIB}"'
    .[]
    | select(.created_at >= $cutoff)
    | . as $t
    | row(1;
        ("todo:" + ($t.action_name | clean));
        kind($t.target_type);
        ($t.target.references.full // $t.target.reference // "" | clean);
        ($t.target.state // "" | clean);
        (($t.target.updated_at // $t.created_at) | stamp);
        ($t.target.web_url // ($t.target_url | split("#")[0]));
        ($t.target.title // $t.body))
  '

  # 2. Issues assigned to me, anywhere on the host.
  api "issues?scope=assigned_to_me&state=opened&per_page=100" "assigned issues" | jq -r "${JQ_LIB}"'
    .[]
    | row(2; "assigned"; "issue";
        (.references.full | clean); (.state | clean); (.updated_at | stamp);
        .web_url; .title)
  '

  # 3. Open MRs where I am a reviewer.
  api "merge_requests?scope=all&reviewer_username=${GITLAB_USERNAME}&state=opened&per_page=100" "reviewer MRs" \
    | jq -r "${JQ_LIB}"'
    .[]
    | row(3; "reviewer"; "mr";
        (.references.full | clean); (.state | clean); (.updated_at | stamp);
        .web_url; .title)
  '

  # 4. To-Dos I completed inside the window — what I already handled today.
  api "todos?state=done&per_page=100" "done todos" | jq -r --arg cutoff "$CUTOFF" "${JQ_LIB}"'
    .[]
    | select(.created_at >= $cutoff)
    | . as $t
    | row(4;
        ("done:" + ($t.action_name | clean));
        kind($t.target_type);
        ($t.target.references.full // $t.target.reference // "" | clean);
        ($t.target.state // "" | clean);
        (($t.target.updated_at // $t.created_at) | stamp);
        ($t.target.web_url // ($t.target_url | split("#")[0]));
        ($t.target.title // $t.body))
  '

  # 5. Recently touched open issues in the watched projects (titles only —
  #    triage-fetch.sh deliberately does not fetch detail for these).
  for project in $(printf '%s' "${GITLAB_WATCH_PROJECTS:-}" | tr ',' ' '); do
    [ -n "$project" ] || continue
    local encoded
    encoded="${project//\//%2F}"
    api "projects/${encoded}/issues?state=opened&updated_after=${CUTOFF}&per_page=100" "recent ${project}" \
      | jq -r "${JQ_LIB}"'
      .[]
      | row(5; "recent"; "issue";
          (.references.full | clean); (.state | clean); (.updated_at | stamp);
          .web_url; .title)
    '
  done
}

# Lowest priority wins per URL; newest first inside a priority group.
rows \
  | awk -F'\t' 'NF == 4 && $2 != "" && $2 != "null"' \
  | LC_ALL=C sort -t$'\t' -k1,1n -k3,3r \
  | awk -F'\t' '!seen[$2]++' \
  | cut -f4- \
  | awk -v max="$MAX_ROWS" '
      NR <= max { print }
      END { if (NR > max) printf "WARNING: %d rows dropped by --max-rows %d\n", NR - max, max > "/dev/stderr" }
    ' 
