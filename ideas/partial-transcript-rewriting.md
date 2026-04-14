# The dynamic-rewriting display: interim results, stabilization, and where the work happens

**Question:** [`../questions/partial-transcript-rewriting.md`](../questions/partial-transcript-rewriting.md)
**Written:** 14/04/26
**Stack:** Streaming ASR services (Deepgram, AssemblyAI Universal-Streaming, Google Cloud Speech-to-Text streaming, Azure Speech, Soniox, Speechmatics, NVIDIA Riva, Apple Dictation) feeding a desktop client. Distinct from the *recognition* question covered in [`whisper-vs-streaming-asr-for-dictation`](whisper-vs-streaming-asr-for-dictation.md) — this is about the *display contract*.

## TL;DR

The pattern doesn't have a single canonical name; the field uses several interchangeable terms:

- **Interim results** — Google's term, the most common in API docs.
- **Partial transcripts / partial hypotheses** — Deepgram, AssemblyAI, most academic papers.
- **Non-final results** — Azure, Apple `SFSpeechRecognitionResult.isFinal == false`.
- **Unstable hypothesis** + **stable prefix** — Google's finer-grained variant, also seen in research as "stabilization".
- **Live caption** / **live transcript** — the user-facing UI label.
- **Incremental ASR** — the academic umbrella term for the whole class of behaviours.

Mechanically it is **mostly backend, with a thin frontend rendering contract.** The streaming ASR server emits a continuous sequence of `(transcript, is_final, [stability])` events over a WebSocket. Each interim event *replaces* (not appends to) the current in-progress segment in the UI. When the server flips `is_final = true`, that segment is committed and a new in-progress segment begins. The client's job is small but not trivial: maintain a `committed_text + in_progress_text` buffer, replace `in_progress_text` on each interim event, and concatenate to `committed_text` on each final event.

The "sentence boundaries are re-inferred" effect comes from two places: the acoustic model revising its earlier guess as more audio arrives (backend), and the post-processing chain — punctuation, casing, ITN, disfluency removal — being re-run on the growing partial each time (backend). The client almost never runs ML; it runs a string-replace loop.

## Background

A streaming ASR session is a stateful, full-duplex connection (WebSocket or gRPC bidi stream). The client sends raw audio frames upward at the capture rate (typically 16 kHz PCM in 20–250 ms chunks). The server sends transcript events downward at its own cadence, decoupled from the audio cadence — usually one event every 100–500 ms once speech is detected.

Each event carries:

- **`transcript`** — the model's current best guess for the *current in-progress utterance*. Not cumulative across utterances.
- **`is_final`** (boolean) — whether this is the locked version of the utterance. Once true, no further events will revise this segment.
- **`stability`** or **`confidence`** (float, vendor-dependent) — how much the model thinks this partial will change.
- Optionally **word-level timings, alternatives (n-best), speaker labels.**

Google's API additionally splits each interim result into a **stable prefix** (the leading words the model is now confident about) and an **unstable suffix** (the trailing words still subject to revision). Other vendors don't expose this split explicitly — you get one transcript string and have to treat the whole thing as mutable.

The UX behaviour the user describes — text appearing, growing, occasionally rewriting earlier words and resnapping sentence boundaries — falls naturally out of this contract.

## What the methodology is called

There is no single industry-standard term. The taxonomy below maps the names you'll encounter to the same underlying behaviour.

### API / vendor terminology

| Vendor / system | Interim event | Locked event | Stability hint |
|---|---|---|---|
| Google Cloud Speech-to-Text | `interim_results` | `is_final = true` | `stability` (0.0–1.0) + `result_end_time` for stable prefix |
| Deepgram | `is_final = false` | `is_final = true` + `speech_final` for endpointed segment | `confidence`; `interim_results` flag toggles emission |
| AssemblyAI Universal-Streaming | `PartialTranscript` | `FinalTranscript` | none surfaced; engine retunes silently |
| Azure Speech | `Recognizing` event | `Recognized` event | none surfaced |
| Apple `SFSpeechRecognizer` | `isFinal = false` | `isFinal = true` | none |
| Speechmatics | `AddPartialTranscript` | `AddTranscript` | none |
| Soniox | `is_final = false` tokens | `is_final = true` tokens | per-token finalisation (very granular) |
| NVIDIA Riva | `is_final = false` | `is_final = true` | `stability` |
| Web Speech API (browser) | `event.results[i].isFinal = false` | `isFinal = true` | none |

