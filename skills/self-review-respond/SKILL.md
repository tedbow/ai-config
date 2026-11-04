---
name: self-review-respond
description: This skill should be used when the user asks to "answer my review replies", "respond to my comments in review.xml", "address my points in the review", "reply to the threads", or has written comments or replies in the self-review app and wants each one answered as a thread turn in the same file. Answers only - it changes no code and raises no new findings. For acting on a curated review use self-review-apply; for a fresh review use review-issue or self-review-critique.
version: 1.1.0
args:
  - name: review-file
    description: Path to the review XML. Defaults to review.xml in the repo root, or the output-file in .self-review.yaml.
    required: false
---

# Answer the human's replies in a self-review file

The user worked through a diff in the self-review app and left comments of their own, replies to
an agent's comments, or both. Nothing in the app posts to GitLab or GitHub, so every human turn in the
file is addressed to the agent: a question, a correction, a note, or a decision. Answer every one,
in the file, as a `<reply>`, so the next time the app opens the thread reads as a conversation.

This skill writes replies and nothing else. No code changes, no new root comments, no edits to
existing comment text. If an answer needs code to move, the reply says what the change would be
and that `self-review-apply` or an explicit request would make it.

XML rules come from the `self-review-format` skill: step 1 for the XSD lookup, step 3 for how a
reply is shaped and attributed. Read that skill first.

## 1. Load the file

Resolve the path from the argument, else `output-file` in `.self-review.yaml`, else `review.xml`
in `git rev-parse --show-toplevel`. Stop if it does not exist. Validate it before touching it, so
a problem you did not cause is reported, not inherited.

## 2. Find the threads that need a turn

Walk every `<comment>`. A reply with no `author` attribute is the human's. Classify each thread:

| Last turn is | Action |
| --- | --- |
| A human reply | Answer it. |
| The agent's own comment or reply, no human reply after it | Skip. Nothing was asked. |
| A human root comment (no `author`), no replies | Answer it. The human wrote it in the app with nobody else to read it, so it is a question or note for you. |
| A human reply you already answered on a previous run | Skip. Document order is conversation order; if an authored reply follows the human's last one, that thread is done. |

A human root comment often has no severity or confidence and may have an empty body with only
a `<suggestion>`. Answer a suggestion-only comment by checking whether its `original-code` still
matches the tree and whether the proposed text is right; say so in one line.

List the threads you will answer before writing anything: file, lines, first words of the human
reply. That is the dry run the user can stop.

## 3. Work out each answer

Read the whole thread top to bottom. Then open the code the thread points at, at the current
working tree, not the diff. The human may have changed it since the comment was written.

- **A question** gets an answer, with the line or call path that supports it. If you do not
  know, say so and say what would settle it.
- **A correction** is evidence your comment was wrong. Check it against the code. If it holds,
  concede in one sentence: what you missed and that the finding is withdrawn. Do not restate
  the original claim in new words.
- **A disagreement you still hold** gets the one piece of evidence the human did not address,
  then stops. Two rounds of the same argument is one too many; after that, the human decides.
- **A decision** ("do it", "leave it", "follow-up issue") gets an acknowledgement and, when it
  asks for code, a reply describing the change and pointing to `self-review-apply`.
- **Already fixed in the tree** gets "fixed at line N by <what>" so the thread closes itself.

Use the thread's own words for things it names. Spell out identifiers and acronyms the first
time. Link anything you have a URL for, as the format skill says; the body is Markdown.

## 4. Write the replies

Append one `<reply author="<your model name>">` with a `<body>` to the end of each answered
comment, after any existing `<attachment>` and `<reply>` children. Change nothing else in the
file: not the timestamp, not `viewed`, not the human's text, not your earlier comments.

XML-escape the body. A fenced code block is fine for a proposed change; a `<suggestion>` is not,
replies cannot carry one.

## 5. Validate and report

Run `xmllint --noout --schema "$XSD" <review-file>` with the XSD from the format skill's lookup.
Fix until it validates.

Then print:

- Threads answered, one line each: file, lines, and conceded / answered / held.
- Threads skipped and why, in one line total if they are all "no human turn".
- Replies that propose a code change, so the user can run `self-review-apply` or ask for them.
- The command to see the result:

```
self-review <diff-args> --resume-from <review-file>
```

`<diff-args>` is the file's `git-diff-args` attribute.

## Related skills

- `self-review-format`: the XML rules this skill follows. Keep this file free of format detail.
- `self-review-apply`: acts on a curated review. Run it after this one when replies asked for
  code. It reads the same threads and treats the last human turn as final.
- `self-review-critique`: a fresh review that also appends replies, but re-reviews the whole
  diff while doing so. Use it when new findings are wanted, this skill when they are not.
