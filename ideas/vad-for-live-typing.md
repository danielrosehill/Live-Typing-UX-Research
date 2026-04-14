# VAD for live typing: what's native, what's bolted on, and how to wire them together

**Question:** [`questions/vad-for-live-typing.md`](../questions/vad-for-live-typing.md)
**Written:** 14/04/26
**Stack:** Linux desktop (Ubuntu 25.10 / KDE / Wayland), local + cloud ASR, Python/Node prototypes feeding text into the focused window.

## TL;DR

VAD is a small, cheap classifier that says "voice / not voice" on short audio frames (10–30 ms). It is essential for hands-free live typing because it tells the system **when to start sending audio to the ASR**, **when an utterance has ended**, and **when to commit the final transcript and release the cursor**.

- **Whisper has no real VAD.** It hallucinates on silence and has no concept of "is the user still talking." Anything Whisper-based that behaves nicely (whisper.cpp, faster-whisper, WhisperX, whisper-streaming, whispering) is using an **external VAD** in front of it — almost always **Silero VAD** or **WebRTC VAD**.
- **Streaming ASR services do have native endpointing** (Deepgram, AssemblyAI, Soniox, Speechmatics, Google Cloud STT, NVIDIA Riva). They expose it as `endpointing_ms`, `utterance_end_ms`, `vad_events`, etc. This is genuinely native — the same model emits both partial tokens and an end-of-utterance signal.
- **For local pipelines, the standard recipe is Silero VAD → faster-whisper / NeMo / Vosk**, glued together in Python with `sounddevice` / `pyaudio` for capture and asyncio (or two threads + a queue) to keep VAD running while the ASR processes the previous chunk.

The "parallel succession" is not really parallelism in the GPU sense — it's a **producer/consumer pipeline**: VAD runs continuously on the mic stream and emits "speech start" / "speech end" events; the ASR consumes finalized speech segments. Single-process Python is fine; a worker thread per stage is the typical shape.

## Background — why VAD matters specifically for live typing

In a live-typing UI you need to answer four operational questions, in order:

1. **Should I open the mic at all?** (push-to-talk solves this; hands-free needs a wake mechanism, often a hotkey or the VAD itself.)
2. **Has the user actually started speaking?** — needed so the overlay can flip from "listening" to "transcribing" without flicker on background noise.
3. **Has the user paused mid-sentence, or finished?** — the difference between "stabilize the partial and keep the stream open" vs. "commit the transcript, inject it, release focus."
4. **Has the room gone quiet long enough that I should close the mic?** — for battery, privacy indicator, and to stop the streaming-ASR meter running.

Pure ASR doesn't answer (2)–(4) reliably. Confidence scores and partial-token churn are noisy proxies. A dedicated VAD does answer them, cheaply (Silero VAD is ~1 MB and runs on CPU at hundreds of times realtime).

This is why every serious dictation tool — Talon, nerd-dictation, WisprFlow, MacWhisper, SuperWhisper, the Whisper-based Linux tools, even Apple/Google's built-in dictation — has a VAD or endpointer somewhere in the pipeline. The only difference is whether it's a separate component or fused into the ASR.

## What "native VAD" actually means in different ASR systems

### Whisper (OpenAI, and all derivatives) — no native VAD

Whisper is a **batch encoder–decoder** trained on 30-second windows. It has no notion of voice activity:

- It will happily decode pure silence and emit hallucinated text ("Thank you for watching", "Subscribe to the channel" — these are real, well-documented hallucinations from YouTube training data).
- Its `no_speech_prob` is a per-segment heuristic, not a frame-level VAD. It's unreliable below ~1 second of audio.
- It does not produce partials or endpointing events. There is no streaming protocol.

Every "live Whisper" tool wraps it with an external VAD that:

1. Gates the recorder so silence is never sent to the model.
2. Buffers speech segments and flushes them to Whisper either on a fixed cadence (e.g. every 2 s of speech) or on detected silence (e.g. 700 ms of non-speech).
3. Optionally trims silence from the head/tail of each segment before inference.

Reference implementations: **WhisperX** uses Silero VAD for diarization and segment boundaries; **whisper-streaming** (ufal) uses VAD-gated chunks; **whisper.cpp** has a `--vad-model` flag accepting a Silero ONNX file; **faster-whisper** has a `vad_filter=True` option that bundles Silero internally; **Whispering** and similar desktop tools all do the same.

### Streaming cloud ASR — VAD is genuinely native

The big streaming providers ship endpointing as a first-class feature:

