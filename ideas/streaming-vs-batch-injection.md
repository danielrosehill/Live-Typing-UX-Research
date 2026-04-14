# Streaming injection vs utterance-final injection in live dictation

**Question:** [`questions/streaming-vs-batch-injection.md`](../questions/streaming-vs-batch-injection.md)
**Written:** 14/04/26
**Stack:** Desktop live voice typing (real-time speech-to-text injecting into the focused window). NVIDIA Parakeet (RNNT/CTC/TDT family) used here as the example offline model; the same axis applies to Whisper, Vosk, Moonshine, faster-whisper, etc.

## TL;DR

Two orthogonal axes are at play. **Axis 1** is the *recognition mode*: **streaming ASR** (the model emits hypotheses as audio arrives) vs **offline / batch ASR** (the model needs the whole utterance before it produces output). **Axis 2** is the *injection mode*: **incremental / streaming injection** (text is typed at the cursor as hypotheses arrive) vs **utterance-final / commit-on-stop injection** (the full transcript is typed once, after dictation ends). The pattern you're describing — text appearing on the fly — is **streaming ASR + incremental injection**, often marketed as "live dictation" or "real-time dictation". Your current Parakeet setup is **offline ASR + utterance-final injection**, sometimes called **commit-on-stop**, **toggle-and-transcribe**, or just **batch dictation**.

## Background

Desktop dictation tools differ along two axes that beginners often conflate:

1. **What the speech recognizer can do.** Some ASR systems are designed to consume audio as a stream and emit incremental hypotheses (partial tokens that may be revised, then "stabilised" as final). Others are designed to consume a complete audio segment and emit one finalized transcript. The first is *streaming*; the second is *offline* (also called *batch*, *non-streaming*, or *full-context*).
2. **What the dictation tool does with the output.** Even a streaming recognizer can be wired to a "wait until the user stops, then type everything" UX. Conversely, an offline recognizer can be made to feel more "live" by chunking audio at VAD boundaries and committing one chunk at a time. The injection policy is a separate decision from the recognizer's capability.

So there are four cells in the matrix, not two. Most tools sit in one of three of them; the fourth is rare in practice.

## The terminology

### Recognition mode (Axis 1)

- **Streaming ASR** — the model emits incremental hypotheses as audio frames arrive. Architectures designed for this: streaming RNN-T, streaming Conformer-CTC, monotonic chunkwise attention, Moonshine, streaming variants of NVIDIA Parakeet (Parakeet-RNNT and Parakeet-TDT have streaming configurations; the popular `parakeet-tdt-0.6b-v2` checkpoint is offline-only). Also sometimes called **online ASR** or **incremental ASR**.
- **Offline ASR** — the model needs the full utterance (or at least a long enough chunk) before it produces output. Whisper (the original OpenAI release) is offline by design. Most "highest WER score on Open ASR Leaderboard" models are offline. Synonyms: **batch ASR**, **non-streaming ASR**, **full-context ASR**.

Inside the streaming family, two sub-terms matter:

- **Partial hypothesis** (or **partial token**, **non-final result**) — the model's current best guess for what's been said so far. Mutable; will be replaced as more audio arrives.
- **Final hypothesis** (or **stable token**, **finalized result**) — the model has committed; this part of the transcript will not be revised.
- **Endpointing** — the act of deciding "the user has finished a segment." Usually VAD-driven (silence threshold) or model-internal. The output of endpointing is a *finalization event* that flips partials into finals.

### Injection mode (Axis 2)

