# Local STT engines and silence handling — which ones have built-in VAD, which need it bolted on, and which sidestep the problem architecturally

**Question:** [`questions/local-stt-builtin-vad.md`](../questions/local-stt-builtin-vad.md)
**Written:** 14/04/26
**Stack:** Linux desktop (Ubuntu 25.10 / KDE / Wayland), local inference, live dictation use case where the user pauses mid-thought for seconds at a time.

## TL;DR

For a pause-for-thought dictator on a local stack, the question "will it hallucinate during my thinking silences?" has three possible answers depending on how the engine is built:

1. **Built-in VAD / endpointer** — the engine itself gates silence before the model sees it, or the model emits an explicit end-of-utterance token. **Vosk, NeMo streaming Conformer/FastConformer, sherpa-onnx / sherpa-ncnn, Wenet, Riva**. These are safe by default.
2. **Bundled-but-optional VAD** — the engine is a Whisper-family wrapper that ships a VAD under a flag. Off by default on some, on by default on others. **faster-whisper (`vad_filter=True`), whisper.cpp (`--vad-model`), WhisperX, whisper-streaming, Whispering, nerd-dictation, Handy.** Safe *if you enable the flag.*
3. **No VAD, no endpointer, will hallucinate on silence** — raw Whisper in any form with VAD disabled, Moonshine in its base form, raw `openai-whisper` Python package, Silero STT. These require an external VAD in front of them or they will emit "Thank you for watching" / "." / "Bye!" / translated-language noise during your pauses.

The alternative architecture that **sidesteps VAD entirely** is **push-to-talk** (hold a key while speaking) — the mic is hardware-gated by the user, so there is no silence to hallucinate on. This is why Talon, nerd-dictation (in PTT mode), many Whisper-keyboard tools, and every "hold Fn to dictate" macOS/Windows built-in work reliably without any VAD logic: the user *is* the VAD.

## Background — what "silence hallucination" is and why it matters for dictation

Whisper and Whisper-family models were trained on 30-second windows of audio scraped from YouTube, podcasts, and similar sources. A large fraction of those clips contain speech throughout. When Whisper is fed a 30-second window that is actually silence or low-level background noise, it has no "no-speech" class to fall back on — it decodes into whatever token sequence is statistically most likely, which turns out to be things like:

- `Thank you for watching.`
- `Subscribe to the channel.`
- `.` (a single period, repeated)
- `Bye!`
- Entire sentences in Welsh, Korean, or Portuguese.
- The previous utterance, repeated (a failure mode called "repetition loop").

This is **well-documented** (Koenecke et al., "Careless Whisper," FAccT 2024) and **reproducible** — feed `faster-whisper` 10 seconds of room tone with `vad_filter=False` and you will get hallucinated text.

For a dictator who **pauses to think mid-sentence**, this is catastrophic:

- Every thinking pause becomes a potential insertion of garbage text into the focused window.
- If the injector commits partials as they arrive, the garbage gets typed *into the user's document*.
- Correction workflow has to assume any given span could be model hallucination rather than user speech — which destroys trust in the tool.

So "does this engine prevent silence hallucinations?" is one of the single most important questions when choosing a local STT stack for live typing. It sits above model accuracy, above latency, above GPU story.

## Engines that handle silence *architecturally*

These engines either do not use a Whisper-style batch decoder, or they have an explicit endpointing / VAD stage that prevents silence from reaching the acoustic model.

### Vosk (Kaldi under the hood)

- **Mechanism**: Kaldi's decoder has a built-in silence model and endpointing logic. `KaldiRecognizer.AcceptWaveform(chunk)` returns `True` when an utterance boundary is detected; `PartialResult()` and `FinalResult()` give you text only when there was actual speech.
- **Silence behaviour**: no hallucination. Silence produces empty strings. Pausing mid-dictation is safe by default — the decoder just holds the partial and waits.
- **Tradeoffs**: Kaldi acoustic models are older than Whisper; accuracy on casual conversational English is noticeably lower than Whisper-large. But it is bulletproof on silence.
- **Best fit**: a "no-hallucination-ever" constraint matters more than peak WER.

