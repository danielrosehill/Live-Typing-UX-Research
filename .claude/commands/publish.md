---
description: Refresh the top-level README topics index and report the public repo URL.
---

# /publish

Rebuild the "Topics" section of the top-level `README.md` so it reflects every topic currently in `questions/` + `ideas/`, then push.

## Steps

### 1. Scan `questions/` and `ideas/`

For each slug present in `questions/<slug>.md`:

- Read the H1 title from `questions/<slug>.md` for the **Question** column.
- Read the H1 title from `ideas/<slug>.md` for the **Ideas** column.
- Warn the user if a question file has no matching ideas file (or vice versa) — these are orphans that should be repaired before publishing.

### 2. Rebuild the index

Replace the existing "Topics" section in the top-level `README.md` with a freshly generated, alphabetically-sorted-by-slug table:

```markdown
## Topics

| Question | Ideas |
|---|---|
| [<question title>](questions/<slug>.md) | [<ideas title>](ideas/<slug>.md) |
| ...
```

If both folders are empty, write `_No topics yet — run /ask to add one._` instead.

### 3. Commit & push

```bash
git add README.md
git commit -m "Refresh topics index"
git push
```

### 4. Report the public URL

```bash
gh repo view --json url -q .url
```

Print the URL so the user can share it.
