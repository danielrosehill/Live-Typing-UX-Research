# Live Typing UX Research

A research workspace for documenting the UX challenges of using **live voice typing as a replacement for keyboard input on the desktop**.

The focus is desktop-specific — not mobile dictation, not transcription-after-the-fact, but real-time speech-to-text that feeds a cursor in arbitrary applications (editors, chat boxes, terminals, address bars).

This repo catalogues:

- **Interaction patterns** in current live-typing tools — what they're called (push-to-talk, hands-free / VAD-gated, hold-to-dictate, toggle-dictation, streaming overlay, commit-on-pause, etc.), how they behave from the user's perspective, and how they work under the hood (streaming ASR vs. chunked, endpointing, partial vs. final tokens, injection method into the focused window).
- **Friction points** observed while prototyping — false commits, lost partials, focus loss, punctuation/formatting gaps, correction workflows, modal vs. modeless overlays.
- **A working spec for an "ideal" desktop live-typing UI**, derived from the patterns above and prototypes built along the way, refined as the research evolves.

Each topic lives as its own guide under `guides/<slug>/`, revised over time rather than rewritten.

---

## Guides

- [Handling focus loss between dictation start and transcript arrival](guides/focus-loss-during-dictation/README.md) — patterns for when the user moves focus away while waiting for the transcript: clipboard fallback, target-window capture with deferred inject, anchored overlay, and what's actually implementable on Wayland.

---

## How this workspace works

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