- **Deepgram** — `endpointing` (ms of silence before final), `utterance_end_ms`, and a separate `vad_events: true` that emits `SpeechStarted` messages on the WebSocket.
- **AssemblyAI Universal-Streaming** — `end_of_turn_confidence`, `min_end_of_turn_silence_when_confident`, `max_turn_silence`. Tunable per-session.
- **Soniox** — emits `<end>` tokens in the response stream when it detects an utterance boundary.
- **Speechmatics** — `end_of_utterance_silence_trigger` parameter; emits `EndOfUtterance` messages.
- **Google Cloud Speech-to-Text v2** — `voice_activity_events: true` plus `voice_activity_timeout` for begin/end-of-speech callbacks.
- **NVIDIA Riva** (self-hostable) — built-in two-pass endpointing in the streaming recognizer.

Whether this is one model or two internally varies — Deepgram's Nova models are RNN-T / Conformer streaming architectures where the model itself emits an end-of-utterance probability per frame; Google historically ran a separate VAD alongside the recognizer. From the API surface it doesn't matter; you get partial transcripts and endpointing events from a single connection.

### Other open-source streaming ASR

- **NVIDIA NeMo** streaming Conformer / FastConformer models include an endpointing head; `nemo.collections.asr` exposes it.
- **Vosk** (Kaldi-based) has its own internal endpointer, exposed via `KaldiRecognizer.AcceptWaveform()` returning `True` on utterance end.
- **Wenet** has CTC-based endpointing built in.
- **Silero** publishes both an STT model line and a VAD, but its STT is not commonly used for English desktop dictation.
- **Moonshine** (Useful Sensors, 2024) — small streaming-friendly model; no native VAD, paired with Silero in their reference apps.

### Apple / Microsoft built-ins

- **macOS Dictation** uses Apple's own on-device VAD + ASR (since 13.0 the ASR is fully local for many languages). Endpointing is internal, controlled by the OS, not user-tunable.
- **Windows Voice Access / Speech Recognition** uses an internal endpointer; same story.

## Pairing a separate VAD with an ASR — the standard pipelines

For a Linux desktop live-typing tool built on Whisper or any non-endpointing ASR, the canonical pipeline is:

```
mic → resample to 16 kHz mono → ring buffer
        ↓
       VAD (every 30 ms frame)
        ↓
   speech segmenter (start on N speech frames, end on M silence frames)
        ↓
   completed segment → ASR worker → text → injector
```

### Components people actually use

**VAD models:**

- **Silero VAD** (ONNX, ~1.5 MB, MIT licensed) — the de facto default. Frame-level, multilingual, runs on CPU at ~0.5 ms per 30 ms frame. Repo: `snakers4/silero-vad`.
- **WebRTC VAD** — older, signal-processing based (not ML), four aggressiveness levels (0–3). Built into Chromium and exposed via the `webrtcvad` Python binding. Lower quality than Silero, but zero dependencies and microscopically light.
- **pyannote VAD** / **pyannote/segmentation-3.0** — heavier, designed for offline diarization. Overkill for live typing but widely used in research.
- **TEN-VAD** (2024–25) — a newer transformer-based VAD positioned as a Silero alternative; worth tracking but Silero is still the default.

**ASR engines paired with the above:**

- **faster-whisper** (CTranslate2 backend) — `WhisperModel(...).transcribe(audio, vad_filter=True)` bundles Silero internally; or pass pre-segmented chunks yourself.
- **whisper.cpp** — `./main -m model.bin --vad-model silero-v5.1-small.onnx audio.wav`. Native C++ pipeline, lowest dependency footprint.
- **NVIDIA NeMo** — has its own endpointing; you can also stack Silero in front for tighter UX control.
- **Vosk** — endpointing built in; no external VAD needed.

### Inference engines / runtimes

The two stages typically run in the same Python (or C++) process:

- **VAD runtime**: ONNX Runtime (`onnxruntime`) for Silero — CPU-only is more than enough. PyTorch is also fine but heavier to load.
- **ASR runtime**: depends on the model.
  - **CTranslate2** for faster-whisper (CPU/CUDA/Metal).
  - **whisper.cpp** uses GGML (CPU + optional CUDA / Metal / Vulkan / SYCL).
  - **PyTorch** for vanilla openai-whisper, NeMo, pyannote.
  - **TensorRT** / **Triton Inference Server** if you're scaling beyond a single user.

You don't need a special "dual-model orchestrator." VAD is so cheap that it runs in the audio capture thread; the ASR runs in a worker thread or `asyncio` task and consumes finished segments off a queue.

### Concrete glue patterns

**Pattern A — single-process Python, two threads (most common):**

