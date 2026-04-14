# Inference cadence and sentence entry — finding the UX sweet spot for pause-for-thought dictators

**Question:** [`questions/inference-cadence-and-sentence-entry.md`](../questions/inference-cadence-and-sentence-entry.md)
**Written:** 14/04/26
**Stack:** Desktop live dictation for someone who pauses mid-sentence to think. Distracted by words-as-you-speak; also frustrated by fully-batched wait-for-the-end rendering.

## TL;DR

The "distracting vs laggy" axis is actually **three tunable intervals**, not one:

1. **Partial cadence** — how often interim results redraw on screen (typically 100–300 ms).
2. **Finalisation threshold** — how long of silence before a segment is committed as immutable final (can be ~10 ms up to seconds).
3. **Utterance-end threshold** — how long of silence before the system declares "you're done" (the one that lets you press Enter) — typically **1000–2500 ms**.

Deepgram's UX feels right because it **decouples** these. Most tools conflate them. The sweet spot for a pause-for-thought dictator is: partials at ~250–300 ms with **stabilised / immutable** semantics, finals fired quickly on short silences, and an utterance-end signal around **1.5–2 seconds** — long enough to survive a thinking pause, short enough not to feel laggy when you actually stop.

## Background

Every streaming ASR system emits two event types over the wire: **interim** results (mutable, redrawable) and **final** results (committed, not revised). Vendors layer a third signal on top — **utterance-end** — that tries to say "the speaker is finished for now," independent of when any particular token was finalised.

The UX problem is that these three intervals interact, and most apps expose only one knob. You get "too live" when partials redraw aggressively with every token. You get "too laggy" when a single batch-on-endpoint runs, you wait for it, and only then can you hit Enter. The systems that feel best are the ones that let the three signals run on different clocks.

## The three intervals, with numbers

| Signal | What it controls | Typical value | User-facing feel |
|---|---|---|---|
| **Partial cadence** | How often interim text redraws | 100–300 ms | "Liveness" — lower = more flicker, higher = more lag |
| **Finalisation silence** | Silence before `is_final=true` on a segment | 10 ms – few sec | How quickly text "locks in" |
| **Utterance-end silence** | Silence before "done speaking" event | 1000–2500 ms | How long a pause-for-thought you can take before the system commits |

### Partial cadence — per vendor

| Vendor | Documented cadence | Partial semantics |
|---|---|---|
| **Deepgram Nova-3** | ~100–300 ms | Mutable — will rewrite until final. `smart_format` improves finals. |
| **AssemblyAI Universal-Streaming** | ~300 ms | **Immutable** — partials, once emitted, don't retract. |
| **Google Cloud STT v2** | ~100–200 ms (observational) | Mutable. |
| **Azure Speech** | ~200–500 ms (observational) | Mutable `Recognizing` events. |
| **Speechmatics** | Continuous; `max_delay` caps finals (default **10 s**, min 2 s) | Mutable; `max_delay_mode` trades latency vs punctuation. |
| **OpenAI Realtime / `gpt-4o-transcribe`** | Sub-second token deltas, not formally spec'd | Token-level — semantics differ from CTC/RNN-T partials. |

The **immutable-partials** pattern (AssemblyAI) is the explicit UX countermeasure to word-by-word flicker. Deepgram achieves a similar feel by emitting slightly lagged, stabilised partials rather than retracting aggressively — in practice a ~250–300 ms cadence with minimal mutation.

### Endpointing and utterance-end — per vendor

- **Deepgram** distinguishes two things:
  - `endpointing` — ms of silence before `is_final=true` fires on a segment. Default **10 ms** (i.e. finalize ASAP).
  - `utterance_end_ms` — emits a separate `UtteranceEnd` event after this much non-speech. Recommended **1000–2000 ms**. This is the one you wire up for "OK, hit Enter now."
- **AssemblyAI** uses model-based end-of-turn rather than pure silence: `end_of_turn_confidence_threshold`, `min_end_of_turn_silence_when_confident` (~160 ms default), `max_turn_silence` (~2400 ms default).
- **Google Cloud** — `single_utterance` mode ends on silence; threshold not user-exposed.
- **Azure** — `SpeechServiceConnection_EndSilenceTimeoutMs` (default ~500 ms).
- **OpenAI Realtime** — `turn_detection.silence_duration_ms` (default 500 ms) controls server VAD turn boundaries.

### Industry silence-threshold convention

These aren't standardised, but there's a broad consensus across vendors and VAD libraries:

