#!/bin/bash
#
# Print a Jira ticket's remote-link URLs (Jira's "web links" feature), one
# per line. Typically used to find a ticket's linked Drupal.org/GitLab issue
# when its description doesn't already contain the link.
#
# Usage: get_link.sh <ISSUE_KEY>
#   get_link.sh SCP-693
#
# Reads JIRA_DOMAIN, JIRA_EMAIL from the repo's .env.
# Requires JIRA_API_TOKEN in the environment (never stored in .env).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

if [ $# -eq 0 ]; then
  echo "Usage: $(basename "$0") <ISSUE_KEY>" >&2
  exit 1
fi

if [ -z "${JIRA_API_TOKEN:-}" ]; then
  echo "ERROR: JIRA_API_TOKEN not set" >&2
  exit 1
fi

AUTH_HEADER=$(printf '%s' "${JIRA_EMAIL}:${JIRA_API_TOKEN}" | base64)

get_web_links() {
    ISSUE_KEY=$1

    # Hit the specific Remote Link endpoint
    RESPONSE=$(curl -s -H "Authorization: Basic $AUTH_HEADER" \
         -H "Accept: application/json" \
         "https://$JIRA_DOMAIN/rest/api/3/issue/$ISSUE_KEY/remotelink")

    # Check if there's an error
    if echo "$RESPONSE" | jq -e '.errorMessages // empty' > /dev/null 2>&1; then
        ERROR_MSG=$(echo "$RESPONSE" | jq -r '.errorMessages[]?' 2>/dev/null)
        if [ -n "$ERROR_MSG" ]; then
            echo "Error: $ERROR_MSG" >&2
            return 1
        fi
    fi

    # Extract URLs - handle both object.url and just url fields
    echo "$RESPONSE" | jq -r '.[] | if .object then .object.url else .url end // empty'
}

get_web_links "$1"