```python
# pseudo-shape, not a working snippet
audio_q  = queue.Queue()    # raw 30 ms frames from sounddevice callback
seg_q    = queue.Queue()    # completed speech segments

def vad_loop():
    state = "silence"
    buf = []
    for frame in iter(audio_q.get, None):
        is_speech = silero_vad(frame)              # ~0.5 ms
        # state machine: silence ↔ speech with hangover
        # on speech end, push np.concatenate(buf) to seg_q

def asr_loop():
    for segment in iter(seg_q.get, None):
        text = whisper_model.transcribe(segment)   # tens of ms to seconds
        injector.inject(text)
```

This is exactly the structure used by nerd-dictation, whispering, and most "Whisper as keyboard" tools. The two stages overlap in time naturally — while the ASR is decoding utterance N, the VAD is already detecting utterance N+1.

**Pattern B — single-process asyncio (good for streaming ASR):**

When the ASR is itself streaming (Deepgram, NeMo streaming, etc.), VAD is often optional or used only as a "should I open the connection" gate. The ASR's own endpointer drives commit timing.

**Pattern C — separate processes over a socket:**

Useful when the ASR is heavy and you want it pinned to a GPU as a long-running daemon. The audio capture + VAD process sends segments over a Unix socket or gRPC; the ASR daemon returns text. This is how teams self-hosting Riva or Triton typically structure things.

## Tradeoffs and tuning

- **Aggressiveness vs. clipping.** Too sensitive a VAD (low silence threshold) clips the start of words ("ext step" instead of "next step"). Too lax (long silence threshold) makes the system feel sluggish — the user pauses, looks at the screen, nothing commits. Typical live-typing values: speech-start after 100–200 ms of speech, speech-end after 500–800 ms of silence.
- **Hangover / pre-roll.** Always keep a 200–500 ms pre-roll buffer of audio *before* VAD says "speech started," so the first phoneme isn't cut. Most VAD wrappers handle this for you.
- **Music and background TTS.** Silero handles music as non-speech reasonably well; WebRTC VAD can fire on it. If the user is on a call or has TTS playing, a desktop tool needs an additional gate (mute the mic, or use system audio routing).
- **Endpointing vs. semantic turn detection.** Silence-based VAD can't tell a thinking pause from a finished sentence. The 2024–25 trend (AssemblyAI's Universal-Streaming, Pipecat's "smart turn") is to layer a small **turn-detection model** on top of VAD that uses partial transcript content + acoustic features to predict end-of-turn. Worth being aware of even if you don't implement it yourself.
- **Wayland injection lag.** None of this matters if `ydotool` / `wtype` injection is the bottleneck. Measure end-to-end latency, not just ASR latency.

## Recommendation for this workspace

For a Linux desktop live-typing prototype:

1. **Use Silero VAD** as the front end. ONNX Runtime, ~1 MB model, ~0.5 ms per frame on CPU. Don't bother with WebRTC VAD unless you have a hard size constraint.
2. **Pick one of two ASR paths**:
   - **Local, Whisper-family**: faster-whisper with `vad_filter=True` (bundled Silero). Simplest possible setup.
   - **Streaming, cloud or self-hosted**: Deepgram / AssemblyAI / Riva — let their native endpointing do the work. VAD becomes a hotkey-gating concern, not an audio concern.
3. **Two threads + a queue** is the right concurrency model for the local path. Don't over-engineer with multiprocessing until you have measured a bottleneck.
4. **Treat VAD parameters as part of the UX**, not as model config. Silence threshold, hangover, and pre-roll all directly shape how the dictation feels — they belong in the user-facing settings, not buried in code.

## References

- Silero VAD — https://github.com/snakers4/silero-vad
- faster-whisper VAD filter — https://github.com/SYSTRAN/faster-whisper#voice-activity-detection-filter
- whisper.cpp VAD support — https://github.com/ggerganov/whisper.cpp (`--vad-model` flag, README)
- Deepgram endpointing & VAD events — https://developers.deepgram.com/docs/endpointing
- AssemblyAI Universal-Streaming end-of-turn — https://www.assemblyai.com/docs/speech-to-text/universal-streaming
- Google Cloud STT voice activity events — https://cloud.google.com/speech-to-text/v2/docs/voice-activity-events
- Speechmatics end-of-utterance — https://docs.speechmatics.com/features/end-of-utterance
- NVIDIA Riva streaming ASR — https://docs.nvidia.com/deeplearning/riva/user-guide/docs/asr/asr-overview.html
- Vosk endpointing — https://github.com/alphacep/vosk-api
- WebRTC VAD Python — https://github.com/wiseman/py-webrtcvad
- Pipecat smart turn detection — https://github.com/pipecat-ai/pipecat
- Whisper hallucination on silence (paper) — Koenecke et al., "Careless Whisper" (2024)
