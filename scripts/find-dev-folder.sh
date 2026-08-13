#!/bin/bash
#
# Find local dev folder(s) under SITES_DIR whose name contains any of the
# given search terms (case-insensitive, whole-token match). Terms are plain
# strings — this script doesn't know or care whether they're Jira keys,
# Drupal.org issue numbers, or anything else.
#
# Direct/interactive use: prompts to pick a folder (if more than one match)
# then drops you into a subshell cd'd into it — type `exit` to return.
#   find-dev-folder.sh SCP-693
#   find-dev-folder.sh SCP-693 3591909
#
# --list: just print matching paths, one per line, no prompt/subshell.
# Always used by the find-dev-folder skill.
#   find-dev-folder.sh --list SCP-693
#
# Reads SITES_DIR from the repo's .env.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found. Copy .env.example to .env and fill in values." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

LIST_ONLY=false
if [ "${1:-}" == "--list" ]; then
  LIST_ONLY=true
  shift
fi

if [ $# -eq 0 ]; then
  echo "Usage: $(basename "$0") [--list] <term> [<term> ...]" >&2
  exit 1
fi

if [ ! -d "${SITES_DIR:-}" ]; then
  echo "ERROR: SITES_DIR not found or not set: ${SITES_DIR:-<unset>}" >&2
  exit 1
fi

shopt -s nocasematch
MATCHES=()
for dir in "$SITES_DIR"/*/; do
  name=$(basename "$dir")
  for term in "$@"; do
    if [[ "$name" =~ (^|[^0-9A-Za-z])${term}([^0-9A-Za-z]|$) ]]; then
      MATCHES+=("${dir%/}")
      break
    fi
  done
done
shopt -u nocasematch

if [ ${#MATCHES[@]} -eq 0 ]; then
  echo "No matching folder found in $SITES_DIR for: $*" >&2
  exit 1
fi

SORTED=()
while IFS= read -r line; do
  SORTED+=("$line")
done < <(printf '%s\n' "${MATCHES[@]}" | sort)
MATCHES=("${SORTED[@]}")

if [ "$LIST_ONLY" = true ] || [ ! -t 0 ]; then
  printf '%s\n' "${MATCHES[@]}"
  exit 0
fi

if [ ${#MATCHES[@]} -eq 1 ]; then
  TARGET="${MATCHES[0]}"
else
  echo "Multiple matches:" >&2
  for i in "${!MATCHES[@]}"; do
    printf '  %d) %s\n' "$((i + 1))" "${MATCHES[$i]}" >&2
  done
  read -rp "Select directory (number): " choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#MATCHES[@]} ]; then
    echo "Invalid selection." >&2
    exit 1
  fi
  TARGET="${MATCHES[$((choice - 1))]}"
fi

echo "Entering $TARGET (type 'exit' to return)" >&2
cd "$TARGET"
exec "${SHELL:-/bin/bash}"
