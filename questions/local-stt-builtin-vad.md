# Local STT engines with built-in VAD (or equivalent silence-handling architecture)

**Asked:** 14/04/26
**Slug:** `local-stt-builtin-vad`
**Response:** [`ideas/local-stt-builtin-vad.md`](../ideas/local-stt-builtin-vad.md)

## The question

Which local speech-to-text engines have built-in VAD — or an alternative architectural mechanism that serves the same purpose — such that they **will not hallucinate inputs the user didn't speak** when the user pauses for thought? Either the engine has VAD bundled, or its architecture is such that audio captured during silent thinking periods is never sent through the transcription model.

Related:

- [`ideas/vad-for-live-typing.md`](../ideas/vad-for-live-typing.md) — the general VAD pipeline story.
- [`ideas/local-stt-inference-engines-gpu.md`](../ideas/local-stt-inference-engines-gpu.md) — engine × vendor × backend table.
