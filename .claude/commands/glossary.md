---
description: Rebuild the top-level glossary.md by extracting terminology defined across ideas/*.md.
---

# /glossary

Regenerate `glossary.md` at the repo root by reading every file in `ideas/` and consolidating the terminology defined or named in them into a single alphabetical reference.

This is not a mechanical extraction — apply judgment about what counts as a "term worth glossing." The glossary is for readers who want to look up vocabulary used across the workspace, not a dump of every bolded phrase.

## Steps

### 1. Read everything in `ideas/`

Read each `ideas/*.md` file. For each one, note:

- Terms introduced in **bold** with a definition nearby (the strongest signal — these are deliberate definitions).
- Synonyms listed inline (e.g. `*Synonyms: foo, bar, baz.*` or "also called X, Y, Z").
- Pattern names introduced in section headings (e.g. "Pattern 3 — Capture-target, defer-inject").
- Acronyms expanded in the prose (VAD, PTT, RTF, ASR, etc.).

Skip:

- Tool/product names (Talon, Whisper, Parakeet) — those belong in references, not the glossary.
- One-off jargon used without definition.
- Extremely generic terms (e.g. "user", "window") that don't carry domain meaning.

### 2. Merge with the existing glossary

Read the current `glossary.md`. For each candidate term:

- If it's already in the glossary, leave the canonical definition alone unless an `ideas/` file now contradicts it. Update the *See* backlinks to include any new source files.
- If it's a synonym for an existing term, fold it into that entry's `*Synonyms:*` line rather than creating a duplicate entry.
- If it's new, write a fresh entry in the right alphabetical section.

Preserve the existing entry style:

```markdown
### Term name
*Synonyms: alt name, other alt name.*
One- to three-sentence definition. Concrete, no hedging.
*See:* [slug-1](ideas/slug-1.md), [slug-2](ideas/slug-2.md)
```

If a term has no synonyms, omit the `*Synonyms:*` line. If it isn't discussed in any `ideas/` file (rare — only for terms cited from external sources), omit the `*See:*` line.

### 3. Rewrite `glossary.md`

Re-emit the whole file with:

- The existing intro paragraph at the top (don't drop it).
- Sections `## A` through `## Z`, alphabetical, omitting any letter section with no entries.
- Entries within each section also alphabetical.
- Cross-reference stubs (`### Foo` → `*See* **Bar**.`) for important synonyms that readers might look up directly.

### 4. Sanity check

After rewriting:

- Every `*See:*` link must resolve to a file that exists in `ideas/`.
- No duplicate canonical entries (synonyms folded into one canonical term).
- No empty alphabetical sections.

### 5. Commit

```bash
git add glossary.md
git commit -m "Rebuild glossary from ideas/"
git push
```

### 6. Report

Tell the user:

- How many entries the glossary now has.
- Which terms were newly added in this pass (if any).
- Which terms were updated with new backlinks (if any).