### Conceptual / academic terminology

- **Incremental ASR** — the umbrella term in the speech research literature for any system that emits hypotheses before the utterance is complete.
- **Online ASR** — broader, also covers streaming without incremental emission (i.e. "produce one transcript at the end with low latency").
- **Partial / final hypothesis discipline** — how a system manages the lifecycle of a guess from "first emitted" to "locked".
- **Stabilization** / **prefix stability** — the property that early parts of the transcript stop changing as more audio arrives. A high-stability system rewrites less; a low-stability system rewrites more but may end with better accuracy.
- **Re-decoding** / **lattice rescoring** — the actual mechanism by which an earlier guess gets revised: the model (or a downstream LM) re-evaluates the n-best lattice with new acoustic context.
- **Token revision** / **deletion-and-rewrite** — the visible effect when a previously-emitted token is replaced by a different one. Some systems are *non-revisable* (CTC-style, append-only) and some are *revisable* (RNN-T with re-scoring, attention-based with restart).
- **Right-context delay** — the engineering knob that trades latency for stability: how much future audio the model is allowed to peek at before emitting a token.

For the desktop-dictation reference you're building, the cleanest names to standardise on are probably **interim results** (for the events) and **stabilization** (for the rewriting behaviour as it appears to the user).

## Frontend or backend?

It is a **mixture, weighted heavily toward the backend.** The split is roughly:

### Backend does (≈90% of the work)

1. **Streaming acoustic decoding** — the model consumes audio chunks and produces token-level hypotheses with monotonic alignment (RNN-T, streaming CTC, streaming Conformer; see [`whisper-vs-streaming-asr-for-dictation`](whisper-vs-streaming-asr-for-dictation.md) for the architectural detail).
2. **Hypothesis revision** — as new audio arrives, the joint network's beam search re-evaluates the n-best hypotheses for the current utterance. An earlier "their" can flip to "they're" once a following verb disambiguates it. This is the source of the visible rewriting.
3. **Post-processing chain re-run on each partial** — punctuation/casing model, inverse text normalisation ("twenty twenty six" → "2026"), disfluency removal, entity formatting. These run on the partial transcript each time it's emitted, which is why sentence boundaries snap into different positions as the partial grows.
4. **Endpointing** — a separate VAD or a learned end-of-utterance head decides "the speaker is done with this segment, flip to final." This is what causes the in-progress text to lock and a new in-progress segment to begin.
5. **Event emission cadence** — the server decides when to emit an interim result. Some vendors emit on every model step (~80–160 ms); others throttle to ~500 ms; some only emit when the transcript actually changes.

### Frontend does (≈10% — but easy to get wrong)

1. **Maintain two buffers**: `committed` (everything from past `is_final = true` events, concatenated) and `in_progress` (the latest interim transcript for the *current* utterance, replaced wholesale each event).
2. **Render `committed + in_progress`** on each event. Style `in_progress` differently (lighter colour, italic, underline, subtle background) to signal mutability.
3. **On `is_final`**: append `in_progress` to `committed`, clear `in_progress`, ready for the next utterance.
4. **Cursor / caret positioning** — keep the caret at the end of `committed + in_progress` so the user sees text growing toward them.
5. **Optional: client-side stabilization heuristic** — if the vendor doesn't provide a stable-prefix hint, the client can compute a longest-common-prefix across the last N partials and only animate / rewrite the suffix beyond that prefix. This dampens visible jitter at the cost of a small extra delay.
6. **Optional: smoothing / debouncing** — coalesce rapid-fire partials so the UI doesn't repaint at 20 Hz. A 60–80 ms render budget is usually right.
7. **Edge cases**: handle out-of-order events (rare on WebSocket but possible on lossy transports); handle the connection dropping mid-utterance (commit `in_progress` as-is or discard).

