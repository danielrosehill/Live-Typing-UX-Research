---
description: Append a dated follow-up section to an existing ideas/<slug>.md without rewriting the canonical response.
---

# /followup

For small additions: a clarification, an edge case, a "but what about X?" — without disturbing the main response.

## Steps

### 1. Pick the topic

List `ideas/*.md` and confirm which one this follow-up belongs to.

### 2. Capture the question

Either from the slash command arguments or by asking.

### 3. Append the follow-up section

Append (do not rewrite) a dated section at the bottom of `ideas/<slug>.md`:

```markdown
## Follow-up — YYYY-MM-DD: <short topic>

**Question:** <verbatim or paraphrased>

<focused answer — assume the reader already read everything above>
```

If multiple follow-ups accumulate, they stack chronologically — newest at the bottom.

### 4. Optional: note in the question file

If the follow-up represents a genuinely new sub-question (not just a clarification), append a short bullet to `questions/<slug>.md` so the question half stays representative of what's actually been asked:

```markdown
## Follow-up questions

- DD/MM/YY — <one-line restatement of the new sub-question>
```

### 5. Commit

```bash
git add -A
git commit -m "Follow-up on <slug>: <short topic>"
git push
```
