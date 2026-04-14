# The pause-tolerant prompt-dictator — a codified user profile and the STT stack that matches it

**Question:** [`questions/pause-tolerant-dictation-profile-and-stack.md`](../questions/pause-tolerant-dictation-profile-and-stack.md)
**Written:** 14/04/26
**Stack:** Desktop live dictation on Ubuntu 25.10 / KDE / Wayland, primary workload is dictating prompts to AI agents. Thinking pauses of 3–20 s are routine. Hallucinations during silence are an absolute no. Preferred UX is batched commits at ~20 s cadence, not token-streaming.

## TL;DR

The right architecture for this user is **push-to-talk (or hold-to-dictate) with batched commits at a ~15–20 s cadence**, fed into an ASR model with proven non-hallucinating silence behaviour, then polished by an LLM pass that removes disfluencies and inserts paragraph breaks before injection. The **top cloud pick is Deepgram Nova-3** (with `smart_format=true`, `endpointing` decoupled from `utterance_end_ms`, or simply PTT-gated so endpointing is moot). The **top local pick is NVIDIA Parakeet-TDT 0.6B v2 via NeMo** (streaming variant for hands-free, offline variant under PTT) because it has no Whisper-style silence-hallucination failure mode. Raw Whisper is only acceptable under faster-whisper with `vad_filter=True` + strict `no_speech_threshold` / `logprob_threshold` / `compression_ratio_threshold` settings.

## The user profile, codified

Archetype name: **the pause-tolerant prompt-dictator**.

Defining traits, as a checklist:

- [ ] **Thinks mid-utterance.** 3–20 s pauses are routine, not exceptional. Any system that treats >2 s of silence as "done speaking" is incompatible.
- [ ] **Zero tolerance for hallucinated content.** A fabricated "Thank you for watching" or a repeated prior phrase inside a prompt to an AI agent is worse than a missed word — it actively corrupts the instruction.
- [ ] **Wants post-processed output.** Raw ASR with `um`s, false starts, and wall-of-text monologue is unacceptable. Output should read like edited prose: paragraphs, punctuation, disfluencies removed.
- [ ] **Precision-sensitive workload.** The primary consumer of the transcript is an LLM acting on editing instructions. A misheard "remove" vs "reword" changes the outcome. Justifies paying for a top-tier model.
- [ ] **Flow-state tool, not transcription tool.** The goal is to lower the activation energy between a thought and its delivery to an agent. Anything that makes the user aware of the tool itself (flickering partials, token-by-token reveal, premature commits) is a regression.
- [ ] **Batched visible output at ~20 s cadence.** Token-streaming is distracting. Fully silent until end-of-session is also wrong — the user wants reassurance that inference is making progress. A commit every 15–20 s hits that middle.

## Derived specification

Translating the profile into concrete technical requirements:

### 1. Long-pause tolerance — hard requirement

Two valid architectures, pick one:

- **(a) Sidestep endpointing entirely** — push-to-talk or hold-to-dictate. The mic is hardware-gated by the user's finger. Silences during thought happen with the key released, so they are never in the audio buffer. This is the cleanest solution and what this profile strongly suggests.
- **(b) If hands-free is required** — use an engine with **architectural non-emission on silence** (Parakeet streaming, NeMo FastConformer, sherpa-onnx, Vosk) and set the utterance-end threshold to ≥ 20 s. Deepgram `utterance_end_ms` goes well above default and can be tuned high; Speechmatics `max_delay` caps finals rather than defining an utterance boundary, so utterance-end is app-side anyway.

**Hallucination risk vectors to neutralise:**

- Whisper's well-documented silence-hallucination behaviour (Koenecke et al., FAccT 2024). Mitigations, in order of defensive strength:
  1. VAD gating in front of the model (Silero VAD; `vad_filter=True` in faster-whisper).
  2. `no_speech_threshold` ≥ 0.6 (default), `logprob_threshold` ≥ -1.0, `compression_ratio_threshold` ≤ 2.4. These are heuristics, not a VAD — do not rely on them alone.
  3. `condition_on_previous_text=False` — breaks the repetition-loop failure mode.
  4. Switch to a non-Whisper model (Parakeet, FastConformer, Nova-3) that doesn't have the training-distribution silence problem in the first place.