### Where the line moves

Some products move *more* work to the frontend deliberately:

- **Two-pass clients**: render the raw partial immediately for responsiveness, then run a small client-side rewriter (punctuation, capitalisation) to clean it up before commit. Reduces server post-processing latency.
- **Custom stabilization**: the client tracks how often each token has been revised and only renders tokens that have been stable for k consecutive partials. Trades a bit of latency for much less visible rewriting.
- **Predictive rendering**: the client runs a tiny on-device LM that predicts the next 1–2 words from the current partial and renders them ghosted, then confirms or rewrites when the server catches up. Rare in practice — too easy to hallucinate.

And some products move *more* work to the backend:

- **Pre-stabilized output**: the server only emits an interim result when its stable-prefix has grown. The client gets an append-only stream and never has to rewrite. AssemblyAI's Universal-Streaming and Soniox's per-token finalisation lean this way.
- **Server-side rendering of the styled HTML**: rare for dictation, common for live-caption broadcast tools.

## How a single utterance looks on the wire

Concrete trace for the spoken phrase *"the meeting is at four PM tomorrow"*, talking to a generic streaming ASR endpoint with `interim_results=true` and `smart_format=true`. Times are illustrative.

```
t=0.00s  client opens WebSocket, starts streaming 16-bit PCM @ 16kHz
t=0.30s  → interim   "the"                              is_final=false
t=0.45s  → interim   "the meeting"                      is_final=false
t=0.62s  → interim   "the meeting is"                   is_final=false
t=0.80s  → interim   "the meeting is at"                is_final=false
t=1.05s  → interim   "the meeting is at 4"              is_final=false  ← ITN kicks in
t=1.25s  → interim   "the meeting is at 4 PM"           is_final=false
t=1.55s  → interim   "the meeting is at 4 PM tomorrow"  is_final=false
t=1.80s  → final     "The meeting is at 4 PM tomorrow." is_final=true   ← punctuation + casing on commit
t=2.10s  endpointer fires; segment closed
```

Things to notice:

- The same prefix ("the meeting is at") is re-emitted in each interim event. The client replaces, not appends.
- `"four"` becomes `"4"` mid-stream — that's the ITN model running on the partial each time and changing its mind once it sees the following "PM".
- Capitalisation of `"The"` and the trailing period only land on the final event. Many vendors only run the heaviest post-processing on the final utterance to keep interim latency low; cheaper post-processing (number formatting) runs on every partial.
- A revision can also delete: if the user's next word disambiguates an earlier homophone, an interim result can shorten or restructure the prefix.

## Why it's done this way

The design is a compromise between three competing goals:

- **Perceived latency** — the user wants to see something within ~250 ms of speaking. Waiting for a finalised, post-processed transcript would feel sluggish.
- **Final accuracy** — the model gets better answers when it sees more right-context. Forcing it to commit early hurts WER.
- **UI stability** — the user wants the text to stop wiggling so they can read it. Constant rewriting is distracting.

Interim results + stabilization is the standard compromise: emit a fast, mutable guess for responsiveness, lock it once enough right-context has arrived, and visually distinguish the two states. The exact tuning (how often to emit, how much to revise, when to flip to final) is what differentiates products and what the various stability/endpointing knobs control.

## Implications for an "ideal" desktop live-typing UI

A few design choices follow directly from the contract:

