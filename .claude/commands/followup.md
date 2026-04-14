---
description: Append a follow-up Q&A note to an existing guide without rewriting the canonical answer.
---

# /followup

For small additions: a clarification, an edge case, a "but what about X?" — without disturbing the main guide.

## Steps

### 1. Pick the guide

List `guides/*/README.md` and confirm which one this follow-up belongs to.

### 2. Capture the question

Either from the slash command arguments or by asking. Slugify it for the filename.

### 3. Write the follow-up

Create `guides/<slug>/followups/YYYY-MM-DD-<short-topic>.md`:

```markdown
# Follow-up: <question>

**Date:** YYYY-MM-DD
**Parent guide:** [<title>](../README.md)

## Question

<verbatim or paraphrased>

## Answer

<focused answer — assume the reader already read the parent guide>
```

### 4. Link from the parent

Add (or update) a "Follow-ups" section at the bottom of the guide's `README.md`:

```markdown
## Follow-ups

- [YYYY-MM-DD: <short topic>](followups/YYYY-MM-DD-<short-topic>.md)
```

### 5. Commit

```bash
git add -A
git commit -m "Follow-up on <slug>: <short topic>"
git push
```