- Cloud streaming endpoints can also emit spurious finals during long pauses on some providers; Deepgram Nova-3 and Speechmatics have the cleanest empirical profile here as of April 2026.

### 2. Post-processing pipeline — two valid shapes

Architecture A — **native formatter only** (cheaper, lower latency, less flexible):

```
mic → ASR with built-in formatter → injection
         (Deepgram smart_format / AssemblyAI format_text+disfluencies
          / Speechmatics punctuation_overrides)
```

Architecture B — **ASR + LLM polish pass** (better prompt-grade output):

```
mic → ASR (raw text + optional native formatter)
    → LLM reformatter (disfluency removal, paragraph inference,
                       light prose cleanup — NOT rewriting content)
    → injection
```

For this user, **Architecture B is the right default**. Native formatters handle punctuation and casing, but they do not reliably remove "you know", "like I said", false starts, or mid-sentence topic swerves — and they don't insert paragraph breaks on semantic content changes. A small LLM pass gets you there.

Candidate polish models:

| Model | Hosted/local | Latency for ~300 words | Notes |
|---|---|---|---|
| `gpt-4o-mini` / `gpt-4.1-mini` | Hosted | 1–3 s | Cheap; reliable at "clean this transcript without changing meaning". |
| `claude-haiku-4` | Hosted | 1–3 s | Strong at preserving intent; good for instruction-grade transcripts. |
| Local `Qwen2.5-7B-Instruct` | Local (GPU) | 1–4 s | Runs alongside STT on a 16 GB+ card; privacy win. |
| Local `Llama-3.1-8B-Instruct` | Local (GPU) | 1–4 s | Similar. |
| Local `gemma-3-4b-it` | Local (CPU/GPU) | 2–5 s | Lightweight fallback. |

Key prompt engineering rule for the polish stage: **instruct the LLM not to rewrite, only to remove disfluencies and add paragraph breaks**. Otherwise it will "improve" prompts and change their meaning, which is the exact failure mode this user cannot tolerate.

### 3. Injection cadence — batched at ~15–20 s

This is **not** token-streaming. It is also not "fully silent until PTT release". It is periodic commits of well-formed prose.

Implementation options:

- **PTT commit-on-release** (simplest). Works for bursts up to the user's natural utterance length. For longer dictations it violates the "reassurance that inference is working" criterion.
- **PTT with periodic flush every 15–20 s** while the key is held. App-side timer; on tick, slice the audio buffer at the last VAD-detected pause, run inference + polish on the slice, inject, and continue recording on the remainder. This is the architecture that directly matches the profile.
- **Speechmatics `max_delay` ≈ 15–20 s** — caps how long the model will wait before committing a final. Limits apply (documented ceiling is typically 10 s on some plans as of April 2026; check current docs).
- **Deepgram with manual buffering**: let partials stream, but ignore them for UI purposes; only commit to the focused window on utterance-end events, or on an app-side 20 s timer.
- **Whisper/Parakeet chunked batch inference**: slice audio into 15–20 s windows (aligned to VAD-detected silence boundaries to avoid mid-word cuts), run batch inference on each, inject.

This is a generalisation of the Handy "print delay" pattern documented in [`handy-inference-vs-typing-delay.md`](handy-inference-vs-typing-delay.md) — but shifted up the pipeline. Handy paces the *keystrokes* of an already-done transcript. This profile wants pacing at the *inference* boundary, so each commit is a genuinely fresh chunk of finalised, polished text.

### 4. Accuracy / nuance bar

Prompt dictation demands a higher bar than casual typing. A transcript going to an AI agent is a *specification*, and a single misheard token can invert an instruction. This justifies:

- Largest-tier models: **whisper-large-v3** / **Nova-3** / **Universal-2** / **Parakeet-TDT 0.6B v2** / **Scribe**. Do not use `whisper-tiny`, `whisper-base`, or `distil-small` for this workload.
- Domain vocabulary boosting where available: Deepgram `keywords` / Speechmatics `custom_dictionary` / AssemblyAI `word_boost`. Seed with tool names, library names, and recurring proper nouns.

## Recommended cloud stack

