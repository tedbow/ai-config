#!/bin/bash
#
# Deterministic per-issue detail fetch for the triage data layer.
#
# One entry point for every issue flavour the triage touches. Dispatches on the
# URL shape, writes ONE compact markdown file per issue, and bounds its own
# output so an agent can read a dozen of them without blowing up its context.
# Agents read these files; they never run the underlying CLIs themselves.
#
# Usage: fetch-issue-detail.sh <url-or-number> [options]
#   <url-or-number>   one of:
#       3591909                                   bare Drupal.org issue number
#       https://drupal.org/i/3591909              Drupal.org issue (also /node/N,
#                                                 /project/X/issues/N)
#       https://git.drupalcode.org/project/canvas/-/work_items/3592103
#       https://git.drupalcode.org/project/canvas/-/issues/3592103
#       https://git.drupalcode.org/project/canvas/-/merge_requests/1802
#       https://github.com/owner/repo/pull/42
#   --out DIR         output directory (default $TRIAGE_ROOT/<today>/data/issues)
#   --comments N      keep only the last N comments (default 5)
#   --refresh         refetch even when the file is still fresh
#   --max-age MIN     treat a file younger than MIN minutes as fresh (default 720)
#   --include-bots    keep drupalbot's "Issue tools:" / "Fork created:" banner
#                     comments, which are dropped by default so they do not eat
#                     the comment budget
#   --print-path      print only the output path, no progress on stderr
#
# Prints the output path on stdout. Exits non-zero only when it wrote nothing.
#
# Bounding rules (all deterministic):
#   - issue/MR description capped at 12000 chars
#   - at most N comments, each capped at 3000 chars
#   - at most 10 related MRs listed, pipeline status fetched for the first 3
#
# URLs are reproduced VERBATIM from the source: a /-/work_items/ URL is never
# rewritten to drupal.org/i/ or vice versa.
#
# Requires: drupalorg, glab (authenticated), gh, jq.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

TARGET=""
OUT_DIR=""
COMMENTS=5
REFRESH=false
MAX_AGE=720
QUIET=false
INCLUDE_BOTS=false

DESC_MAX=12000
CMT_MAX=3000
MR_MAX=10
MR_PIPELINE_MAX=3

while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT_DIR="${2:?--out needs a directory}"; shift 2 ;;
    --out=*) OUT_DIR="${1#*=}"; shift ;;
    --comments) COMMENTS="${2:?--comments needs a number}"; shift 2 ;;
    --comments=*) COMMENTS="${1#*=}"; shift ;;
    --max-age) MAX_AGE="${2:?--max-age needs a number}"; shift 2 ;;
    --max-age=*) MAX_AGE="${1#*=}"; shift ;;
    --refresh) REFRESH=true; shift ;;
    --include-bots) INCLUDE_BOTS=true; shift ;;
    --print-path) QUIET=true; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//;$d'; exit 0 ;;
    -*) echo "ERROR: unknown option: $1" >&2; exit 1 ;;
    *) if [ -n "$TARGET" ]; then echo "ERROR: unexpected argument: $1" >&2; exit 1; fi
       TARGET="$1"; shift ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "Usage: $(basename "$0") <url-or-number> [--out DIR] [--comments N] [--refresh]" >&2
  exit 1
fi

TRIAGE_ROOT="${TRIAGE_ROOT:-$HOME/triage}"
OUT_DIR="${OUT_DIR:-${TRIAGE_ROOT}/$(date +%F)/data/issues}"
GITLAB_HOST="${GITLAB_HOST:-git.drupalcode.org}"

note() { [ "$QUIET" = true ] || echo "$*" >&2; }

# ---------------------------------------------------------------- dispatch ---

TYPE=""
NID=""; GL_HOST=""; GL_PROJECT=""; GL_IID=""
GH_OWNER=""; GH_REPO=""; GH_NUM=""

