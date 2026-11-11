#!/bin/bash
# Print the shell command that forks the current Claude Code session into a
# new top-level session, ready to paste into another terminal.
#
# Usage: fork-text.sh [session-id]
#
# The session id comes from the first argument (the fork-text skill passes its
# ${CLAUDE_SESSION_ID} substitution) or, failing that, from the
# CLAUDE_CODE_SESSION_ID variable Claude Code exports to the commands it runs.
# That fallback is what lets this run with no skill at all, e.g. from the
# `!` bash prompt inside a session.
#
# The launcher is named after the config dir, matching shell wrappers such as
# claude-mine (CLAUDE_CONFIG_DIR=~/.claude-mine). With no CLAUDE_CONFIG_DIR it
# is plain `claude`. Set FORK_TEXT_LAUNCHER to override either.
set -euo pipefail

session_id="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
if [ -z "$session_id" ]; then
  echo "fork-text: no session id - pass one, or run this inside Claude Code" >&2
  exit 1
fi

if [ -n "${FORK_TEXT_LAUNCHER:-}" ]; then
  launcher="$FORK_TEXT_LAUNCHER"
elif [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  launcher="$(basename "$CLAUDE_CONFIG_DIR")"
  launcher="${launcher#.}"
else
  launcher="claude"
fi

echo "$launcher --resume $session_id --fork-session"