All prices / parameter defaults are April 2026; verify against current vendor docs before committing.

| Vendor / model | Pause tolerance | Post-processing | Injection cadence knob | Hallucination-on-silence | Approx $/hr | Fit for this profile |
|---|---|---|---|---|---|---|
| **Deepgram Nova-3** | Excellent — `utterance_end_ms` decoupled from `endpointing`; set to ≥ 20000 or ignore in favour of PTT | `smart_format=true`, `paragraphs=true`, `filler_words=false` (or `=true` then LLM-strip) | App-side buffer + commit on `UtteranceEnd` or 20 s timer | Low on silence; streaming non-emission is well-behaved | ~$0.43–0.58 | **Top pick.** Cleanest separation of "final" and "done". |
| **AssemblyAI Universal-Streaming (Universal-2)** | Good — `max_turn_silence` tunable, immutable partials mean no flicker | `format_text=true`, `disfluencies=false`, `punctuate=true` | Commit on end-of-turn events | Low; immutable-partials semantics reduce retraction artefacts | ~$0.37 | Strong alternative; end-of-turn model is opinionated and may not reach 20 s — app-side timer is safer. |
| **Speechmatics Enhanced** | Good — `max_delay` caps finals (commonly up to 10 s; beyond that, app-side batching) | `punctuation_overrides`, `enable_entities`, diarisation optional | `max_delay` + app buffer | Low-hallucination profile; explicit silence handling | ~$0.30–0.50 | Good for long-form; nuance model competitive with Nova-3 on UK / accented English. |
| **OpenAI `gpt-4o-transcribe` (Realtime)** | Mixed — token-level streaming; `turn_detection.silence_duration_ms` defaults to 500 ms | Built-in; fluent, sometimes over-edits | `turn_detection=null` to disable server VAD; commit client-side | Low in practice, but semantics differ from CTC/RNN-T; occasional over-formalisation | ~$0.60/hr (audio input pricing) | Use with `turn_detection=null` + PTT to sidestep; otherwise endpointing is too eager. |
| **OpenAI `whisper-1` (non-Realtime)** | Batch only | Simple punctuation | Not applicable (batch) | Inherits Whisper's silence-hallucination risk | ~$0.36 | Acceptable under PTT commit-on-release; not for streaming. |
| **ElevenLabs Scribe v1** | Batch only | Good formatting, disfluency handling | Not applicable (batch) | Non-streaming; no live hallucination pattern | ~$0.40 | Strong for post-hoc polish; **not** a live dictation engine. |

**Cloud recommendation:** **Deepgram Nova-3 + `smart_format` + app-side 20 s buffer, fronted by PTT.** The PTT lets you treat `utterance_end_ms` as irrelevant; the app-side buffer gives you the 20 s cadence; `smart_format` handles punctuation, and a cheap LLM polish pass removes disfluencies.

Deepgram knobs that matter (as of April 2026):

```
model=nova-3
smart_format=true
punctuate=true
paragraphs=true
filler_words=false
diarize=false
interim_results=false      # we don't want partials on the wire for this profile
endpointing=10             # irrelevant under PTT, leave at default
utterance_end_ms=20000     # fallback if running hands-free
keywords=<project vocab list>
```

## Recommended local stack

Privacy, cost, and offline operation all favour local. Daniel's hardware is documented in [`local-stt-inference-engines-gpu.md`](local-stt-inference-engines-gpu.md) — see that topic for which engine × backend combinations are viable on this machine.