### NVIDIA NeMo — streaming Conformer / FastConformer / Parakeet streaming

- **Mechanism**: RNN-T / CTC streaming models with an integrated endpointing head that emits probabilities per frame. The decoder only outputs tokens when the frame is classified as speech with sufficient confidence.
- **Silence behaviour**: genuine non-emission on silence. No hallucination.
- **Caveat**: the *offline* Parakeet TDT models (the ones most commonly benchmarked for their sub-Whisper WER) are **batch** and do not have the same protection. The streaming variants (`stt_en_fastconformer_hybrid_large_streaming_multi`, etc.) are the ones with the endpointing behaviour.
- **Best fit**: serious live dictation on NVIDIA hardware; willing to run NeMo/Riva.

### sherpa-onnx / sherpa-ncnn (k2-fsa project)

- **Mechanism**: wraps streaming RNN-T Zipformer models plus an explicit Silero-VAD ONNX pass. The recognizer API has `is_endpoint(stream)` that returns `True` after configurable silence.
- **Silence behaviour**: silence is gated by Silero VAD; the acoustic model sees only speech segments; endpointing flushes finals on pauses.
- **Tradeoffs**: excellent on-device footprint (runs well on Raspberry Pi, Android, WASM); English models are solid but not Whisper-class on hard domains.
- **Best fit**: low-latency live typing, especially on modest hardware or when you need a single binary with no Python.

### Wenet

- **Mechanism**: CTC/AED hybrid with built-in endpointing. Similar story to NeMo — the streaming decoder emits tokens only when there's classified speech.
- **Best fit**: research / Chinese-English bilingual dictation; less common than NeMo in English-first setups.

### NVIDIA Riva (self-hostable)

- Same streaming Conformer family as NeMo, packaged as a Triton-based service. Two-pass endpointing is built in.
- **Best fit**: multi-user / long-running daemon; overkill for a single-user desktop tool.

### Silero STT

- Ships from the same authors as Silero VAD, so the model and VAD are designed together. English models are CTC-based with explicit handling of non-speech.
- **Caveat**: Silero STT is not commonly used for English desktop dictation — the maintained English models are older, and the Whisper ecosystem has eclipsed it. Worth being aware of but not a first choice in 2026.

## Engines that ship with VAD bundled but *optional*

These are Whisper-family wrappers. They do not have architectural silence handling — Whisper itself cannot emit "no speech" reliably — but they ship a VAD wrapper. If the flag is on, silence is gated before Whisper ever sees it. If the flag is off, you get hallucinations.

### faster-whisper (CTranslate2)

- Flag: `transcribe(audio, vad_filter=True, vad_parameters=dict(min_silence_duration_ms=500))`.
- VAD model: **Silero VAD** (bundled in the package since v0.9).
- **Default**: `vad_filter=False` — i.e. off by default. **This is the single most common source of "why is my Whisper hallucinating" bug reports.** Always turn it on for live dictation.
- Once enabled, hallucination on silence is almost entirely eliminated.

### whisper.cpp

- Flag: `./main --vad --vad-model models/silero-v5.1-small.onnx ...`.
- VAD model: Silero, loaded as an ONNX file.
- **Default**: off. Must be enabled explicitly.
- The `stream` example (the sliding-window live-ish mode) has its own energy-based gating that is cruder than Silero; for a real live-typing tool use the Silero ONNX flag.

### WhisperX

- Silero VAD (or pyannote VAD, configurable) is used for **segment boundaries** — it's integral to how the pipeline works, not optional.
- Silence doesn't produce hallucination output because silent regions aren't fed to Whisper.
- Caveat: WhisperX is batch-oriented (diarization, word-level alignment) — not the natural choice for live typing.

