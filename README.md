# {{PROJECT_NAME}}

{{DESCRIPTION}}

A workspace for asking Claude (or any AI coding agent) technical how-to questions and turning the answers into **living, maintainable guides** — like a GitHub Gist, but multi-file and built to be revised over time.

## Why a repo and not a Gist?

- A guide can span multiple files (code samples, diagrams, follow-up Q&A).
- Guides change as tools, OS versions, and best practices change — versioned files beat a one-shot answer.
- Each guide gets its own folder, history, and (optionally) issues/PRs for corrections.

## Getting started

After cloning from this template, run:

```
/setup-workspace
```

That replaces placeholders, seeds `context/`, and asks for a one-line description of what you'll be researching here.

## Day-to-day commands

| Command | What it does |
|---|---|
| `/ask` | Pose a new technical question — produces a structured guide under `guides/<slug>/README.md`. |
| `/revise` | Update an existing guide with new findings. |
| `/followup` | Append a Q&A note to an existing guide without rewriting it. |
| `/publish` | Rebuild the top-level guide index and report the public repo URL. |

## Layout

```
context/   — Stack, environment, constraints (read by every command)
guides/    — One folder per guide; each contains README.md + optional followups/, revisions/
outputs/   — Loose drafts before they become a guide
```

## Visibility

This template defaults to **public** repos. Don't put secrets or sensitive context in `context/` or `guides/`.