- **Render committed and in-progress text in different visual styles.** Users learn very quickly to ignore the unstable region while reading the stable one. Without the visual cue, every partial revision looks like a bug.
- **Never inject the in-progress region into a destination application.** Only commit on `is_final`, or on a client-side stability heuristic (e.g. "this prefix has been stable for 400 ms"). See [`streaming-vs-batch-injection`](streaming-vs-batch-injection.md) for the injection-policy implications.
- **Tune endpointing aggressively for dictation.** Default endpointing thresholds are tuned for meeting transcription (long pauses tolerated). Dictation users want short pauses to commit, so they can think between phrases without losing the segment.
- **Respect the two-buffer model in your data structures.** A single mutable string is hard to reason about; `committed: string + in_progress: string` makes the contract explicit and matches the API event shape.
- **Provide a manual "commit now" affordance.** Some users want to flush the in-progress segment without waiting for the endpointer. A keyboard shortcut that forces `in_progress → committed` is cheap to add and high-value.
- **Consider stabilization debouncing if the vendor's partials are jittery.** A 200–400 ms longest-common-prefix dampener removes a lot of visible noise without hurting perceived latency.

## Caveats

- **"Deepgram does X" is a moving target.** Vendor APIs evolve; check current docs before relying on specific event field names. The high-level contract (interim → final, replace not append) is stable; the field names and stability metrics are not.
- **Web Speech API is not a peer to commercial APIs.** Browser implementations vary wildly in stability behaviour; Chrome's implementation (which proxies to Google) is the most production-like.
- **Some embedded / on-device models are append-only.** Apple's older on-device dictation, several CTC-only open-source models, and some keyboard voice-input modes don't revise — they emit once and commit. The "rewriting" UX is specific to revisable systems (RNN-T, attention with restart, server-side beam search).
- **Stabilization metrics are not comparable across vendors.** Google's `stability` and Deepgram's `confidence` measure different things and aren't on the same scale.
- **Translation streaming behaves differently.** When a streaming ASR is paired with a streaming MT model, the rewriting can be much more aggressive (whole clauses re-ordered) because translation needs more right-context than transcription. The same display contract applies but the visual jitter is higher.
- **Local Whisper "streaming" wrappers fake this contract.** They run batch Whisper on rolling VAD chunks and synthesise interim/final events from the chunk boundaries. The rewriting feel is shallower and the latency floor is higher; see [`whisper-vs-streaming-asr-for-dictation`](whisper-vs-streaming-asr-for-dictation.md).

## References

- Google Cloud Speech-to-Text — interim results and stability: <https://cloud.google.com/speech-to-text/docs/basics#interim-results>
- Deepgram — interim results and `is_final` / `speech_final`: <https://developers.deepgram.com/docs/interim-results>
- AssemblyAI Universal-Streaming — partial vs. final transcripts: <https://www.assemblyai.com/docs/speech-to-text/universal-streaming>
- Azure Speech SDK — `Recognizing` vs `Recognized` events: <https://learn.microsoft.com/azure/ai-services/speech-service/get-started-speech-to-text>
- Apple `SFSpeechRecognitionResult.isFinal` documentation: <https://developer.apple.com/documentation/speech/sfspeechrecognitionresult/1649463-isfinal>
- Soniox — per-token finalisation: <https://soniox.com/docs/>
- Speechmatics — partial vs final transcript messages: <https://docs.speechmatics.com/rt-api-ref>
- Web Speech API `SpeechRecognitionResult.isFinal`: <https://developer.mozilla.org/docs/Web/API/SpeechRecognitionResult/isFinal>
- Background on incremental ASR (Schlangen & Skantze, *A General, Abstract Model of Incremental Dialogue Processing*): <https://aclanthology.org/E09-1081/>
- FastEmit — training-time technique for low-latency streaming emission: <https://arxiv.org/abs/2010.11148>
- Related in this workspace:
  - [`whisper-vs-streaming-asr-for-dictation`](whisper-vs-streaming-asr-for-dictation.md) — the model architecture that makes revisable partials possible.
  - [`streaming-vs-batch-injection`](streaming-vs-batch-injection.md) — what to do with interim results when feeding a focused application.
