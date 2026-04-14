---
description: Capture a new question into questions/<slug>.md and write the response into ideas/<slug>.md, cross-referenced.
---

# /ask

Capture a new technical question and turn the response into a maintainable, cross-referenced pair of files.

## Steps

### 1. Get the question

If the user invoked `/ask` with arguments, treat that as the question. Otherwise ask them to state it in one sentence.

### 2. Pick a slug

Propose a kebab-case slug derived from the question (e.g. "How do I run Ollama with a ROCm GPU?" → `ollama-rocm-setup`). Confirm with the user before creating the files if there's any ambiguity.

The same slug is used on both sides: `questions/<slug>.md` and `ideas/<slug>.md`.

### 3. Read context

Always read `context/stack.md` and any other files in `context/` before answering. They define the user's environment — responses must respect it.

### 4. Write the question file

Create `questions/<slug>.md`. Keep it short and faithful to how the user posed the question — do not paraphrase it into a different question.

```markdown
# <Short title — restate, don't reframe>

**Asked:** DD/MM/YY
**Slug:** `<slug>`
**Response:** [`ideas/<slug>.md`](../ideas/<slug>.md)

## The question

<verbatim or lightly cleaned-up version of what the user asked, including any context they gave>
```

### 5. Write the ideas file

Create `ideas/<slug>.md` with the long-form response. The shape of the response follows from the question — use the structure below as a default for how-to questions, but feel free to adapt for design exploration, pattern catalogues, or comparative analysis.

```markdown
# <Title — restate the question as a statement>

**Question:** [`questions/<slug>.md`](../questions/<slug>.md)
**Written:** DD/MM/YY
**Stack:** <relevant subset of context/stack.md>

## TL;DR

<2–4 sentences — the actionable answer or core finding>

## Background

<Why this matters, what assumptions are being made>

## <Body sections — adapt to the question>

For how-to questions: Steps → Verification → Caveats.
For design questions: Patterns → Tradeoffs → Recommendation.
For comparisons: Options → Criteria → Verdict.

## References

- <links, man pages, docs>
```

Use the Context7 MCP for any library/CLI/framework references — your training data may be stale.

### 6. Update the topics index

Append (or insert in alphabetical order) a row to the "Topics" table in the top-level `README.md`. If the table doesn't exist yet, create it; remove any `_No topics yet_` placeholder.

```markdown
## Topics

| Question | Ideas |
|---|---|
| [<short question title>](questions/<slug>.md) | [<ideas title>](ideas/<slug>.md) |
```

### 7. Commit

```bash
git add -A
git commit -m "Add topic: <slug>"
git push
```

### 8. Report

Give the user both file paths and the public GitHub URL (`gh repo view --json url -q .url`).