if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  TYPE=drupal_issue; NID="$TARGET"
elif [[ "$TARGET" =~ ^https?://(www\.)?drupal\.org/i/([0-9]+) ]]; then
  TYPE=drupal_issue; NID="${BASH_REMATCH[2]}"
elif [[ "$TARGET" =~ ^https?://(www\.)?drupal\.org/node/([0-9]+) ]]; then
  TYPE=drupal_issue; NID="${BASH_REMATCH[2]}"
elif [[ "$TARGET" =~ ^https?://(www\.)?drupal\.org/project/[^/]+/issues/([0-9]+) ]]; then
  TYPE=drupal_issue; NID="${BASH_REMATCH[2]}"
elif [[ "$TARGET" =~ ^https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  TYPE=github_pr; GH_OWNER="${BASH_REMATCH[1]}"; GH_REPO="${BASH_REMATCH[2]}"; GH_NUM="${BASH_REMATCH[3]}"
elif [[ "$TARGET" =~ ^https?://([^/]+)/(.+)/-/merge_requests/([0-9]+) ]]; then
  TYPE=gitlab_mr; GL_HOST="${BASH_REMATCH[1]}"; GL_PROJECT="${BASH_REMATCH[2]}"; GL_IID="${BASH_REMATCH[3]}"
elif [[ "$TARGET" =~ ^https?://([^/]+)/(.+)/-/(work_items|issues)/([0-9]+) ]]; then
  TYPE=gitlab_issue; GL_HOST="${BASH_REMATCH[1]}"; GL_PROJECT="${BASH_REMATCH[2]}"; GL_IID="${BASH_REMATCH[4]}"
else
  echo "ERROR: unrecognised issue reference: $TARGET" >&2
  exit 1
fi

slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//'; }

case "$TYPE" in
  drupal_issue) SLUG="drupal-${NID}" ;;
  gitlab_issue) SLUG="$(slugify "${GL_PROJECT}")-${GL_IID}" ;;
  gitlab_mr)    SLUG="$(slugify "${GL_PROJECT}")-mr-${GL_IID}" ;;
  github_pr)    SLUG="github-$(slugify "${GH_OWNER}-${GH_REPO}")-pr-${GH_NUM}" ;;
esac

OUT_FILE="${OUT_DIR}/${SLUG}.md"
mkdir -p "$OUT_DIR"

if [ "$REFRESH" != true ] && [ -s "$OUT_FILE" ] \
   && [ -n "$(find "$OUT_FILE" -maxdepth 0 -mmin "-${MAX_AGE}" 2>/dev/null)" ]; then
  note "fresh, skipping: ${OUT_FILE}"
  printf '%s\n' "$OUT_FILE"
  exit 0
fi

# ---------------------------------------------------------------- helpers ---

urlenc_path() { printf '%s' "$1" | sed 's|/|%2F|g'; }

gl() { # gl <host> <path> — JSON array/object, or empty on failure
  local host="$1" path="$2" out
  if ! out=$(glab api --hostname "$host" "$path" 2>&1); then
    note "WARNING: glab api ${path} failed: $(printf '%s' "$out" | head -c 200)"
    return 1
  fi
  printf '%s' "$out"
}

# cap_region <open-regex> <close-regex> <max-chars> <marker>
cap_region() {
  awk -v o="$1" -v c="$2" -v max="$3" -v marker="$4" '
    !inr && $0 ~ o { print; inr = 1; cnt = 0; cut = 0; next }
    inr  && $0 ~ c { if (cut) print marker; print; inr = 0; next }
    inr {
      if (cut) next
      cnt += length($0) + 1
      if (cnt > max) { cut = 1; next }
      print; next
    }
    { print }
  '
}

# keep_last_comments <keep> <per-comment-max> — trims the <comments> block of
# drupalorg's llm output to the last N comments. Comment groups there are flat:
# each starts with a <number> line.
keep_last_comments() {
  awk -v keep="$1" -v percmt="$2" '
    /^[[:space:]]*<comments>[[:space:]]*$/ { print; inc = 1; n = 0; next }
    inc && /^[[:space:]]*<\/comments>[[:space:]]*$/ {
      start = (n > keep) ? n - keep : 0
      if (start > 0) printf "    [... %d earlier comments omitted; last %d kept ...]\n", start, keep
      for (i = start + 1; i <= n; i++) {
        printf "%s", g[i]
        if (trunc[i]) print "    [... comment truncated ...]"
      }
      print; inc = 0; next
    }
    inc {
      if ($0 ~ /^[[:space:]]*<number>/) { n++; len[n] = 0 }
      if (n == 0) next
      if (len[n] > percmt) { trunc[n] = 1; next }
      g[n] = g[n] $0 "\n"; len[n] += length($0) + 1
      next
    }
    { print }
  '
}

xml_field() { # xml_field <tag> < input
  sed -n "s|^[[:space:]]*<$1>\(.*\)</$1>[[:space:]]*$|\1|p" | head -1
}

# Render a GitLab MR JSON array as compact one-line-per-MR rows.
mr_rows() {
  jq -r --argjson max "$MR_MAX" '
    def pipe: (.head_pipeline.status // .pipeline.status // "unknown");
    (if type == "array" then . else [.] end)
    | ( [ .[] | select(.state == "opened") ] | sort_by(.updated_at // "") | reverse )
      + ( [ .[] | select(.state != "opened") ] | sort_by(.updated_at // "") | reverse )
    | .[0:$max] | .[]
    | "- \(.references.full // .reference // ("!" + (.iid|tostring)))"
      + " | \(.state)\(if .draft then " (draft)" else "" end)"
      + " | pipeline: \(pipe)"
      + " | merge: \(.detailed_merge_status // .merge_status // "?")"
      + " | \(.source_branch) -> \(.target_branch)"
      + " | \(.web_url)"
      + "\n  \(.title)"
  '
}

# Render GitLab notes (newest-first input) as the last N human comments,
# oldest-first, each capped.
note_rows() {
  jq -r --argjson keep "$COMMENTS" --argjson cap "$CMT_MAX" --argjson bots "$INCLUDE_BOTS" '
    (if type == "array" then . else [] end)
    | map(select((.system | not) and ((.body // "") | length) > 0))
    | map(select($bots or ((.author.username // "") != "drupalbot")
                       or ((.body // "") | startswith(">>> [!note]") | not)))
    | (length) as $total
    | .[0:$keep] | reverse
    | if $total == 0 then "none" else
        (if $total > $keep then "[... \($total - $keep) earlier comments omitted; last \($keep) kept ...]\n" else "" end)
        + (map("### \(.created_at[0:16]) \(.author.username // "?")\n"
               + (if ((.body | length) > $cap) then (.body[0:$cap] + "\n[... comment truncated ...]") else .body end)
              ) | join("\n\n"))
      end
  '
}

TMP="$(mktemp "${TMPDIR:-/tmp}/fetch-issue-detail.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

FETCHED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---------------------------------------------------------------- fetchers ---

fetch_drupal_issue() {
  # Classic Drupal.org issue. drupalorg's llm format carries description AND
  # comments for these (unlike GitLab work items), so one call does it.
  # do.php info is deliberately NOT used: it aborts on these issues
  # (IssueInfo.php:68, unrelated pre-existing bug).
  local raw project title state
  if ! raw=$(drupalorg issue:show "$NID" --format=llm --with-comments 2>&1); then
    echo "ERROR: drupalorg issue:show $NID failed: $(printf '%s' "$raw" | head -c 300)" >&2
    return 1
  fi
  project=$(printf '%s\n' "$raw" | xml_field project)
  title=$(printf '%s\n' "$raw" | xml_field title)
  state=$(printf '%s\n' "$raw" | xml_field status)

  {
    printf '# %s\n\n' "${title:-drupal.org issue ${NID}}"
    printf -- '- Source: drupal.org issue\n'
    printf -- '- URL: https://drupal.org/i/%s\n' "$NID"
    printf -- '- Project: %s\n' "${project:-unknown}"
    printf -- '- Status: %s\n' "${state:-unknown}"
    printf -- '- Fetched: %s\n\n' "$FETCHED"

    printf '## Merge requests\n\n'
    if [ -n "$project" ]; then
      # Drupal core/contrib MRs for a classic issue live in the project repo on
      # branches named after the issue number, so search the project for it.
      local enc search mrs
      enc="$(urlenc_path "project/${project}")"
      if search=$(gl "$GITLAB_HOST" "projects/${enc}/search?scope=merge_requests&search=${NID}"); then
        mrs=$(printf '%s' "$search" | jq --arg nid "$NID" '
          [ .[] | select((.source_branch // "" | test("(^|[^0-9])" + $nid + "([^0-9]|$)"))
                         or (.title // "" | test("(^|[^0-9])" + $nid + "([^0-9]|$)"))) ]')
        if [ "$(printf '%s' "$mrs" | jq 'length')" -gt 0 ]; then
          # Pipeline status needs a per-MR call; cap how many we spend.
          local enriched i iid full
          enriched='[]'
          i=0
          while IFS= read -r iid; do
            [ -n "$iid" ] || continue
            if [ "$i" -lt "$MR_PIPELINE_MAX" ] && full=$(gl "$GITLAB_HOST" "projects/${enc}/merge_requests/${iid}"); then
              enriched=$(printf '%s' "$enriched" | jq --argjson m "$full" '. + [$m]')
            else
              enriched=$(printf '%s' "$enriched" | jq --argjson m "$(printf '%s' "$mrs" | jq --argjson iid "$iid" '[.[] | select(.iid == $iid)][0]')" '. + [$m]')
            fi
            i=$((i + 1))
          done < <(printf '%s' "$mrs" | jq -r '.[].iid')
          printf '%s' "$enriched" | mr_rows
        else
          printf 'none found\n'
        fi
      else
        printf 'lookup failed\n'
      fi
    else
      printf 'project unknown, skipped\n'
    fi
    printf '\n'

    printf '## Issue\n\n'
    printf '%s\n' "$raw" \
      | cap_region '^[[:space:]]*<description>' '^[[:space:]]*</description>' "$DESC_MAX" '[... description truncated ...]' \
      | keep_last_comments "$COMMENTS" "$CMT_MAX"
  } > "$TMP"
}

fetch_gitlab_issue() {
  local enc json title state updated url body
  enc="$(urlenc_path "$GL_PROJECT")"
  if ! json=$(gl "$GL_HOST" "projects/${enc}/issues/${GL_IID}"); then
    echo "ERROR: could not read ${GL_PROJECT}#${GL_IID} on ${GL_HOST}" >&2
    return 1
  fi
  title=$(printf '%s' "$json" | jq -r '.title // ""')
  state=$(printf '%s' "$json" | jq -r '.state // ""')
  updated=$(printf '%s' "$json" | jq -r '(.updated_at // "")[0:16]')
  # web_url from the API, used verbatim — it is the work_items form for
  # migrated Drupal.org queues and must stay that way.
  url=$(printf '%s' "$json" | jq -r '.web_url // ""')

  {
    printf '# %s\n\n' "${title:-${GL_PROJECT}#${GL_IID}}"
    printf -- '- Source: gitlab issue (%s)\n' "$GL_HOST"
    printf -- '- Ref: %s\n' "$(printf '%s' "$json" | jq -r '.references.full // ""')"
    printf -- '- URL: %s\n' "${url:-$TARGET}"
    printf -- '- State: %s\n' "${state:-unknown}"
    printf -- '- Updated: %s\n' "$updated"
    printf -- '- Labels: %s\n' "$(printf '%s' "$json" | jq -r '(.labels // []) | join(", ")')"
    printf -- '- Assignees: %s\n' "$(printf '%s' "$json" | jq -r '[(.assignees // [])[].username] | join(", ")')"
    printf -- '- Fetched: %s\n\n' "$FETCHED"

    printf '## Merge requests\n\n'
    local related
    if related=$(gl "$GL_HOST" "projects/${enc}/issues/${GL_IID}/related_merge_requests"); then
      if [ "$(printf '%s' "$related" | jq 'length')" -gt 0 ]; then
        # related_merge_requests already embeds head_pipeline — no extra calls.
        printf '%s' "$related" | mr_rows
      else
        printf 'none\n'
      fi
    else
      printf 'lookup failed\n'
    fi
    printf '\n'

    printf '## Issue\n\n'
    # drupalorg renders drupalcode issues in its llm shape, which is tighter
    # than raw API JSON; fall back to the API description elsewhere.
    body=""
    if [ "$GL_HOST" = "git.drupalcode.org" ]; then
      body=$(drupalorg issue:show "${url:-$TARGET}" --format=llm 2>/dev/null || true)
    fi
    if [ -n "$body" ]; then
      printf '%s\n' "$body" \
        | cap_region '^[[:space:]]*<description>' '^[[:space:]]*</description>' "$DESC_MAX" '[... description truncated ...]'
    else
      printf '%s\n' "$(printf '%s' "$json" | jq -r '.description // "(no description)"')" | head -c "$DESC_MAX"
      printf '\n'
    fi
    printf '\n'

    # GitLab work items keep their discussion in notes; drupalorg --with-comments
    # does not return them, so read them straight from the API.
    printf '## Comments (last %s)\n\n' "$COMMENTS"
    local notes
    if notes=$(gl "$GL_HOST" "projects/${enc}/issues/${GL_IID}/notes?per_page=100&sort=desc&order_by=created_at"); then
      printf '%s' "$notes" | note_rows
    else
      printf 'lookup failed\n'
    fi
    printf '\n'
  } > "$TMP"
}

fetch_gitlab_mr() {
  local enc json url
  enc="$(urlenc_path "$GL_PROJECT")"
  if ! json=$(gl "$GL_HOST" "projects/${enc}/merge_requests/${GL_IID}"); then
    echo "ERROR: could not read ${GL_PROJECT}!${GL_IID} on ${GL_HOST}" >&2
    return 1
  fi
  url=$(printf '%s' "$json" | jq -r '.web_url // ""')

  {
    printf '# %s\n\n' "$(printf '%s' "$json" | jq -r '.title // ""')"
    printf -- '- Source: gitlab merge request (%s)\n' "$GL_HOST"
    printf -- '- URL: %s\n' "${url:-$TARGET}"
    printf -- '- Fetched: %s\n\n' "$FETCHED"
    printf '## Merge request\n\n'
    printf '%s' "$json" | mr_rows
    printf '\n'
    printf -- '- Author: %s\n' "$(printf '%s' "$json" | jq -r '.author.username // ""')"
    printf -- '- Reviewers: %s\n' "$(printf '%s' "$json" | jq -r '[(.reviewers // [])[].username] | join(", ")')"
    printf -- '- Changed files: %s\n' "$(printf '%s' "$json" | jq -r '.changes_count // "?"')"
    printf -- '- Conflicts: %s\n' "$(printf '%s' "$json" | jq -r 'if .has_conflicts then "yes" else "no" end')"
    printf -- '- Pipeline: %s (%s)\n\n' \
      "$(printf '%s' "$json" | jq -r '.head_pipeline.status // "unknown"')" \
      "$(printf '%s' "$json" | jq -r '.head_pipeline.web_url // "-"')"

    printf '## Description\n\n'
    printf '%s\n' "$(printf '%s' "$json" | jq -r '.description // "(none)"')" | head -c "$DESC_MAX"
    printf '\n\n'

    printf '## Comments (last %s)\n\n' "$COMMENTS"
    local notes
    if notes=$(gl "$GL_HOST" "projects/${enc}/merge_requests/${GL_IID}/notes?per_page=100&sort=desc&order_by=created_at"); then
      printf '%s' "$notes" | note_rows
    else
      printf 'lookup failed\n'
    fi
    printf '\n'
  } > "$TMP"
}

fetch_github_pr() {
  local json
  if ! json=$(gh pr view "$TARGET" --json \
      number,title,state,isDraft,url,author,reviewDecision,statusCheckRollup,headRefName,baseRefName,updatedAt,mergeable,changedFiles,body,comments,reviews \
      2>&1); then
    echo "ERROR: gh pr view $TARGET failed: $(printf '%s' "$json" | head -c 300)" >&2
    return 1
  fi

  {
    printf '%s' "$json" | jq -r --argjson keep "$COMMENTS" --argjson cap "$CMT_MAX" --argjson desc "$DESC_MAX" --arg fetched "$FETCHED" '
      "# \(.title)\n",
      "- Source: github pull request",
      "- URL: \(.url)",
      "- State: \(.state)\(if .isDraft then " (draft)" else "" end)",
      "- Author: \(.author.login // "?")",
      "- Review decision: \(.reviewDecision // "none")",
      "- Mergeable: \(.mergeable // "?")",
      "- Branches: \(.headRefName) -> \(.baseRefName)",
      "- Changed files: \(.changedFiles // "?")",
      "- Updated: \((.updatedAt // "")[0:16])",
      "- Fetched: \($fetched)\n",
      "## Checks\n",
      ( [ (.statusCheckRollup // [])[]
          | "- \(.name // .context // "?"): \(.conclusion // .state // "?")" ]
        | if length == 0 then ["none"] else . end | .[] ),
      "\n## Reviews\n",
      ( [ (.reviews // [])[] | "- \(.author.login // "?"): \(.state)" ]
        | if length == 0 then ["none"] else . end | .[] ),
      "\n## Description\n",
      ((.body // "(none)") | if (length > $desc) then (.[0:$desc] + "\n[... description truncated ...]") else . end),
      "\n## Comments (last \($keep))\n",
      ( (.comments // []) as $all
        | ($all | length) as $total
        | (if $total > $keep then "[... \($total - $keep) earlier comments omitted; last \($keep) kept ...]\n" else "" end)
          + ( ($all | .[-$keep:] | map("### \((.createdAt // "")[0:16]) \(.author.login // "?")\n"
                 + ((.body // "") | if (length > $cap) then (.[0:$cap] + "\n[... comment truncated ...]") else . end)))
              | if length == 0 then ["none"] else . end | join("\n\n") ) )
    '
  } > "$TMP"
}

case "$TYPE" in
  drupal_issue) fetch_drupal_issue ;;
  gitlab_issue) fetch_gitlab_issue ;;
  gitlab_mr)    fetch_gitlab_mr ;;
  github_pr)    fetch_github_pr ;;
esac

if [ ! -s "$TMP" ]; then
  echo "ERROR: produced no content for $TARGET" >&2
  exit 1
fi

mv "$TMP" "$OUT_FILE"
trap - EXIT
note "wrote ${OUT_FILE} ($(wc -c < "$OUT_FILE" | tr -d ' ') bytes)"
printf '%s\n' "$OUT_FILE"