### whisper-streaming (ufal)

- VAD-gated chunks by default. The reference implementation uses Silero VAD (or WebRTC VAD as fallback) to decide when to flush to Whisper.
- Well-suited to pause-for-thought dictation out of the box.

### Handy

- Desktop Whisper-keyboard app; uses VAD gating on its hands-free mode.
- Push-to-talk mode sidesteps VAD entirely.
- See [`ideas/live-typing-models-saas-and-local.md`](live-typing-models-saas-and-local.md) for where it sits in the landscape.

### nerd-dictation (Linux)

- Built on Vosk, so inherits Vosk's architectural silence handling — no Whisper in the default path.
- Even in its optional Whisper-backend modes, VAD gating is present.
- Push-to-talk is the canonical usage.

### Whispering, Dictation, WisprFlow, SuperWhisper, MacWhisper, Aqua, Wispr Flow

- All are Whisper-family desktop tools with VAD baked into their pipeline. They would be unusable without it, so it's not optional at the user level.
- Push-to-talk is typically the default UX; hands-free mode when offered is VAD-gated.

## Engines that do NOT handle silence — will hallucinate without external VAD

### Reference `openai-whisper` (the original Python package)

- No VAD. `whisper.transcribe("audio.wav")` will hallucinate on silence.
- Has a `no_speech_threshold` (default 0.6) and `logprob_threshold` — these are **per-30-second-segment heuristics**, not a real VAD. They reduce but do not eliminate silence hallucinations, and they're unreliable on short clips.
- **Only safe for live dictation if you put a VAD in front of it yourself.**

### Moonshine (Useful Sensors, base form)

- Small streaming-friendly encoder-decoder. No built-in VAD or endpointer.
- The reference demo apps pair it with Silero VAD; without that pairing it will hallucinate on silence like Whisper does.
- Good choice for live typing **only if you wire Silero in front.**

### Distil-Whisper

- Smaller, faster Whisper distillation. Inherits Whisper's lack of VAD exactly.
- Same fix: pair with Silero, or run it via faster-whisper with `vad_filter=True`.

### Parakeet TDT (the offline / batch variants)

- High-accuracy NVIDIA NeMo models, but the offline variants are batch and do not endpoint. They can and do hallucinate on long silent regions.
- For live typing, pick the **streaming** Parakeet / FastConformer variants, not the offline TDT ones.

### Canary (NVIDIA)

- Multilingual offline model. Same story as Parakeet TDT — no streaming endpointer; needs external VAD for live use.

## The alternative architecture — push-to-talk makes VAD almost unnecessary

A fundamentally different way to prevent silence hallucinations: **don't capture silence in the first place.**

- User holds a hotkey (or foot pedal, or push-button) while speaking.
- Mic is opened on keydown, closed on keyup.
- Whatever audio is captured is (by definition) intended speech.
- Thinking pauses happen with the key released — no audio captured, nothing to hallucinate on.

This is the reason **Talon**, **nerd-dictation (in PTT mode)**, **most Whisper-keyboard tools**, **macOS Dictation's "Fn Fn" hold-to-dictate**, and **every foot-pedal medical dictation setup for the last 40 years** works without sophisticated silence handling. The user is providing the VAD with their finger.

Tradeoffs relative to hands-free + VAD:

- **Pro**: zero hallucination risk, zero VAD tuning, zero false commits on coughs / keyboard noise / TTS playing in another window.
- **Pro**: extremely simple to implement. One global hotkey + `sounddevice.InputStream` context manager.
- **Con**: requires a hand on a key. Breaks accessibility use cases where hands-free is the whole point.
- **Con**: can't do true long-form dictation without holding the key indefinitely; usually paired with a toggle mode as an escape hatch.

For a pause-for-thought dictator, push-to-talk + release-on-pause is arguably the **correct default** — you think with the key up and speak with the key down. The "pause for thought" problem becomes a non-problem because silence is never in the capture buffer.

