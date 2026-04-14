# CLAUDE.md — Live Typing UX Research

## Purpose

A research workspace for documenting the UX challenges of using **live voice typing as a replacement for keyboard input on the desktop**.

The scope is desktop-specific — not mobile dictation, not transcription-after-the-fact, but real-time speech-to-text that feeds a cursor in arbitrary applications (editors, chat boxes, terminals, address bars).

The work here catalogues:

- **Interaction patterns** in current live-typing tools — their names (push-to-talk, hands-free / VAD-gated, hold-to-dictate, toggle-dictation, streaming overlay, commit-on-pause, etc.), how they behave from the user's perspective, and how they work under the hood (streaming ASR vs. chunked, endpointing, partial vs. final tokens, injection method into the focused window).
- **Friction points** observed while prototyping — false commits, lost partials, focus loss, punctuation/formatting gaps, correction workflows, modal vs. modeless overlays.
- **A working spec for an "ideal" desktop live-typing UI**, derived from the patterns above and Daniel's own prototypes, refined as the research evolves.

This is a **technical research workspace** — a place to ask Claude (or any AI agent) "how do I do X?" or "what's the best way to approach Y?" and capture the conversation as a **living, maintainable reference**.

Each topic is recorded as **two cross-referenced files**: the user's question (in `questions/`) and the AI's response/ideas (in `ideas/`). They share a slug and link to each other. This keeps the framing and the analysis legible as separate artefacts rather than fused into one document.

## Folder structure

```
.
├── context/     # Background on the user's stack, constraints, goals
├── questions/   # One file per question — <slug>.md — faithful to how it was posed
├── ideas/       # One file per response — <slug>.md — cross-referenced to its question
└── outputs/     # Loose drafts before promotion to a question/ideas pair
```

## Conventions

- **One topic = one matched pair**: `questions/<kebab-slug>.md` + `ideas/<kebab-slug>.md`. The slug is identical on both sides.
- The **question** file is short — restate the user's question as clearly as possible without paraphrasing it into a different question. Include a link to the corresponding `ideas/<slug>.md`.
- The **ideas** file is the long-form response: patterns, tradeoffs, recommendations, references. It links back to `questions/<slug>.md` in its header.
- Top-level `README.md` is an **index table** with one row per topic, linking the question and the ideas side by side. Keep it in sync when topics are added or renamed.
- Use absolute dates (DD/MM/YY in prose, ISO `YYYY-MM-DD` in filenames).
- **Follow-ups**: append to the existing `ideas/<slug>.md` under a dated `## Follow-up — YYYY-MM-DD` section, and add a short note in `questions/<slug>.md` if a new sub-question prompted it.
- When the ideas file is substantially rewritten, snapshot the previous version into `ideas/<slug>.revisions/YYYY-MM-DD.md` before overwriting.

## Available commands

- `/setup-workspace` — first-run setup; replaces placeholders in this file and seeds `context/`.
- `/ask` — capture a new question into `questions/<slug>.md` and write the response into `ideas/<slug>.md`, cross-referenced.
- `/revise` — update the response in `ideas/<slug>.md` with new information (snapshot the previous version first).
- `/followup` — append a dated follow-up section to `ideas/<slug>.md` without rewriting it.
- `/publish` — refresh the top-level `README.md` index table and report the public URL.
- `/glossary` — rebuild the top-level `glossary.md` by extracting and consolidating terminology defined across `ideas/`.

## Behavioural notes

- Default to producing **explanatory how-to content** rather than throwaway answers — the user is building a reference, not just chatting.
- Cite tools, versions, and OS/distro assumptions explicitly. Stale guides are worse than missing ones.
- When the answer is uncertain or fast-moving, say so in the guide itself (don't bury caveats in a tool result).
- This repo is typically **public** on GitHub — never write secrets, API keys, or private hostnames into guides or context.
