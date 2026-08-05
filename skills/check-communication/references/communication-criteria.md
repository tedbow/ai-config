# Communication Readiness Criteria

Apply these checks to any ticket, PR, or issue. Each check has a **pass condition** — if it isn't met, flag it with the specific gap found and a concrete suggestion.

---

## Clarity Checks

**Root cause documented**
- Pass: The content explicitly states *why* the problem happens, not just what the symptom is. "503 error on save" is a symptom. "TMGMT introduces trailing whitespace on URI fields; Canvas's field processor doesn't trim before validation" is a root cause.
- Common failure: Description jumps straight from symptom to solution with no explanation of the mechanism.

**Scope explicit**
- Pass: Content states what this work addresses AND, if multiple symptoms were reported, which ones are in scope and which are not (or are addressed elsewhere).
- Common failure: Ticket reports two issues; PR only addresses one; no mention of the other.

**Multiple symptoms handled**
- Pass: If multiple symptoms are present, there's explicit confirmation of whether they share a root cause or are independent — and where each is resolved.
- Common failure: "Issue 2 was fixed" with no link to where or how.

---

## Evidence Integrity Checks

**Cited links self-explanatory**
- Pass: Any comment, commit, or ticket linked as evidence actually says what the author claims it says. Fetch and read the linked content; do not just note that a link exists.
- Common failure: Author links a comment saying "it works now" as proof that a specific person made a specific fix. The comment doesn't say either of those things. The author's memory fills the gap, but the reader's cannot.

**"Fixed elsewhere" traceable**
- Pass: If a symptom is described as "resolved elsewhere" or "fixed by someone else," there is a pointer to the actual artifact: a commit SHA, a PR/MR URL, a config change with a description.
- Common failure: "Ankitha fixed this, as noted by Vipin [link to Vipin's comment]." Vipin's comment doesn't name Ankitha or describe a fix.

---

## Freshness Checks (PRs/MRs only)

**Description matches current code**
- Pass: The PR description does not reference code, hooks, files, or behavior that no longer exists in the current diff.
- Common failure: Description was written for an earlier version of the PR; code was changed but description wasn't updated. Look for function names, file names, or behaviors mentioned in the description that don't appear in the diff.

**Title matches scope**
- Pass: The PR title describes what the PR actually does, not a broader or earlier version of the work.
- Common failure: Title says "Fix page translation issue" but the PR only addresses one specific cause (URI whitespace) of one of two reported symptoms.

---

## Reader Perspective Checks

**Cold reader test**
- Pass: Someone who knows nothing about this ticket's history and has not read any prior discussion can understand: what was broken, why, what this work does to fix it, and what (if anything) is out of scope.
- Apply this test: Imagine the reader just joined the team yesterday. Would they need to ask follow-up questions to understand the scope and approach? Every "yes" is a gap.

**No assumption of shared context**
- Pass: The content doesn't rely on the reader already knowing the outcome of verbal conversations, Slack messages, or prior states of the demo site.
- Common failure: "The site is now working" with no explanation of what changed between "broken" and "working."
