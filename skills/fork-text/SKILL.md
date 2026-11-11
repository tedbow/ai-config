---
name: fork-text
description: Print the shell command that forks the current session into a new top-level session in another terminal.
disable-model-invocation: true
allowed-tools: Bash(*/fork-text/fork-text.sh *)
---

# Fork Text

The command below was produced by `fork-text.sh` before this prompt reached
you. Reply with that one line in a fenced `bash` code block and nothing else:
no introduction, no explanation, no follow-up question. Do not run it.

!`${CLAUDE_SKILL_DIR}/fork-text.sh ${CLAUDE_SESSION_ID}`