See [`ideas/voice-dictation-hotkey-count-tradeoffs.md`](voice-dictation-hotkey-count-tradeoffs.md) for the ergonomic side of this.

## Quick reference table

| Engine | Silence handling | What to do for safe live typing |
|---|---|---|
| Vosk | Built-in (Kaldi endpointer) | Use as-is |
| NeMo streaming Conformer / FastConformer | Built-in endpointing head | Use streaming variants, not offline TDT |
| sherpa-onnx / sherpa-ncnn | Built-in (Silero + endpoint API) | Use as-is |
| Wenet | Built-in CTC endpointing | Use as-is |
| Riva | Built-in two-pass endpointing | Use as-is |
| Silero STT | Trained with VAD-aware data | Viable but ecosystem is thin |
| faster-whisper | Optional (Silero, off by default) | `vad_filter=True` always |
| whisper.cpp | Optional (Silero ONNX, off by default) | `--vad --vad-model silero...onnx` |
| WhisperX | VAD integral to pipeline | Use as-is (but batch, not live) |
| whisper-streaming | VAD-gated by default | Use as-is |
| Handy / Whispering / WisprFlow / etc. | VAD baked in | Use as-is |
| nerd-dictation | Vosk-backed, or VAD-gated Whisper | Use as-is |
| `openai-whisper` (reference) | None | Add Silero VAD in front, or switch to faster-whisper |
| Moonshine (base) | None | Add Silero VAD in front |
| Distil-Whisper | None (inherits Whisper) | `vad_filter=True` via faster-whisper |
| Parakeet TDT (offline) | None | Switch to streaming FastConformer, or add VAD |
| Canary | None | Add VAD |

## Recommendation for this workspace

For a pause-for-thought live-typing prototype on Linux:

1. **If push-to-talk is acceptable UX**: skip the VAD debate entirely. Bind a hotkey, open the mic only while held, feed whatever you captured to any local Whisper. Hallucinations become a non-issue.
2. **If hands-free is required**: pick an engine with **architectural** silence handling — **sherpa-onnx** (lightweight, streaming, native endpointing) or **faster-whisper with `vad_filter=True` always on** (best WER, Silero bundled). Do not use raw `openai-whisper`, raw Moonshine, or offline Parakeet TDT for hands-free dictation.
3. **Do not rely on Whisper's `no_speech_threshold` alone.** It's a heuristic, not a VAD. It will leak silence hallucinations into live output.
4. **Expose VAD sensitivity as a UX setting**, not a buried config. Silence-end threshold (500–800 ms typical) directly shapes how long a thinking pause can be before the system commits prematurely.

## References

- Koenecke et al., "Careless Whisper: Speech-to-Text Hallucination Harms" (FAccT 2024) — https://dl.acm.org/doi/10.1145/3630106.3658996
- Silero VAD — https://github.com/snakers4/silero-vad
- faster-whisper VAD filter — https://github.com/SYSTRAN/faster-whisper
- whisper.cpp VAD flag — https://github.com/ggerganov/whisper.cpp
- Vosk API (endpointing via `AcceptWaveform`) — https://github.com/alphacep/vosk-api
- NVIDIA NeMo streaming ASR — https://docs.nvidia.com/deeplearning/nemo/user-guide/docs/en/main/asr/models.html
- sherpa-onnx (streaming + VAD + endpointing) — https://github.com/k2-fsa/sherpa-onnx
- Moonshine — https://github.com/usefulsensors/moonshine
- Companion topic: [`ideas/vad-for-live-typing.md`](vad-for-live-typing.md)
- Companion topic: [`ideas/local-stt-inference-engines-gpu.md`](local-stt-inference-engines-gpu.md)
- Companion topic: [`ideas/whisper-vs-streaming-asr-for-dictation.md`](whisper-vs-streaming-asr-for-dictation.md)
