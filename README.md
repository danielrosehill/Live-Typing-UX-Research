# Live Typing UX Research

A research workspace for documenting the UX challenges of using **live voice typing as a replacement for keyboard input on the desktop**.

The focus is desktop-specific — not mobile dictation, not transcription-after-the-fact, but real-time speech-to-text that feeds a cursor in arbitrary applications (editors, chat boxes, terminals, address bars).

This repo catalogues:

- **Interaction patterns** in current live-typing tools — what they're called (push-to-talk, hands-free / VAD-gated, hold-to-dictate, toggle-dictation, streaming overlay, commit-on-pause, etc.), how they behave from the user's perspective, and how they work under the hood (streaming ASR vs. chunked, endpointing, partial vs. final tokens, injection method into the focused window).
- **Friction points** observed while prototyping — false commits, lost partials, focus loss, punctuation/formatting gaps, correction workflows, modal vs. modeless overlays.
- **A working spec for an "ideal" desktop live-typing UI**, derived from the patterns above and prototypes built along the way, refined as the research evolves.

Each topic is recorded as a pair of cross-referenced files:

- `questions/<slug>.md` — the question as posed, kept short and faithful to how it was asked.
- `ideas/<slug>.md` — the exploratory response: patterns, tradeoffs, recommendations, references.

The two halves link to each other. This keeps the user's framing and the AI's analysis legible as separate artefacts rather than fused into one document.

---

## Reference

- [Glossary](glossary.md) — consolidated terminology used across all topics.

## Topics

| Question | Ideas |
|---|---|
| [Does end-of-utterance batch inference give better accuracy than chunked streaming?](questions/batch-vs-chunked-inference-accuracy.md) | [End-of-utterance batch inference is genuinely more accurate than chunked streaming — it's not just frontend engineering](ideas/batch-vs-chunked-inference-accuracy.md) |
| [Focus loss during dictation](questions/focus-loss-during-dictation.md) | [Handling focus loss between dictation start and transcript arrival](ideas/focus-loss-during-dictation.md) |
| [Leading STT models for live typing — SaaS/API and locally runnable](questions/live-typing-models-saas-and-local.md) | [Leading STT models for live typing — SaaS and local, with architecture commonalities and differences](ideas/live-typing-models-saas-and-local.md) |
| [Local STT inference engines and GPU acceleration (NVIDIA vs AMD)](questions/local-stt-inference-engines-gpu.md) | [Local STT inference engines — GPU acceleration on NVIDIA vs AMD, with an engine × vendor × backend table](ideas/local-stt-inference-engines-gpu.md) |
| [What is the dynamic-rewriting display in tools like Deepgram called?](questions/partial-transcript-rewriting.md) | [Interim results, stabilization, and where the work happens](ideas/partial-transcript-rewriting.md) |
| [Streaming injection vs batch transcription on stop](questions/streaming-vs-batch-injection.md) | [Streaming injection vs utterance-final injection in live dictation](ideas/streaming-vs-batch-injection.md) |
| [VAD (voice activity detection) for live typing](questions/vad-for-live-typing.md) | [VAD for live typing: what's native, what's bolted on, and how to wire them together](ideas/vad-for-live-typing.md) |
| [Hotkey count tradeoffs for voice dictation control (single key, macro pads)](questions/voice-dictation-hotkey-count-tradeoffs.md) | [Hotkey count tradeoffs for voice dictation: from single toggle to a four-key macro pad](ideas/voice-dictation-hotkey-count-tradeoffs.md) |
| [Inference cadence and sentence entry for pause-for-thought dictators](questions/inference-cadence-and-sentence-entry.md) | [Inference cadence and sentence entry — finding the UX sweet spot for pause-for-thought dictators](ideas/inference-cadence-and-sentence-entry.md) |
| [Why Whisper isn't ideal for live dictation, and how live STT models rewrite on the fly](questions/whisper-vs-streaming-asr-for-dictation.md) | [Why Whisper isn't built for live dictation, and how streaming STT models rewrite on the fly](ideas/whisper-vs-streaming-asr-for-dictation.md) |

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
| `/glossary` | Rebuild `glossary.md` from terminology defined across `ideas/`. |

## Layout

```
context/    — Stack, environment, constraints (read by every command)
questions/  — One file per question, <slug>.md, kept faithful to how it was posed
ideas/      — One file per response, <slug>.md, cross-referenced to its question
outputs/    — Loose drafts before promotion to a question/ideas pair
```

## Visibility

This template defaults to **public** repos. Don't put secrets or sensitive context in `context/` or `guides/`.
