# Glossary

A consolidated reference for the terminology used across this workspace.

Entries are alphabetical. Each entry gives the canonical term, common synonyms, a short definition, and the `ideas/` files where the term is discussed in depth.

This file is rebuilt from the contents of `ideas/` by the `/glossary` command — don't hand-edit speculative entries, add them to a guide first and let `/glossary` pull them in.

---

## A

### Anchored overlay
*Synonyms: inline preview, floating dictation overlay.*
A non-modal UI element that displays the streaming transcript near the original caret position. Nothing is committed to the underlying app until the user explicitly accepts (Enter, hotkey, click). Sidesteps focus-loss races at the cost of breaking the "transparent typing" illusion.
*See:* [focus-loss-during-dictation](ideas/focus-loss-during-dictation.md)

## B

### Batch ASR
*See* **Offline ASR**.

### Bracketed paste mode
A terminal escape-sequence convention (`ESC [ 200 ~ … ESC [ 201 ~`) that lets terminals distinguish pasted text from typed input, suppressing interpretation of control characters in the pasted block. Important for any dictation tool injecting into terminals.
*See:* [focus-loss-during-dictation](ideas/focus-loss-during-dictation.md)

## C

### Capture-target, defer-inject
A focus-loss mitigation pattern: at dictation start, capture the focused window (and where possible the caret), then refuse to inject if focus has moved, holding the transcript until the original target regains focus.
*See:* [focus-loss-during-dictation](ideas/focus-loss-during-dictation.md)

### Chunked injection
*Synonyms: segment injection, chunked-offline injection.*
A middle-ground injection mode where the tool segments audio at VAD pauses, transcribes each segment with an offline model, and injects each segment as it completes. Looks live to the user but is batch-on-each-chunk under the hood.
*See:* [streaming-vs-batch-injection](ideas/streaming-vs-batch-injection.md)

### Clipboard fallback
The standard focus-loss mitigation: in addition to (or instead of) injecting at the cursor, place the transcript on the clipboard so it can be recovered with one paste even if the keystrokes landed in the wrong window.
*See:* [focus-loss-during-dictation](ideas/focus-loss-during-dictation.md)

### Commit-on-pause
A finalization policy where the recognizer treats a configurable silence interval as the end of an utterance and commits the accumulated text. Often paired with hands-free / VAD-gated dictation.

### Commit-on-stop
*See* **Utterance-final injection**.

### Confirmation-on-mismatch
A focus-loss pattern: inject only if the focused window matches the captured target; on mismatch, fall back to overlay or clipboard with a notification rather than silently injecting elsewhere.
*See:* [focus-loss-during-dictation](ideas/focus-loss-during-dictation.md)

## E

### Endpointing
The act of deciding "the user has finished a segment" in a streaming ASR system — usually VAD-driven (silence threshold) or model-internal. Outputs a finalization event that flips partial hypotheses into finals. Often the hidden UX dial behind "this tool feels wrong" complaints.
*See:* [streaming-vs-batch-injection](ideas/streaming-vs-batch-injection.md)

## F

### Final hypothesis
*Synonyms: stable token, finalized result.*
A piece of streaming ASR output that the model has committed to and will not revise. The safe unit to inject incrementally into the focused window.
*See:* [streaming-vs-batch-injection](ideas/streaming-vs-batch-injection.md)

## H

### Hands-free dictation
*Synonym: VAD-gated dictation.*
A dictation mode with no explicit start/stop key — the recognizer is always listening, and VAD plus endpointing decide when an utterance begins and ends. Forces incremental injection because there's no discrete "stop" event.

### Hold-to-dictate
*See* **Push-to-talk**.

## I

### Incremental injection
*Synonyms: streaming injection, live commit, type-as-you-speak.*
An injection mode where the dictation tool types into the focused window as soon as the recognizer emits tokens (usually finals; sometimes partials, with risk). Produces the on-the-fly "text appears as you speak" experience.
*See:* [streaming-vs-batch-injection](ideas/streaming-vs-batch-injection.md)

## L

### Live dictation
*Synonym: real-time dictation.*
Marketing term for the combination of streaming ASR and incremental injection — text appears at the cursor as the user speaks. Examples: Apple Live Dictation, Google Live Caption + dictation, Talon Voice in dictation mode.
*See:* [streaming-vs-batch-injection](ideas/streaming-vs-batch-injection.md)

## O

### Offline ASR
*Synonyms: batch ASR, non-streaming ASR, full-context ASR.*
A speech recognizer that requires the full utterance (or a long enough chunk) before producing a transcript. Generally higher accuracy than streaming counterparts because it can use bidirectional context. Whisper, the offline NVIDIA Parakeet checkpoints (e.g. `parakeet-tdt-0.6b-v2`), and most leaderboard-leading models are offline.
*See:* [streaming-vs-batch-injection](ideas/streaming-vs-batch-injection.md)

## P

### Partial hypothesis
*Synonyms: partial token, non-final result.*
The streaming ASR model's current best guess for what's been said so far. Mutable — will be replaced as more audio arrives. Generally not safe to inject into the underlying app; safer to display in an overlay only.
*See:* [streaming-vs-batch-injection](ideas/streaming-vs-batch-injection.md)

### Push-to-talk
*Synonyms: PTT, hold-to-dictate.*
A dictation mode where the user holds a key (or button) while speaking and releases it to commit. Removes the focus-loss race for short utterances because the user is physically engaged with the tool.

## S

### Streaming ASR
*Synonyms: online ASR, incremental ASR.*
A speech recognizer designed to consume audio as a stream and emit incremental hypotheses (partials, then finals) as audio frames arrive. Required for true real-time dictation. Architectures: streaming RNN-T, streaming Conformer-CTC, monotonic chunkwise attention, Moonshine, NVIDIA Parakeet streaming configurations.
*See:* [streaming-vs-batch-injection](ideas/streaming-vs-batch-injection.md)

### Streaming overlay
A floating UI surface that shows the live transcript as it's being recognized, separate from the target text field. May or may not also commit text into the target.

## T

### Toggle-and-transcribe
*See* **Utterance-final injection**.

### Toggle-dictation
A dictation mode where one keypress starts the session and another (or the same) ends it. Distinct from push-to-talk in that the user is not physically holding anything during the session — leaving more room for focus loss.

## U

### Utterance-final injection
*Synonyms: commit-on-stop, toggle-and-transcribe, deferred injection, batch injection, post-hoc dictation.*
An injection mode where nothing is typed until the user signals "done" (toggle off, release PTT, long silence). The full transcript is then injected in one operation. Pairs naturally with offline ASR and is the typical pattern for Whisper- or Parakeet-backed hotkey dictation tools.
*See:* [streaming-vs-batch-injection](ideas/streaming-vs-batch-injection.md)

## V

### VAD
*Voice Activity Detection.*
A signal-processing component that classifies audio frames as speech or non-speech. Used to gate the recognizer (start/stop), to chunk audio for chunked-offline injection, and to drive endpointing in streaming ASR. Common implementations: WebRTC VAD, Silero VAD.
*See:* [streaming-vs-batch-injection](ideas/streaming-vs-batch-injection.md)
