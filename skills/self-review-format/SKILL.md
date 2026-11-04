---
name: self-review-format
description: This skill should be used when the user asks to "output in self-review format", "write the review as review.xml", "self-review XML", "make this reviewable in self-review", or when another review skill (review-issue, or any future review skill) is told to emit its findings as a file the self-review desktop app can open. Format only - it does not decide what to review or what to say. Pair it with the skill that produces the findings.
version: 1.0.0
---

# Self-review XML output format

Turn review findings into a `urn:self-review:v3` document that the self-review app
(https://github.com/e0ipso/self-review) opens with `--resume-from`. The *content* of the review
belongs to the calling skill. This skill only fixes the container: file list, line anchoring,
attributes, validation, and the hand-off message.

Keep the calling skill's workflow intact. Replace only its "print a summary" step with the XML
file described here, and skip any "offer to post" step unless the user asks for both.

## 1. Locate the schema

The XSD ships with the `self-review-apply` skill, which may be installed in a per-user config dir
or in the project. Find it at runtime instead of hardcoding a path:

```bash
XSD=$(find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills" .agents/skills .claude/skills \
  -path '*self-review-apply/assets/self-review-v3.xsd' 2>/dev/null | head -1)
```

If `XSD` is empty, tell the user the self-review skills are not installed (they live under
`.agents/skills/` in the self-review repo) and continue without validation. Do not copy the XSD
into this skill; the self-review repo is the single source of truth for it.

When the XSD is present, read its `<xs:documentation>` annotations if anything below is unclear.
The rules below are the ones that matter in practice and are kept in sync with v3.

## 2. Decide the output path and the diff args

- **Output path:** what the user named. Default `review.xml` in the repo root, or the
  `output-file` value from `.self-review.yaml` if that file exists in the repo root.
- **Diff args:** the exact `git diff` arguments the user will pass to the app, for example
  `1.x-workspaces`, `--staged`, `main...HEAD`. Ask if unclear. The calling skill may diff against
  something else (`origin/1.x...HEAD`); the XML must match what the *app* will show, so build the
  file list from the app's args:

```bash
git diff --name-status <diff-args>
```

Untracked files are not in `git diff` but the app lists them. Leave them out of the XML. The app
adds them on load.

Warn the user up front, once, when the output path is not the configured one: the app loads
comments from `--resume-from` but Finish Review and Save & Quit write to the configured
`output-file` (default `review.xml`). Resuming from `agent-review.xml` overwrites `review.xml`
unless they pick another path from the file-tree footer first.

## 3. Join an existing file instead of replacing it

If the output path already exists, read it first. It may hold a human's comments.

- Keep every existing `<file>` and `<comment>` verbatim.
- A finding already present gets a `<reply>` appended to that comment, not a new root comment.
- Never add `severity`, `confidence`, `<category>` or `<suggestion>` to a reply. Put proposed
  code in the reply body as a fenced block.
- Set `author` on every reply. An unauthored reply reads as the human's.

## 4. Document shape

```xml
<?xml version="1.0" encoding="UTF-8"?>
<review xmlns="urn:self-review:v3" timestamp="2026-02-28T14:30:00.000Z" git-diff-args="1.x-workspaces" repository="/absolute/repo/root">
  <file path="src/Foo.php" change-type="modified" viewed="true">
    <comment new-line-start="42" new-line-end="44" author="Claude Fable 5.1" severity="minor" confidence="high">
      <body>Lead with the evidence, then the consequence. One to three sentences.</body>
      <category>bug</category>
      <suggestion>
        <original-code>    $x = $a / $b;</original-code>
        <proposed-code>    $x = $b === 0 ? 0 : $a / $b;</proposed-code>
      </suggestion>
    </comment>
    <comment author="Claude Fable 5.1" severity="info" confidence="medium">
      <body>File-level comment: no line attributes.</body>
      <category>question</category>
    </comment>
  </file>
  <file path="src/Bar.php" change-type="added" viewed="true" />
</review>
```

**`<review>`**
- `timestamp`: `node -e "console.log(new Date().toISOString())"` or `date -u +%Y-%m-%dT%H:%M:%S.000Z`.
- `git-diff-args`: the string from step 2, verbatim.
- `repository`: `git rev-parse --show-toplevel`.

**`<file>`** - one per file in `git diff --name-status`, in that order, including files with no
comments.
- `path`: repo-relative. For renames and copies, the **new** path.
- `change-type`: map the status letter: `A` added, `M` modified, `D` deleted, `R` renamed,
  `C` copied.
- `viewed="true"` on every file you read; `false` only for files you skipped.

**`<comment>`**
- Exactly one line pair: `new-line-start`/`new-line-end` for added or context lines, or
  `old-line-start`/`old-line-end` for deleted lines. Neither pair means file-level. Never both.
- Line numbers are positions in the **new** file (or old file for `old-*`), not diff hunk offsets.
  Verify with `sed -n '42,44p' path` before writing them.
- `author`: your model name, on every comment you write. Omit it only on comments you copied
  from a human's file.
- `severity`: impact **if the finding is real**. `critical` data loss, security hole or crash on
  a reachable path; `major` wrong behavior or broken contract on a reachable path; `minor` real
  but bounded; `info` no defect (style, naming, question).
- `confidence`: how sure you are it **is** real. `high` traceable from code you read, no unseen
  assumption; `medium` rests on one unverified assumption, which the body states; `low`
  speculative. Lowering confidence is the signal working, not a weaker comment.
- Children in this order: `<body>`, `<category>`, optional `<suggestion>`, optional
  `<attachment>`s, then `<reply>`s.
- `<category>`: one of the names in `.self-review.yaml` `categories` if present, else
  `question`, `bug`, `security`, `style`, `task`, `nit`.
- `<suggestion>`: `<original-code>` must be the exact current text at the anchored lines,
  whitespace included, and should occur once in the file. `<proposed-code>` is the full
  replacement. Confirm the match before writing:
  `grep -c -F -- "<first line of original>" path`.
- XML-escape text: `&` `&amp;`, `<` `&lt;`, `>` `&gt;`, `"` `&quot;`, `'` `&apos;`.

**`<reply>`** - flat, never nested, document order is conversation order. Carries `<body>`,
optional `author`, optional `<attachment>`s. Nothing else.

## 5. Write and validate

Write the file, then:

```bash
xmllint --noout --schema "$XSD" <output-path>
```

Fix and re-run until it prints `validates`. If `xmllint` is missing, say so and continue.

Then check anchors mechanically, not by eye: for each comment with a `<suggestion>`, confirm
`original-code` is found at the stated lines. A suggestion that does not match is worse than no
suggestion, because the apply skill will refuse it.

## 6. Hand-off

Print, in this order:
- Output path, file count, comment count by category and by severity.
- Any finding you dropped for lack of evidence, in one line each, so the user knows the file is
  not the whole review.
- The exact command to open it:

```
self-review <diff-args> --resume-from <output-path>
```

- The save-target warning from step 2 if the output path differs from the configured one.

## Related skills

- `self-review-critique` (from the self-review repo): a complete AI review with its own evidence
  bar. Use it when no domain-specific review skill applies. Its "XML Reference" section is the
  upstream of the rules above; when they disagree, the upstream wins and this file needs updating.
- `self-review-apply`: executes the comments in a review file. Owns the XSD this skill validates
  against.
- `self-review-guide`: writes the `review.guide.xml` walkthrough sidecar. Independent of this
  skill; run it only when asked.
