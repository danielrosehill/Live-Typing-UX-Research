# Leading STT models for live typing — SaaS and local

**Question:** [`questions/live-typing-models-saas-and-local.md`](../questions/live-typing-models-saas-and-local.md)
**Written:** 14/04/26
**Stack:** Desktop live dictation — real-time speech-to-text feeding a cursor in arbitrary apps. Hardware-agnostic but Daniel's box is Ubuntu 25.10 / KDE on a GPU workstation.

## TL;DR

For **live typing**, the two things that actually matter are (a) whether the model **emits partial hypotheses quickly enough to feel live** (sub-300 ms tick), and (b) whether its **final output is accurate enough that you don't have to correct afterwards**. That split maps cleanly onto an architecture axis:

- **Transducer-family** (RNN-T, TDT) and **streaming CTC** — built for low-latency partials. Dominant in SaaS streaming APIs and in Parakeet / Moonshine-streaming locally.
- **Encoder-decoder / attention** (Whisper, Canary, gpt-4o-transcribe) — attention over the full utterance gives top-tier accuracy but is inherently **batch-after-endpoint**; streaming is faked by re-running on a rolling window.

Live-typing tools almost always bolt **VAD → streaming ASR → endpointed final re-score** together. The "best" model depends on which of the three you're willing to compromise on.

## Background

A live-typing pipeline has five stages: mic capture → VAD/endpointing → ASR partials (typed on-screen as they stabilise) → ASR final (committed on utterance end) → injection into focused window. The ASR stage is what this doc is about.

Two orthogonal choices drive model selection:

1. **SaaS vs local** — latency floor, privacy, cost per minute, offline capability.
2. **Streaming vs batch-on-endpoint** — whether you want text to appear as you speak, or only once you stop.

