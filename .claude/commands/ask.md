---
description: Ask a new technical how-to question and produce a structured guide under guides/<slug>/.
---

# /ask

Capture a new technical question and turn the answer into a maintainable guide.

## Steps

### 1. Get the question

If the user invoked `/ask` with arguments, treat that as the question. Otherwise ask them to state it in one sentence.

### 2. Pick a slug

Propose a kebab-case slug derived from the question (e.g. "How do I run Ollama with a ROCm GPU?" → `ollama-rocm-setup`). Confirm with the user before creating the folder if there's any ambiguity.

### 3. Read context

Always read `context/stack.md` and any other files in `context/` before answering. They define the user's environment — answers must respect it.

### 4. Produce the guide

Create `guides/<slug>/README.md` with this structure:

```markdown
# <Question, restated as a title>

**Asked:** YYYY-MM-DD
**Stack:** <relevant subset of context/stack.md>

## TL;DR

<2–4 sentences — the actionable answer>

## Background

<Why this matters, what assumptions are being made>

## Steps

1. ...
2. ...

## Verification

<How to confirm it worked>

## Caveats / things that can go wrong

<Version sensitivity, gotchas, known pitfalls>

## References

- <links, man pages, docs>
```

Use the Context7 MCP for any library/CLI/framework references — your training data may be stale.

### 5. Update the index

Append a row to the "Guides" section in the top-level `README.md`:

```markdown
- [<Title>](guides/<slug>/README.md) — <one-line summary>
```

### 6. Commit

```bash
git add -A
git commit -m "Add guide: <slug>"
git push
```

### 7. Report

Give the user the guide path and the public GitHub URL (`gh repo view --json url -q .url`).
