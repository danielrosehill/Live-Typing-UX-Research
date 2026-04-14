---
description: Update an existing guide with new findings, snapshotting the previous version.
---

# /revise

Substantial rewrite of an existing guide. Use `/followup` instead for small additions.

## Steps

### 1. Pick the guide

List `guides/*/README.md` and ask which one to revise (skip if the user named it).

### 2. Snapshot the current version

Before overwriting, copy the current `README.md` to `guides/<slug>/revisions/YYYY-MM-DD.md` so the history is preserved on disk (not just in git).

### 3. Re-read context

Read `context/stack.md` — the stack may have changed since the original guide was written.

### 4. Rewrite

Update the guide. Bump the `**Asked:**` line to add a `**Last revised:**` line beneath it. If significant assumptions changed, note that explicitly in a "What changed" subsection at the top.

### 5. Commit

```bash
git add -A
git commit -m "Revise guide: <slug>"
git push
```

### 6. Report

Tell the user what changed and link to the snapshot under `revisions/`.
