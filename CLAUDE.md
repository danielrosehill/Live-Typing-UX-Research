# CLAUDE.md — Live Typing UX Research

## Purpose

A research workspace for documenting the UX challenges of using **live voice typing as a replacement for keyboard input on the desktop**.

The scope is desktop-specific — not mobile dictation, not transcription-after-the-fact, but real-time speech-to-text that feeds a cursor in arbitrary applications (editors, chat boxes, terminals, address bars).

The work here catalogues:

- **Interaction patterns** in current live-typing tools — their names (push-to-talk, hands-free / VAD-gated, hold-to-dictate, toggle-dictation, streaming overlay, commit-on-pause, etc.), how they behave from the user's perspective, and how they work under the hood (streaming ASR vs. chunked, endpointing, partial vs. final tokens, injection method into the focused window).
- **Friction points** observed while prototyping — false commits, lost partials, focus loss, punctuation/formatting gaps, correction workflows, modal vs. modeless overlays.
- **A working spec for an "ideal" desktop live-typing UI**, derived from the patterns above and Daniel's own prototypes, refined as the research evolves.

This is a **technical research workspace** — a place to ask Claude (or any AI agent) "how do I do X?" or "what's the best way to approach Y?" and capture the answer as a **living, maintainable guide**.

Think of it as a private/public GitHub Gist that grew up: it can hold multiple guides, each of which can be revised, extended with follow-up Q&A, and published as a coherent reference over time.

## Folder structure

```
.
├── context/    # Background on the user's stack, constraints, goals
├── guides/    # Each guide lives in its own folder (one topic per folder)
│              #   guides/<slug>/README.md            — the canonical guide
│              #   guides/<slug>/followups/           — appended Q&A
│              #   guides/<slug>/revisions/           — dated snapshots if needed
└── outputs/   # Loose drafts, exploratory answers, before promotion to a guide
```

## Conventions

- One guide = one folder under `guides/<kebab-slug>/`.
- Top-level `README.md` in this repo is an **index** of all guides — keep it in sync when guides are added or renamed.
- Inside each guide folder, `README.md` is the canonical answer. Follow-ups go to `followups/YYYY-MM-DD-short-topic.md`.
- Use absolute dates (DD/MM/YY in prose, ISO `YYYY-MM-DD` in filenames).
- When a guide is substantially rewritten, snapshot the previous version into `revisions/YYYY-MM-DD.md` before overwriting.

## Available commands

- `/setup-workspace` — first-run setup; replaces placeholders in this file and seeds `context/`.
- `/ask` — capture a new technical question and produce a structured guide under `guides/`.
- `/revise` — pick an existing guide and update it with new information.
- `/followup` — append a follow-up Q&A to an existing guide without rewriting it.
- `/publish` — refresh the top-level `README.md` index of all guides and report the public URL.

## Behavioural notes

- Default to producing **explanatory how-to content** rather than throwaway answers — the user is building a reference, not just chatting.
- Cite tools, versions, and OS/distro assumptions explicitly. Stale guides are worse than missing ones.
- When the answer is uncertain or fast-moving, say so in the guide itself (don't bury caveats in a tool result).
- This repo is typically **public** on GitHub — never write secrets, API keys, or private hostnames into guides or context.
