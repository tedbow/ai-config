---
name: Communication Readiness Check
description: This skill should be used when the user asks to "communication check", "check communication", "check PR description", "check ticket clarity", "ready to request review", "is this ready to submit", "self-review check", or wants to verify that a ticket, PR, or issue is clearly written for a cold reader — checking communication quality, not code correctness. Does NOT perform code review — for code review use review-issue.
version: 1.0.0
args:
  - name: target
    description: URL or identifier for the work item to check. Accepts GitHub PR URLs (github.com/.../pull/N), GitLab MR/issue URLs, Jira ticket keys (e.g. SCP-691) or URLs, Drupal.org issue URLs (drupal.org/i/N), or any similar identifier.
    required: true
---

# Communication Readiness Check Skill

You are checking whether a ticket, PR, or issue communicates clearly to a cold reader — someone with no prior context. This is not a code review. You are looking for gaps in explanation, stale descriptions, and unsupported claims.

## Workflow

### 1. Fetch the content

Fetch the target using whatever tools are appropriate for the platform. Use the full content: title, description, and all comments.

**Critical**: Also fetch any linked items cited as evidence — linked comments, linked tickets, referenced commits. You must read what those links actually say, not just note that a link exists. The most common failure pattern is an author linking something that doesn't say what they claim it does.

### 2. Apply communication checks

Read `${CLAUDE_PLUGIN_ROOT}/skills/check-communication/references/communication-criteria.md` and apply every check to the fetched content.

For each **cited link**, fetch the target and compare what it actually says against what the author claims it says. Note any gap.

For **PRs and MRs**, also fetch the diff to check whether the description references code or behavior that no longer exists.

### 3. Produce the readiness report

Output a structured report using this template:

```
## Communication Readiness: {{identifier}}

**Verdict**: Ready | Needs Work | Blocked

> Ready — all checks pass
> Needs Work — one or more gaps found, but a reader could piece together the story
> Blocked — critical information missing; a reviewer cannot evaluate scope or intent without asking follow-up questions

### Checks

| Check | Result | Gap |
|-------|--------|-----|
| Root cause documented | ✅ / ❌ | [specific gap or "—"] |
| Scope explicit | ✅ / ❌ | |
| Multiple symptoms handled | ✅ / ❌ / N/A | |
| Cited links self-explanatory | ✅ / ❌ / N/A | |
| "Fixed elsewhere" traceable | ✅ / ❌ / N/A | |
| Description matches current code | ✅ / ❌ / N/A | |
| Title matches scope | ✅ / ❌ / N/A | |
| Cold reader test | ✅ / ❌ | |
| No assumption of shared context | ✅ / ❌ | |

### Suggested fixes

[For each ❌ check, one concrete suggestion. Be specific — show exactly what sentence or paragraph to add, change, or remove. Don't say "improve the description"; say what to write.]
```

Mark a check N/A only when it genuinely doesn't apply (e.g. "Description matches current code" is N/A for a Jira ticket with no associated PR).

### 4. Offer to post

After displaying the report, use AskUserQuestion to ask whether to post it:

```
options:
  - label: "Keep local"
    description: "Don't post anywhere — for your own review only"
  - label: "Post as comment"
    description: "Post the report as a comment on the ticket or PR"
```

If the user chooses to post, add the report as a comment using the appropriate tool for the platform.

## Error Handling

- **Can't fetch target**: Tell the user what you tried, ask them to verify the URL or identifier.
- **Can't fetch a cited link**: Note in the report that the link couldn't be verified and flag it as a potential gap.
- **No target provided**: Ask the user for the URL or identifier.
- **PR diff unavailable**: Skip the "Description matches current code" check and mark it N/A; note that the diff couldn't be fetched.

## Tips

- The "Cited links self-explanatory" check is the most important and most commonly missed. Always fetch and read linked content.
- Phrase suggested fixes as additions the author can make without rewriting everything — most gaps are missing sentences, not wrong ones.
- The goal is to help the author see their own blind spots, not to criticize. Keep the report factual and specific.
- If all checks pass, say so clearly — "Ready" is a valid and useful verdict.