- **Incremental injection** (also: **streaming injection**, **live commit**, **type-as-you-speak**) — the dictation tool types into the focused window as soon as the recognizer emits tokens (usually finalized ones; some tools also display partials in an overlay without committing them to the underlying app).
- **Utterance-final injection** (also: **commit-on-stop**, **toggle-and-transcribe**, **deferred injection**, **batch injection**, sometimes simply **post-hoc dictation**) — nothing is typed until the user signals "done" (toggle off, release PTT key, long silence). The full transcript is then injected in one operation.
- **Chunked / segment injection** — a middle ground: the tool segments the audio at VAD pauses, transcribes each segment offline, and injects each segment as it completes. From the user's perspective this *looks* live, but under the hood it's batch-on-each-chunk. This is how a lot of "live" Whisper-based tools (e.g. wispr-style frontends) actually work.

### The four-cell matrix

| | Incremental injection | Utterance-final injection |
|---|---|---|
| **Streaming ASR** | True real-time dictation. Apple Live Dictation, Google Live Caption + dictation, Talon Voice (in dictation mode), Dragon NaturallySpeaking. | Streaming under the hood but batched at the UI — used when the developer wants stable text only. Less common; generally a wasted capability. |
| **Offline ASR** | Approximated via VAD chunking — appears live, isn't really. Many Whisper-based tools (Whispering, MacWhisper streaming mode, some `nerd-dictation` configs). | Toggle-and-transcribe. **This is your current Parakeet setup.** Also: most "press hotkey, speak, release, get text" tools built on Whisper-large or Parakeet-TDT-0.6B. |

## What you're actually using vs what you're describing

- **Your current setup (Parakeet, toggle-mic-off, full transcript appears at once):** offline ASR + utterance-final injection. The widely-used names are **commit-on-stop** or **toggle-and-transcribe**. NVIDIA's offline Parakeet checkpoints (e.g. `parakeet-tdt-0.6b-v2`) are designed for this; they hold state-of-the-art positions on the Open ASR Leaderboard precisely because they get to see the whole utterance before deciding.
- **The "text dumps on the fly" pattern you're describing:** streaming ASR + incremental injection. Marketing usually calls this **live dictation** or **real-time dictation**. From an engineering perspective the distinguishing feature is that the recognizer emits *finalized tokens incrementally* (as opposed to one big finalization at the end), and the injector commits them as they finalize.

## Tradeoffs between the two

This is the part that matters for your "ideal UI" spec.

### Where commit-on-stop wins