| Silence duration | Typical interpretation |
|---|---|
| < 300 ms | Within-utterance pause (don't segment) |
| 500–1000 ms | Sentence boundary |
| 1500–2500 ms | Turn / paragraph boundary / "done speaking" |
| > 3000 ms | Stop recording |

Silero VAD typical hangover is 100–500 ms; WebRTC VAD runs at 10/20/30 ms frames with app-level hangover usually 200–800 ms.

## Why Deepgram feels right

Deepgram's API cleanly separates the three signals:

- Partials stream at ~250–300 ms with stabilisation that avoids per-word retraction — **present enough to feel live, lagged enough not to strobe**.
- `endpointing` defaults to 10 ms, so segments commit as immutable finals as soon as silence begins — the text "settles" behind the partial cursor.
- `utterance_end_ms` is a **separate event** you can set to 1500–2000 ms. That means: the text has already finalised, *and* you get a distinct signal for "press Enter now" after the user's pause-for-thought grace period.

This decoupling is the key. Most consumer tools fire a single "done" event that bundles finalise + commit + send, which forces you to pick between "too eager" and "too laggy". Deepgram lets you pick different values for each.

## Sentence and paragraph boundary detection

All major vendors combine a **punctuation/capitalization model** (applied on finals) with **silence-based segmentation**. No vendor advertises a semantic sentence-boundary model separate from punctuation.

- Deepgram `smart_format` + `paragraphs=true` — paragraph breaks use long silences + punctuation signals.
- AssemblyAI `format_text` — punctuation on finals.
- Google `enable_automatic_punctuation` — same pattern.

**Practical mapping for a pause-for-thought dictator:**

| Silence | Action |
|---|---|
| 150–400 ms | Ignore — pause within thought. Do nothing. |
| 400–800 ms | Sentence-ending punctuation candidate (punctuation model decides `.` / `?` / `,`). |
| 1500–2000 ms | Utterance-end — safe to commit and signal "done". |
| 2000–3000 ms | Paragraph boundary — insert `\n\n`. |
| > 3000 ms | Stop recording / release PTT equivalent. |

The 1500–2000 ms window is the critical one. Too short (say 800 ms) and a thinking pause looks like "done". Too long (say 3000 ms) and the user drums their fingers after they actually stopped.

## The UI friction points, explicitly named

1. **Strobing partials** — text redrawing word-by-word with retractions as the ASR revises. Fixed by: immutable partials (AssemblyAI), stabilised partials (Deepgram), or UI-side lag buffer (render partials ~200 ms behind arrival).
2. **Batch-on-endpoint wait** — a batch model (Whisper-large) running only after you stop talking, blocking the Enter-to-send moment. Fixed by: streaming partials running live + final re-score in parallel; or separate utterance-end event so the UI commits before the re-score returns.
3. **Premature commit on thinking pause** — a too-short utterance-end threshold cuts you off mid-thought. Fixed by: raise `utterance_end_ms` to 1500–2000 ms; optionally make it adaptive (longer after conjunctions, shorter after periods).
4. **Conflated endpoint and commit** — a single event triggers finalisation *and* send. Fixed by: separate "text is final" from "user is done" — two events, not one.

## Recommendation

For Daniel's prototype (and for any live-typing UI serving pause-for-thought users), the target configuration:

- **Partial redraw cadence**: ~250 ms, with either immutable-partial semantics or a UI-side 200 ms stabilisation buffer.
- **Segment finalisation**: aggressive — ~10–200 ms, so text "locks in" behind the live cursor quickly.
- **Utterance-end for Enter-to-send**: **1500 ms** default, user-configurable 1000–2500 ms. Crucially, a **separate event** from finalisation.
- **Paragraph break heuristic**: 2000–3000 ms silence inserts `\n\n`.
- **Visual cue**: render partials in a slightly dimmer / italicised style until final — gives the eye something to latch onto without the "flickering-cursor" jitter.

Deepgram's `interim_results=true` + `endpointing=10` + `utterance_end_ms=1500` is the reference config for this user profile. For local, the equivalent is a streaming ASR (Parakeet-TDT or Moonshine-streaming) plus a separate app-side Silero VAD timer that fires the "done" event at 1500 ms independently of the ASR's own segment finalisation.

## References

- Deepgram streaming API — `endpointing`, `utterance_end_ms`, `smart_format`, `paragraphs`: [developers.deepgram.com/docs/understanding-end-of-speech-detection](https://developers.deepgram.com/docs/understanding-end-of-speech-detection)
- AssemblyAI Universal-Streaming end-of-turn params: [assemblyai.com/docs/speech-to-text/universal-streaming](https://www.assemblyai.com/docs/speech-to-text/universal-streaming)
- Google Cloud STT v2 interim results: [cloud.google.com/speech-to-text/v2/docs](https://cloud.google.com/speech-to-text/v2/docs)
- Speechmatics `max_delay`: [docs.speechmatics.com](https://docs.speechmatics.com/)
- OpenAI Realtime `turn_detection`: [platform.openai.com/docs/guides/realtime](https://platform.openai.com/docs/guides/realtime)
- Silero VAD: [github.com/snakers4/silero-vad](https://github.com/snakers4/silero-vad)
- Related topics:
  - [`vad-for-live-typing`](vad-for-live-typing.md) — VAD building blocks for the timers above.
  - [`partial-transcript-rewriting`](partial-transcript-rewriting.md) — the mechanics of interim results and stabilisation.
  - [`streaming-vs-batch-injection`](streaming-vs-batch-injection.md) — how these intervals map to injection strategy.
  - [`batch-vs-chunked-inference-accuracy`](batch-vs-chunked-inference-accuracy.md) — why you may still want a final re-score after utterance-end.

## Caveats

- Default numbers (Deepgram `endpointing=10`, Speechmatics `max_delay=10s`) are documented.
- Google / Azure / OpenAI partial cadences above are observational and undocumented — treat as ballparks, not spec.
- AssemblyAI end-of-turn defaults are current as of 2025 and subject to change.
- The "200–400 ms feels live, >800 ms feels laggy" rule is anecdotal industry folklore — no peer-reviewed HCI number confirms it.