| Engine / model | Silence handling | Accuracy tier | Best usage for this profile |
|---|---|---|---|
| **Parakeet-TDT 0.6B v2 (offline, via NeMo)** | No architectural silence handling; safe under PTT | State-of-the-art English WER on LibriSpeech / AMI | **Top pick under PTT.** ~20–50× real-time on a modern GPU; chunk into 15–20 s windows. |
| **FastConformer streaming (NeMo)** | Built-in endpointing; no hallucination on silence | Very good, slightly below offline Parakeet | **Top pick hands-free.** Use for live streaming + long-pause tolerance. |
| **faster-whisper large-v3** | VAD via Silero, optional (`vad_filter=True`) | State-of-the-art Whisper | Acceptable with strict config (below). Still slower than Parakeet. |
| **whisper.cpp large-v3** | `--vad --vad-model silero-v5.1-small.onnx` | Same as above | Best for CPU-only or when CTranslate2 isn't available. |
| **WhisperX** | VAD integral to pipeline | Same as Whisper | Batch-oriented; fine for post-hoc polish passes, not live. |
| **whisper-streaming (ufal)** | VAD-gated by default | Whisper WER | Designed for long-form streaming; matches this profile if you must use Whisper in a streaming shape. |
| **Moonshine-base** | No built-in VAD — must pair with Silero | A tier below Whisper-large | Small, fast, PTT-friendly; not the first choice when accuracy matters for prompts. |
| **sherpa-onnx (Zipformer)** | Built-in VAD + endpointing | Solid, below Whisper-large on hard domains | Great ultra-low-latency fallback; not the top pick for nuance. |
| **Canary (NeMo)** | No streaming endpointer | Strong multilingual | Only under PTT with VAD in front. |

**Safe `faster-whisper` config for this profile:**

```python
from faster_whisper import WhisperModel

model = WhisperModel("large-v3", device="cuda", compute_type="float16")

segments, info = model.transcribe(
    audio,
    vad_filter=True,
    vad_parameters=dict(
        min_silence_duration_ms=500,
        threshold=0.5,
    ),
    no_speech_threshold=0.6,
    log_prob_threshold=-1.0,
    compression_ratio_threshold=2.4,
    condition_on_previous_text=False,   # critical: breaks repetition loops
    beam_size=5,
    temperature=(0.0, 0.2, 0.4),        # fallback ladder; first pass greedy
    word_timestamps=False,
    language="en",
)
```

The `condition_on_previous_text=False` line is the single most important setting for this user. It is Whisper's main silence-hallucination mitigation beyond VAD gating.

**Local recommendation:** **Parakeet-TDT 0.6B v2 under push-to-talk, batched at ~20 s windows, polished by a local Qwen2.5-7B-Instruct pass, injected via Fcitx IME commit-string.** No Whisper quirks to manage; inference is fast enough that the 20 s cadence is inference-done-in-parallel rather than inference-blocking.

See [`local-stt-builtin-vad.md`](local-stt-builtin-vad.md) for the wider silence-handling landscape.

## Recommended frontends that match this UX

Existing desktop tools ordered by how well they match the pause-tolerant prompt-dictator profile:

| Tool | Pattern | Fit for this profile |
|---|---|---|
| **Handy** (Rust/Tauri, open source) | PTT → batch transcribe → keystroke-paced injection | **Strong match.** Paced typing *visually* approximates the batched-commit cadence. Use Parakeet backend. See [`handy-inference-vs-typing-delay.md`](handy-inference-vs-typing-delay.md). |
| **Superwhisper / MacWhisper** (macOS) | Hold-to-record → batch transcribe → paste | Strong match on macOS only. PTT sidesteps endpointing entirely. |
| **Wispr Flow / WhisprFlow** | Cursor-level dictation with LLM polish built in | Matches the "LLM polish pass" requirement out of the box. Closed-source; cloud-only. |
| **Aqua Voice** | "Writes like you would" — polish-oriented | Same category as Wispr Flow; closed-source / cloud. |
| **nerd-dictation** (Linux) | PTT, Vosk backend by default, optional Whisper | Strong PTT match; needs LLM polish bolted on for the paragraph-inference requirement. |
| **whisper-typer / whisper-keyboard** (various) | PTT → Whisper → inject | Adequate if paired with a VAD-gated Whisper build. |
| **Speechnote, Numen, Talon** | Hands-free with their own VAD logic | Mixed — Talon is PTT-friendly, others are hands-free and would need their endpointing pushed out to 20 s. |
| **Generic Deepgram/AssemblyAI demo UIs** | Token-streaming overlays | **Poor fit.** Exact "being watched" pattern this user wants to avoid. |

**Framing:** push-to-talk + batched commit is the cleanest match. Streaming tools with configurable utterance-end ≥ 20 s are acceptable. Hands-free streaming with short endpointing (default 500–2000 ms) is fundamentally incompatible with this profile.

## Recommended architecture — the spec