- **Higher accuracy.** Offline models see the whole utterance and can use bidirectional context. Whisper-large and Parakeet-TDT-0.6B both routinely beat their streaming counterparts on WER by 1–4 points absolute. For technical dictation, that gap is significant.
- **Cleaner punctuation and capitalization.** Offline post-processing has the full sentence to work with. Streaming models often emit punctuation late or have to revise it.
- **Simpler injection.** One `wtype`/`xdotool`/SendInput call. No need to manage cursor position drift, no risk of injecting partials into apps that auto-complete or auto-format on each keystroke (think: IDE intellisense, Slack's `@` mentions, terminal readline).
- **No mid-utterance corrections visible to the user.** The user doesn't see the model "change its mind" about earlier words.
- **Plays well with focus capture.** Because injection is a single discrete event, the focus-loss mitigations from [`focus-loss-during-dictation`](focus-loss-during-dictation.md) are easier to apply.

### Where streaming + incremental injection wins

- **Perceived latency.** Even if total time-to-final-text is similar, watching the words appear feels dramatically faster and more responsive. This is the single biggest reason users prefer it for short utterances.
- **Self-correction loop.** The user can see they were misheard and stop / repeat without waiting for the full utterance to commit.
- **Long-form dictation feels less terrifying.** A 90-second commit-on-stop session producing a wall of text at once is psychologically heavier than the same content appearing as you go.
- **Better fit for hands-free / VAD-gated modes.** When there's no explicit "stop" signal, you have to commit incrementally.

### Where the cracks show in each

- **Streaming + incremental injection** breaks badly when partials get committed into apps that react to each keystroke. Typing partials into a Slack message that auto-sends on Enter, or into a terminal where each character could be a command, is dangerous. The defense is to only commit *finals*, never *partials*, into the underlying app — and show partials only in an overlay if at all.
- **Commit-on-stop** breaks when the user expects to be able to start *acting* on early parts of what they said before they're done speaking — and it makes long utterances feel like they're stuck.

## A note on Parakeet specifically

NVIDIA Parakeet is not inherently offline. The family includes:

- **Offline checkpoints** (e.g. `parakeet-tdt-0.6b-v2`, `parakeet-rnnt-1.1b`) — designed for batch transcription, what you're using.
- **Streaming checkpoints / configurations** — Parakeet-RNNT and Parakeet-TDT both have streaming variants in the NeMo framework, with configurable chunk sizes (typically 80 ms / 480 ms / 1040 ms lookahead). These give you partial + final hypotheses on a stream.

If you want to move from commit-on-stop to incremental injection while staying on Parakeet, the path is: switch to a streaming-configured Parakeet model in NeMo, consume the partial/final event stream, and only commit finals into the focused window. Expect a small accuracy regression compared to the offline checkpoint and a meaningful engineering jump in the injection layer.

## Recommended framing for the workspace's "ideal UI" spec

When cataloguing tools and patterns, treat the two axes as independent and tag each tool with both:

- Recognition mode: `streaming` | `offline` | `chunked-offline` (VAD-segmented offline)
- Injection mode: `incremental-finals` | `incremental-with-partials-overlay` | `utterance-final` | `chunked-segment`

Most user-visible behaviour is explained by the *injection* axis; most accuracy and latency tradeoffs come from the *recognition* axis. Keeping them separate avoids the common confusion of calling any tool with a Whisper backend "not real-time" — when in fact it can feel quite real-time with the right chunking and injection policy.

## Caveats / things that can go wrong

- **"Streaming" is overloaded.** Some vendors use it to mean "the API accepts a stream of audio bytes" without committing to incremental output. Check whether the API actually emits partial/final events or just one final result at the end.
- **Whisper is not streaming.** Tools that present "streaming Whisper" are doing chunked-offline with VAD. That's fine, but it's not streaming ASR in the technical sense and inherits offline's inability to revise earlier hypotheses.
- **Partial-vs-final discipline matters.** A surprising number of "live dictation" tools commit partials directly. This produces the unsettling effect of watching words rewrite themselves in your editor and can corrupt undo history.
- **Endpointing thresholds are the hidden UX dial.** Too-aggressive VAD finalization splits sentences mid-thought and loses long-range context (worse punctuation, worse capitalization). Too-lax VAD makes the tool feel laggy. Most "this tool feels wrong" complaints trace back here.
- **Latency is end-to-end, not just model.** Audio capture buffer + VAD lookahead + model RTF + injection round-trip all stack. Streaming ASR with a 1 s lookahead is not faster than offline ASR with a 200 ms RTF on a 3 s utterance.

## References

- NVIDIA NeMo ASR documentation — streaming and offline configurations: <https://docs.nvidia.com/deeplearning/nemo/user-guide/docs/en/main/asr/intro.html>
- Parakeet model card on Hugging Face (offline TDT-0.6B-v2): <https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2>
- Streaming Conformer-CTC / Conformer-Transducer reference (NeMo): <https://docs.nvidia.com/deeplearning/nemo/user-guide/docs/en/main/asr/models.html#streaming>
- Open ASR Leaderboard (offline-leaning benchmark): <https://huggingface.co/spaces/hf-audio/open_asr_leaderboard>
- Moonshine — designed for streaming on-device ASR: <https://github.com/usefulsensors/moonshine>
- Talon Voice — illustrates incremental injection done well: <https://talonvoice.com/>
- nerd-dictation — example of offline + utterance-final injection on Linux, using Vosk/Whisper backends: <https://github.com/ideasman42/nerd-dictation>
- Whispering / WhisperX-based desktop tools — examples of chunked-offline approximating streaming UX.
