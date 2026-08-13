# Shared by scripts/*.sh: locate and source the repo's .env file. Sets
# $REPO_ROOT plus everything defined in .env (SITES_DIR, JIRA_DOMAIN,
# JIRA_EMAIL, etc). JIRA_API_TOKEN is never stored in .env — it's a
# runtime secret, expected to already be exported in the shell.
#
# Source this, don't execute it:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found. Copy .env.example to .env and fill in values." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"
