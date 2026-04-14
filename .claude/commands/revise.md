---
description: Update the response in ideas/<slug>.md with new findings, snapshotting the previous version.
---

# /revise

Substantial rewrite of an existing ideas file. Use `/followup` instead for small additions.

The matching `questions/<slug>.md` is normally **not** rewritten — the original framing is preserved as the artefact.

## Steps

### 1. Pick the topic

List `ideas/*.md` and ask which one to revise (skip if the user named it).

### 2. Snapshot the current version

Before overwriting, copy the current `ideas/<slug>.md` to `ideas/<slug>.revisions/YYYY-MM-DD.md` so the history is preserved on disk (not just in git). Create the `ideas/<slug>.revisions/` directory if it doesn't exist.

### 3. Re-read context

Read `context/stack.md` — the stack may have changed since the original response was written.

### 4. Rewrite

Update `ideas/<slug>.md`. Keep the back-link header to `questions/<slug>.md`. Add a `**Last revised:**` line beneath `**Written:**`. If significant assumptions changed, note that explicitly in a "What changed" subsection at the top.

### 5. Commit

```bash
git add -A
git commit -m "Revise topic: <slug>"
git push
```

### 6. Report

Tell the user what changed and link to the snapshot under `ideas/<slug>.revisions/`.