Putting it all together:

```
┌─────────────────────────────────────────────────────────────────────┐
│  PTT hotkey (hold to dictate, with optional toggle for long-form)   │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Audio capture — sounddevice.InputStream, 16 kHz mono, ring buffer  │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Silero VAD pass — label frames; used only to find safe cut points  │
│  for chunk boundaries (never drops audio inside a chunk).           │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Chunk-and-commit scheduler:                                        │
│  - Every 15–20 s of elapsed PTT time, OR on PTT release,            │
│    slice audio at nearest VAD silence boundary.                     │
│  - Pass the completed slice to ASR; keep recording the remainder.   │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  ASR — Parakeet-TDT 0.6B v2 (local, GPU)  OR                        │
│        Deepgram Nova-3 (cloud, smart_format)                        │
│  Returns raw text (or lightly formatted text).                      │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  LLM polish pass — Qwen2.5-7B-Instruct local  OR  gpt-4.1-mini      │
│  System prompt: "Remove disfluencies and false starts. Insert       │
│  paragraph breaks where the topic shifts. Do NOT rewrite, reorder,  │
│  or change meaning. Preserve technical terms exactly."              │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Injection — Fcitx IME commit-string (instant, Wayland-clean) or    │
│  clipboard+paste fallback. Per-commit; not character-paced.         │
└─────────────────────────────────────────────────────────────────────┘
```

**Latency budget per 20 s chunk** (local stack, modern NVIDIA GPU):

| Stage | Budget |
|---|---|
| VAD scan for cut point | <50 ms |
| Parakeet-TDT inference on 20 s audio | 0.5–1.5 s |
| Qwen2.5-7B polish pass on ~60 words | 1–3 s |
| IME commit injection | <50 ms |
| **Total wall time from cut to injection** | **~2–5 s** |

So a user who has been dictating for 20 s sees a polished paragraph land 2–5 s later, then continues speaking. The *feel* is one new paragraph every 15–25 s, which is the target cadence.

For cloud, swap Parakeet for Nova-3 (0.5–2 s) and Qwen for `gpt-4.1-mini` (1–2 s); budget is similar.

## Anti-patterns for this user

Things to avoid, specifically for the pause-tolerant prompt-dictator:

1. **Short utterance-end timers (< 2 s).** Will commit during thought pauses. Either push endpointing to ≥ 20 s, or use PTT so endpointing is moot. Deepgram `utterance_end_ms=1500`, AssemblyAI `max_turn_silence=2400` — both too aggressive for this profile.
2. **Vanilla Whisper (`openai-whisper`) on long audio without VAD.** Silence-hallucinations ("Thank you for watching", "Subscribe", repeated phrases, drifts into Welsh). Catastrophic for prompt instructions. Always use faster-whisper with `vad_filter=True` + the strict config above, or switch to Parakeet.
3. **Token-by-token streaming overlays.** The exact "being watched" pressure the user wants to avoid. Disable `interim_results` on Deepgram; don't render partials in the UI.
4. **Hands-free VAD-only toggling without a PTT fallback.** A cough, keyboard noise, or a family member's voice triggers capture. For a prompt-dictator, any false capture is a corrupted instruction.
5. **LLM polish passes with vague prompts.** "Clean up this transcript" will paraphrase the user's prompt and change its meaning. Prompt the polish stage narrowly: *remove disfluencies, add paragraph breaks, preserve wording*.
6. **Character-paced keystroke injection** on long transcripts. The 15–20 s-per-paragraph cadence plus another 10–20 s of character-paced typing compounds into an unacceptable delay. Use IME commit-string or clipboard+paste, not paced `ydotool`/`enigo`. See [`handy-inference-vs-typing-delay.md`](handy-inference-vs-typing-delay.md).
7. **Mixing `condition_on_previous_text=True` with Whisper in chunked mode.** Guarantees repetition-loop failures eventually. Always `False` for this workload.
8. **Using `whisper-tiny` / `distil-small` to "speed things up".** The accuracy loss matters more for prompts than for casual typing; save the cycles somewhere else.

## References