[Handy](https://github.com/cjpais/Handy) is a useful reference point because its model registry reflects current production-grade open-weight options — and it ships multiple architectures side by side so users can swap.

## SaaS / API — the streaming leaders

All of these stream over WebSocket (or equivalent) and emit **interim results** with a **final** on endpoint. Architecture families below are based on public vendor characterisation; proprietary specifics are often undisclosed.

| Vendor / model | Architecture family | Streaming behaviour | Notes |
|---|---|---|---|
| **Deepgram Nova-3** | End-to-end transformer, CTC-family (historical; not vendor-confirmed) | WebSocket, interim + finals, endpointing built in | Low P50 latency (~300 ms partial), strong English, word-level timestamps, keyterm boosting. |
| **AssemblyAI Universal-Streaming** (2025) | Transducer-family, purpose-built for streaming | "Immutable" partials (don't rewrite), clean end-of-turn finals | Designed around agent/voice-UI use. Different partial semantics from Deepgram. |
| **Speechmatics** | Proprietary (historically CTC-based, "Ursa"/"Flow") | WebSocket, partials + finals | Strong accent/ESL robustness; batch-quality finals while still streaming. |
| **Google Cloud STT v2 (Chirp 2)** | Encoder + CTC-style decoding for streaming models (USM-derived) | `interim_results: true` | Wide language coverage; latency varies by region. |
| **Azure Speech** | Transformer-based (undisclosed specifics) | SDK/WebSocket with partial hypotheses | Tight Windows/M365 integration, continuous recognition mode. |
| **OpenAI `gpt-4o-transcribe` / `gpt-4o-mini-transcribe`** | Encoder-decoder (GPT-4o family) | Streaming via Realtime API, delta tokens | Newer offering; accuracy is LLM-grade but partials are decoder tokens, not ASR alignments — semantics differ from CTC/RNN-T partials. |
| OpenAI `whisper-1` (legacy) | Encoder-decoder (Whisper) | **Not streaming — batch only** | Listed for completeness; not viable for live typing against the API. |

Common pattern: all of these let you stream raw PCM up, receive `is_final` flags on result objects, and most support **endpointing hints** (silence thresholds, utterance-end triggers). Differences that matter for a live-typing UX:

- **Immutable vs rewritten partials** — AssemblyAI's Universal-Streaming prefers partials that don't move once emitted; Deepgram will rewrite aggressively until the final. Rewriting feels smart on screen but complicates injection if you type partials directly.
- **Endpoint control** — Deepgram and AssemblyAI expose explicit VAD/utterance-end parameters; Google/Azure are more opaque.
- **Word timings vs token deltas** — transducer/CTC APIs give word-aligned timestamps; GPT-4o-transcribe gives token deltas without alignment.

## Locally runnable — what Handy ships

Handy's model registry ([`src-tauri/src/managers/model.rs`](https://github.com/cjpais/Handy/blob/main/src-tauri/src/managers/model.rs)) is a current, actively maintained list of local STT options grouped by engine. As of April 2026:

### Whisper family (via `whisper-rs` / whisper.cpp, GGML)

- `small` (465 MB), `medium` q4_1 (469 MB), `turbo` (large-v3-turbo, 1549 MB), `large` (large-v3 q5_0, 1031 MB), `breeze-asr` (Taiwanese Mandarin fine-tune, 1030 MB).
- **Encoder-decoder**. Not streaming-native — for live typing you chunk with overlap or wait for endpoint.

### NVIDIA Parakeet family (via `transcribe-rs`, ONNX int8)

- `parakeet-tdt-0.6b-v2` (English, 451 MB), `parakeet-tdt-0.6b-v3` (25 EU + ru/uk, 456 MB) — **marked `is_recommended: true`** in Handy.
- **FastConformer encoder + TDT (Token-and-Duration Transducer) decoder.** Transducer-family → native streaming, very low-latency partials. Licence: **CC-BY-4.0** (commercial use with attribution).

### Moonshine family (Useful Sensors)

- `moonshine-base` (EN, 55 MB, non-streaming), and V2 streaming variants: `moonshine-tiny-streaming-en` (31 MB), `moonshine-small-streaming-en` (99 MB), `moonshine-medium-streaming-en` (192 MB).
- **Encoder-decoder** (transformer), but tiny: tiny ≈ 27M params, base ≈ 61M params. Licence: **MIT**. Paper: [arXiv:2410.15608](https://arxiv.org/abs/2410.15608).
- Handy exposes **two distinct engine types** — `Moonshine` (batch) and `MoonshineStreaming` — because the V2 streaming variants use a different runtime contract.

### NVIDIA Canary family (via `transcribe-rs`)

- `canary-180m-flash` (en/de/es/fr, 146 MB), `canary-1b-v2` (25 EU languages, 691 MB).
- FastConformer-based. Designed for multilingual accuracy over raw streaming latency.

### Others

- `sense-voice-int8` (zh/en/ja/ko/yue, 152 MB) — multilingual, tuned for Asian languages.
- `gigaam-v3-e2e-ctc` (Russian CTC, 151 MB) — pure CTC, language-specific.
- `cohere-int8` (multilingual, 1708 MB) — Cohere's ASR entry.

### Runtime split

- **Whisper** → `whisper-rs` (whisper.cpp bindings), GGML format, GPU-accelerated where available.
- **Everything else** (Parakeet, Moonshine, Canary, SenseVoice, GigaAM, Cohere) → [`transcribe-rs`](https://github.com/cjpais/transcribe-rs) (same author), **ONNX Runtime**, int8 quantised, CPU-optimised.
- VAD: **Silero** via `vad-rs`. Audio I/O: `cpal`. Input injection: `rdev` + `xdotool`/`wtype`/`dotool` fallbacks on Linux.

## Architecture commonalities and differences

All production STT models today share the same front end: **log-mel features → neural encoder** (Conformer/FastConformer/Transformer). Where they diverge is **the decoder**, and that's what determines streaming behaviour.

### Decoder family → streaming behaviour

| Family | Examples | Streaming? | Partial-result feel |
|---|---|---|---|
| **CTC** (Connectionist Temporal Classification) | Speechmatics (historical), Google Chirp streaming, GigaAM | Native streaming; frame-synchronous | Partials stabilise quickly but over-generate repeats before final collapse. |
| **RNN-T / Transducer / TDT** | Parakeet-TDT, AssemblyAI Universal-Streaming, most "real-time" SaaS | Native streaming; frame-synchronous with label budget | Clean partial growth, strong rewriting semantics; latency-accuracy tunable. |
| **Encoder-decoder (attention)** | Whisper, Canary, Moonshine, gpt-4o-transcribe | **Not natively streaming** — attends over full encoder states | Batch-quality finals; "streaming" is simulated via chunking + overlap or rolling-window re-inference. |
| **Hybrid / multi-head** | Some Nova-generation systems, various research models | Varies | Vendor-specific. |

### The practical implications for a live-typing UI

- **If you want text to appear during the utterance**: pick a **transducer or streaming CTC** model (Parakeet-TDT, Moonshine-streaming, Deepgram, AssemblyAI). These are what makes the "words appear as you speak" UX feel natural.
- **If you commit on endpoint only**: **encoder-decoder models are fine, often better** — Whisper-turbo or gpt-4o-transcribe will beat most streaming models on final accuracy. This matches the pattern most push-to-talk tools use (Handy's default is push-to-talk + Parakeet-v3).
- **Model size is not the main axis** — Moonshine-tiny (31 MB) streaming beats Whisper-small (465 MB) for live partials despite being ~15× smaller, because its decoder is designed for the job. Size mostly drives vocabulary/multilingual coverage and final-form accuracy, not streaming fitness.

### Licensing, briefly

- **Whisper** — MIT.
- **Moonshine** — MIT.
- **Parakeet (TDT 0.6B)** — CC-BY-4.0 (attribution required for commercial use).
- **Canary** — CC-BY-4.0.
- **SaaS APIs** — per-minute pricing, no model weights exposed.

## Recommendation (for Daniel's prototype)

Given the desktop live-typing goal and a GPU workstation:

1. **Local baseline for push-to-talk**: `parakeet-tdt-0.6b-v3`. It's Handy's recommended default for a reason — transducer streaming, small enough to run on CPU, near-Whisper-large accuracy on English. Commercial licence is clean.
2. **Local baseline for true streaming partials**: `moonshine-small-streaming-en` or `moonshine-medium-streaming-en`. MIT licence, purpose-built for streaming, tiny enough that latency is trivial.
3. **Quality ceiling for batch-on-endpoint**: Whisper `turbo` (large-v3-turbo) locally, or `gpt-4o-transcribe` via API for the absolute top of the accuracy envelope — accept that partials will be fake-streamed (decoder token deltas).
4. **SaaS fallback for the live UX**: Deepgram Nova-3 or AssemblyAI Universal-Streaming depending on whether you prefer rewriting partials or immutable partials. Both are the reference implementations of "good streaming partial UX".

A pragmatic architecture is **Parakeet-streaming for partials + Whisper-turbo for end-of-utterance re-score** — that's the pattern explored in [`batch-vs-chunked-inference-accuracy`](batch-vs-chunked-inference-accuracy.md).

## References

- Handy source — model registry: [`src-tauri/src/managers/model.rs`](https://github.com/cjpais/Handy/blob/main/src-tauri/src/managers/model.rs)
- Handy runtime: [`transcribe-rs`](https://github.com/cjpais/transcribe-rs), [`whisper-rs`](https://github.com/tazz4843/whisper-rs), [`vad-rs`](https://github.com/emotechlab/vad-rs)
- Moonshine paper: [arXiv:2410.15608](https://arxiv.org/abs/2410.15608)
- Parakeet-TDT-0.6B-v3: [huggingface.co/nvidia/parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
- Deepgram Nova-3 docs: [developers.deepgram.com](https://developers.deepgram.com/)
- AssemblyAI Universal-Streaming: [assemblyai.com/blog](https://www.assemblyai.com/blog)
- Related topics in this repo:
  - [`whisper-vs-streaming-asr-for-dictation`](whisper-vs-streaming-asr-for-dictation.md) — why Whisper isn't built for live dictation.
  - [`batch-vs-chunked-inference-accuracy`](batch-vs-chunked-inference-accuracy.md) — accuracy gap between streaming and end-of-utterance inference.
  - [`partial-transcript-rewriting`](partial-transcript-rewriting.md) — interim results and stabilization.
