---
description: Refresh the top-level README guide index and report the public repo URL.
---

# /publish

Rebuild the "Guides" section of the top-level `README.md` so it reflects everything currently in `guides/`, then push.

## Steps

### 1. Scan `guides/`

For each `guides/<slug>/README.md`:
- Read the H1 line for the title.
- Read the `## TL;DR` block (or first paragraph) for a one-line summary.

### 2. Rebuild the index

Replace the existing "Guides" section in the top-level `README.md` with a freshly generated, alphabetically sorted list:

```markdown
## Guides

- [<Title>](guides/<slug>/README.md) — <one-line summary>
- ...
```

If `guides/` is empty, write `_No guides yet — run /ask to add one._` instead.

### 3. Commit & push

```bash
git add README.md
git commit -m "Refresh guide index"
git push
```

### 4. Report the public URL

```bash
gh repo view --json url -q .url
```

Print the URL so the user can share it.