- Deepgram — `smart_format`, `endpointing`, `utterance_end_ms`, `paragraphs`, `filler_words`: [developers.deepgram.com/docs/understanding-end-of-speech-detection](https://developers.deepgram.com/docs/understanding-end-of-speech-detection)
- AssemblyAI Universal-Streaming — end-of-turn parameters, immutable partials: [assemblyai.com/docs/speech-to-text/universal-streaming](https://www.assemblyai.com/docs/speech-to-text/universal-streaming)
- Speechmatics — `max_delay`, `punctuation_overrides`, `enable_entities`: [docs.speechmatics.com](https://docs.speechmatics.com/)
- OpenAI Realtime — `turn_detection.silence_duration_ms`, `gpt-4o-transcribe`: [platform.openai.com/docs/guides/realtime](https://platform.openai.com/docs/guides/realtime)
- ElevenLabs Scribe: [elevenlabs.io/docs/capabilities/speech-to-text](https://elevenlabs.io/docs/capabilities/speech-to-text)
- NVIDIA Parakeet-TDT 0.6B v2: [huggingface.co/nvidia/parakeet-tdt-0.6b-v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)
- NVIDIA NeMo streaming ASR (FastConformer, Canary): [docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/asr/models.html](https://docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/asr/models.html)
- faster-whisper (`vad_filter`, `condition_on_previous_text`, thresholds): [github.com/SYSTRAN/faster-whisper](https://github.com/SYSTRAN/faster-whisper)
- WhisperX: [github.com/m-bain/whisperX](https://github.com/m-bain/whisperX)
- whisper-streaming (ufal): [github.com/ufal/whisper_streaming](https://github.com/ufal/whisper_streaming)
- Moonshine: [github.com/usefulsensors/moonshine](https://github.com/usefulsensors/moonshine)
- Silero VAD: [github.com/snakers4/silero-vad](https://github.com/snakers4/silero-vad)
- Koenecke et al., "Careless Whisper: Speech-to-Text Hallucination Harms" (FAccT 2024): [dl.acm.org/doi/10.1145/3630106.3658996](https://dl.acm.org/doi/10.1145/3630106.3658996)
- Related topics in this workspace:
  - [`inference-cadence-and-sentence-entry`](inference-cadence-and-sentence-entry.md) — the three-interval model this spec sits on top of.
  - [`whisper-vs-streaming-asr-for-dictation`](whisper-vs-streaming-asr-for-dictation.md) — why Whisper isn't built for live dictation.
  - [`local-stt-builtin-vad`](local-stt-builtin-vad.md) — which local engines are safe on silence, which aren't.
  - [`vad-for-live-typing`](vad-for-live-typing.md) — the VAD building blocks.
  - [`live-typing-models-saas-and-local`](live-typing-models-saas-and-local.md) — the wider SaaS/local landscape.
  - [`handy-inference-vs-typing-delay`](handy-inference-vs-typing-delay.md) — why paced injection differs from paced inference.
  - [`local-stt-inference-engines-gpu`](local-stt-inference-engines-gpu.md) — which engines run on this machine's GPU.
  - [`cursor-dictation-vs-clipboard-stt-adoption`](cursor-dictation-vs-clipboard-stt-adoption.md) — injection strategy tradeoffs.

## Caveats

- Vendor pricing, parameter defaults, and model names are accurate to the best of my knowledge **as of April 2026** but move fast. Check Deepgram / AssemblyAI / Speechmatics / OpenAI docs before committing.
- `max_delay` ceilings on Speechmatics have historically been 10 s on most plans; pushing to 20 s may require enterprise tier or app-side batching.
- The "20 s cadence" target is a starting point, not a magic number. Tune between 10 s (tighter reassurance) and 30 s (longer chunks, better LLM polish context) based on subjective feel.
- The LLM-polish stage is the largest remaining risk: it can subtly rewrite the user's intent. Narrow prompting + occasional manual review are the mitigations. Consider logging both raw ASR and polished output side by side during the prototype phase so drift is visible.
- Parakeet-TDT model sizes and availability on Hugging Face may differ from NeMo distributions; cross-check before downloading.
- Context7 MCP was rate-limited at the time of writing, so vendor-specific parameter names above draw from existing cross-referenced topics in this workspace rather than a fresh documentation pull. Verify parameter names against live docs before building.
