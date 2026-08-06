#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "ERROR: .env not found. Copy .env.example to .env and fill in values." >&2
  exit 1
fi

source .env

# Derived values
JIRA_BOARD_URL="https://${JIRA_DOMAIN}/jira/software/c/projects/${JIRA_PROJECT}/boards/${JIRA_BOARD_ID}"

# Build sed expression from all config vars
# Template placeholder syntax: __VAR_NAME__ (avoids collision with bash ${} refs)
SED_EXPR=""
for var in JIRA_CLOUD_ID JIRA_DOMAIN JIRA_EMAIL JIRA_PROJECT JIRA_BOARD_ID JIRA_BOARD_URL; do
  val="${!var}"
  # Escape sed special chars in value
  val_escaped=$(printf '%s\n' "$val" | sed 's/[&/\]/\\&/g')
  SED_EXPR="${SED_EXPR}s|__${var}__|${val_escaped}|g;"
done

# Process all .tmpl files
find . -name '*.tmpl' | while read -r tmpl; do
  out="${tmpl%.tmpl}"
  sed "$SED_EXPR" "$tmpl" > "$out"
  # Make shell scripts executable
  [[ "$out" == *.sh ]] && chmod +x "$out"
  # Make extensionless scripts in jira/ executable
  [[ "$out" == ./jira/* && "$out" != *.* ]] && chmod +x "$out"
  echo "  generated: $out"
done

echo "Build complete."
