---
description: Render selected question/ideas topics into a Typst document under outputs/, then compile to PDF.
---

# /consolidate

Take a scope of topics (everything, this session, since a date, a specific list, or the union of past consolidated runs) and produce a single bound document — a `.typ` source plus a compiled `.pdf` — under `outputs/`.

Multiple consolidations accumulate in `outputs/`; nothing is overwritten. Each generated `.typ` carries a `// SLUGS:` header so a future "meta" run can union them.

## Steps

### 1. Pick the scope

If the slash command argument names a scope, use it. Otherwise use AskUserQuestion to ask which scope:

- **all** — every paired topic in the repo.
- **session** — topics created or modified during this Claude session. Use your own awareness of which files you touched first; cross-check with `git status` (uncommitted) and recent commits (`git log --since=...`). If still ambiguous, fall back to asking the user.
- **since DATE** — every topic where either `questions/<slug>.md` or `ideas/<slug>.md` has mtime ≥ DATE. Accept DD/MM/YY or YYYY-MM-DD.
- **slugs** — explicit list, comma- or space-separated.
- **meta** — union of slugs from one or more existing `outputs/*.typ` files (read each file's `// SLUGS:` header). Useful for combining multiple past sessions into one bound reference.

### 2. Resolve to a slug list

Compute the candidate slugs, then **intersect with the actual paired set** — a slug is included only if both `questions/<slug>.md` and `ideas/<slug>.md` exist. Warn the user about any orphans dropped (e.g. a question with no matching ideas).

If the resulting list is empty, stop and report.

### 3. Pick a descriptor and filename

Suggest a short kebab-case descriptor based on the scope:

- `all` → `all`
- `session` → `session`
- `since 2026-04-01` → `since-2026-04-01`
- `slugs` → a 1–2 word summary of the topics, or `selected`
- `meta` → `meta`

Filename: `outputs/<YYYY-MM-DD>-<descriptor>.typ`. If it already exists, append `-2`, `-3`, etc.

### 4. Generate the Typst source

Write `outputs/<filename>.typ` exactly in this shape:

```typst
// SCOPE: <one-line scope description>
// GENERATED: <YYYY-MM-DD>
// SLUGS: <comma-separated slugs>

#import "_template.typ": workspace-doc, topic

#show: workspace-doc.with(
  title: [<workspace project name> — <scope label>],
  scope: "<scope description>",
  slugs: ("<slug-a>", "<slug-b>", ...),
)

#topic("<slug-a>", "../questions/<slug-a>.md", "../ideas/<slug-a>.md")
#topic("<slug-b>", "../questions/<slug-b>.md", "../ideas/<slug-b>.md")
// ...
```

The workspace project name comes from the H1 of the top-level `README.md` (or `{{PROJECT_NAME}}` if the workspace hasn't been set up yet).

### 5. Compile to PDF

Run from the repo root (not from `outputs/`). The `--root .` flag is required so Typst can resolve `read("../questions/...")` paths outside the `outputs/` directory:

```bash
typst compile --root . outputs/<filename>.typ outputs/<filename>.pdf
```

If `typst` is not on `PATH`, tell the user how to install it (most distros: package `typst`; or `cargo install typst-cli`; or download from <https://github.com/typst/typst/releases>) and stop. Leave the `.typ` for them to compile manually later.

If compilation fails because of the `cmarker` package version, bump the import in `outputs/_template.typ` to a newer version and retry. The first compile in a fresh repo will fetch the package from Typst Universe automatically — that's expected.

### 6. Commit

```bash
git add outputs/<filename>.typ outputs/<filename>.pdf
git commit -m "Consolidate: <scope label>"
git push
```

PDFs are binary and can grow the repo over time. If the user prefers source-only, suggest adding `outputs/*.pdf` to `.gitignore` and committing only the `.typ`.

### 7. Report

Print both paths (`.typ` and `.pdf`) and a one-line summary of what was included (slug count, scope).
