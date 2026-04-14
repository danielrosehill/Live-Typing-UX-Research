# Why Whisper isn't built for live dictation, and how streaming STT models rewrite on the fly

**Question:** [`../questions/whisper-vs-streaming-asr-for-dictation.md`](../questions/whisper-vs-streaming-asr-for-dictation.md)
**Written:** 14/04/26
**Stack:** Desktop live voice typing. Compares Whisper (OpenAI, encoder-decoder offline transformer) against streaming-first commercial ASR (Deepgram Nova, AssemblyAI Universal-Streaming, Soniox, Google Streaming, NVIDIA Riva streaming Conformer/Parakeet, Speechmatics) and the small text-side post-processors that sit downstream of them.

## TL;DR

Whisper isn't a bad transcriber — it's an *offline* transcriber. Its architecture (a fixed 30-second encoder window plus a fully autoregressive text decoder conditioned on the entire encoded clip) is structurally hostile to emitting incremental, low-latency hypotheses. Live-suited models like Deepgram Nova or Streaming Conformer-Transducers are built around three design choices Whisper rejects: **causal/limited-lookahead audio encoding**, **monotonic alignment** (RNN-T or CTC instead of cross-attention), and a **training objective that rewards good partials**, not just a good final transcript.

Filler-word removal ("um/uh" cleanup), punctuation, casing, number formatting, and other "rewriting" effects are mostly *not* done by the acoustic model itself and *do not require* an audio-LLM. They come from two cheap places: (1) **transcript curation** — the ASR is trained on labels where fillers are already absent or marked, so the model learns to skip them; and (2) **a small text-only post-processing chain** — typically a punctuation/casing model, an inverse text normalizer (ITN), and a disfluency remover — that runs on the streaming token output. It's a pipeline of specialized sub-models, not a generative LLM doing end-to-end audio comprehension.

## Background

"Live dictation" sets a bar that batch transcription doesn't:

- **First-token latency** under ~300 ms from the moment a phoneme lands in the mic.
- **Steady incremental output** — partials that get progressively stabilised, so the user can react to misrecognitions before they're committed.
- **Bounded finalization delay** — the gap between the user finishing a phrase and the text being "locked" should be a few hundred ms, not seconds.
- **Real-time factor (RTF) <<1** on a single audio stream while leaving CPU/GPU headroom for the rest of the desktop.
- **Stable behaviour on short clips** — three-word utterances must work, not just minute-long monologues.

Whisper was not engineered against any of those constraints. It was engineered to maximise WER on long-form, weakly-supervised internet audio. Different optimisation target, different shape of model.

## Why Whisper is structurally offline

The Whisper paper and the ubiquitous `openai/whisper` reference implementation make four architectural commitments that each, individually, make true streaming awkward — and together make it nearly impossible without rebuilding the model.

### 1. Fixed 30-second mel-spectrogram windows

Whisper's encoder ingests an 80-channel log-Mel spectrogram of exactly 30 seconds (3000 frames at 10 ms hop). Shorter audio is *zero-padded* to 30 s. Longer audio is *chunked* into 30 s segments by the inference wrapper. The model has no concept of "more audio coming" — every forward pass sees a full 30-second tensor.

For live dictation that means:

- A 1-second utterance is processed as a 30-second tensor with 29 seconds of padding. You pay near-full compute regardless of utterance length.
- The encoder cannot start producing useful features until enough audio has been buffered (or the buffer is padded with silence, which biases the model toward hallucinating end-of-segment behaviour).
- "Streaming Whisper" tools (faster-whisper, whisper-streaming, WhisperLive, MacWhisper streaming, wispr) work around this by VAD-segmenting the audio into short utterances and running batch inference on each segment — *chunked-offline*, not streaming. They inherit Whisper's inability to revise across chunk boundaries.

### 2. Bidirectional encoder

The Whisper encoder is a standard transformer encoder with full bidirectional self-attention over those 3000 frames. Every frame attends to every other frame, including future ones. This is great for accuracy — left and right context disambiguate phonemes brilliantly — but it means you cannot meaningfully run the encoder until you have the full window.

A streaming-friendly encoder uses **causal** or **chunked-causal** attention (each frame attends only to past frames and a small lookahead, e.g. 80–480 ms). That's a fundamentally different architecture, not a tunable knob.

### 3. Autoregressive cross-attention decoder over the whole encoded clip

The Whisper decoder is a transformer that emits text tokens autoregressively, with cross-attention over the *entire encoder output*. The first text token can only be emitted after the encoder has finished. There is no notion of "emit a partial token from the prefix of the audio I've seen so far." Decoding is a single pass over the whole utterance.

Streaming ASR replaces cross-attention with a **monotonic alignment** mechanism — most commonly **RNN-T (RNN Transducer)** or **CTC (Connectionist Temporal Classification)** — that is structurally constrained to emit text in lockstep with audio frames as they arrive.

### 4. Training objective rewards the *final* transcript

Whisper was trained on 680k hours of weakly-supervised internet audio with one objective: produce the right text for the whole clip. The loss does not penalise late, incoherent, or unstable partials, because partials don't exist in training. Even if you bolted a streaming inference loop onto Whisper, you'd be using a model whose weights have never been optimised for the partial→final stabilisation behaviour that defines a good live experience.

### Side-effects users actually feel

These four choices produce predictable failure modes that anyone who has tried "Whisper for live dictation" recognises:

- **Hallucinated endings on short clips.** "Thank you for watching!" or "Subtitles by …" appearing on tiny utterances — the model has been trained on YouTube transcripts and confidently completes patterns when the audio is mostly silence/padding.
- **All-or-nothing latency.** A 5 s utterance produces nothing, then everything. The user can't tell whether the system is working until the result lands.
- **Chunk-boundary artefacts.** Sentences that span a 30 s VAD chunk lose context across the boundary; punctuation and capitalisation suffer.
- **Unstable timestamps.** Whisper's internal timestamp tokens are notoriously off by hundreds of ms; word-level timing is approximated by post-hoc tools (whisperX, stable-ts) that re-align with a separate model.

## What live-suited models do differently

The Deepgram, AssemblyAI, Soniox, Google, Speechmatics, and NVIDIA-streaming families differ in implementation but share a recognisable design pattern.

### Streaming acoustic encoder

Audio is encoded **causally** or with a small fixed **right-context window** (lookahead). Common choices:

- **Streaming Conformer** with chunked attention — each chunk (e.g. 160 ms) attends to a few past chunks and 0–2 future chunks. Used by NVIDIA Riva, Google, and several open-source streaming Parakeet/Conformer configurations.
- **Causal Conformer / causal transformer** — strictly no future context. Lower latency, slightly higher WER.
- **Hybrid CNN-Transformer stacks** with limited lookahead, popular in custom commercial models (Deepgram has historically described their stack as a custom end-to-end architecture rather than a published academic model).

The encoder is invoked every chunk; new audio frames produce new encoder outputs without re-processing the full history.

### Monotonic alignment: RNN-T or streaming CTC

Instead of decoder cross-attention over the whole utterance, the model emits text via:

- **RNN-T (RNN Transducer)** — three networks: an audio encoder, a label-side prediction network (like a small language model), and a joint network that decides "given these audio frames and the tokens I've emitted so far, emit the next token or stay silent." This is the dominant streaming architecture in production. Apple Dictation, Google Live Caption, NVIDIA Parakeet-RNNT, AssemblyAI Universal-Streaming, and Deepgram Nova are all in or near this family.
- **CTC** — emits one token per frame (including a special blank token), then collapses the sequence. Simpler, very low latency, but slightly weaker on context-dependent words.
- **TDT (Token-and-Duration Transducer)** — RNN-T variant that predicts how many frames each token occupies, allowing the model to skip ahead and reduce per-token compute. Used in NVIDIA Parakeet-TDT.

The structural property all of these share: emission is **monotonic** in audio time. The model cannot "go back" and re-decode an earlier region after seeing later audio. This is the price of streaming, and the engineering job is to mitigate it (with limited lookahead, partial-then-final hypotheses, and post-hoc rewriting).

### Partial / final hypothesis discipline

Streaming-first APIs expose two event types:

- **Partial / interim hypothesis** — the model's current best guess for the in-progress utterance. Mutable; will be revised as more audio arrives. Useful for "live caption" overlays; dangerous to commit into a focused window. (See [`streaming-vs-batch-injection`](streaming-vs-batch-injection.md) for the injection-policy implications.)
- **Final hypothesis** — locked. Comes from an **endpointing** decision: the model or a separate VAD says "the speaker has stopped this segment," and the partials in that segment are flipped to final.

Endpointing thresholds are the hidden UX dial. Deepgram, AssemblyAI, and the rest expose them (`endpointing`, `utterance_end_ms`, `vad_events`) precisely because the right value is application-specific. Dictation usually wants more aggressive endpointing than meeting transcription.

### Trained for the streaming objective

Streaming models are trained with auxiliary losses that reward stable partials, low emission latency (the time between when a phoneme lands and when its token is emitted), and good behaviour at chunk boundaries. Techniques include FastEmit, alignment-restricted RNN-T, and minimum-latency training. None of these have analogues in Whisper's training pipeline.

### Optimised for short utterances

Production streaming systems are engineered around the observation that dictation utterances are typically 1–10 seconds. Per-utterance overhead (model warm-up, padding, beam-search initialisation) is amortised aggressively. Whisper's per-utterance overhead, by contrast, is roughly constant in the 30 s window length.

### Summary of the architectural delta

| | Whisper | Streaming ASR (Deepgram Nova / AssemblyAI Universal-Streaming / Streaming Conformer-RNNT) |
|---|---|---|
| Audio context | Fixed 30 s, bidirectional | Chunked, causal or short lookahead (~80–480 ms) |
| Text decoder | Autoregressive cross-attention over full encoding | Monotonic alignment (RNN-T / CTC / TDT) |
| Output cadence | One transcript per 30 s chunk | Partial + final events, every chunk |
| Training objective | WER on full transcript | WER + emission latency + partial stability |
| Per-utterance overhead | High and constant | Low, scales with utterance length |
| Native short-clip behaviour | Poor (hallucinates / pads) | Good |
| Best WER ceiling | Higher (sees full context) | Lower by 1–4 absolute WER points typically |

## How filler-word removal works without a multimodal LLM

This is the part that often looks magical and isn't. The "rewriting" power of Deepgram-class systems comes from a *pipeline of small specialised models*, each doing one thing, none of which is a generative audio-LLM. The acoustic model is still a sequence transducer that maps audio frames to text tokens. The text gets cleaned up by what's downstream.

There are four mechanisms in play, and production systems mix them.

### Mechanism 1: Train the acoustic model on transcripts that already omit (or tag) fillers

The simplest and most powerful trick. If your training transcripts don't contain "um" and "uh" — or contain them as a special tag that you can choose to suppress — the model learns that those acoustic regions don't correspond to text output.

Several large conversational corpora (Switchboard, Fisher, internal customer-service recordings) are annotated with disfluencies marked explicitly: `[uh]`, `[um]`, `<filler>`. With those labels:

- Train one model on the verbatim transcripts → it emits fillers.
- Train another (or use a flag/conditioning token) on filler-stripped transcripts → it skips them.
- Or: train a single model with a special `<no-filler>` conditioning token that the user supplies at inference time. The model learns to emit fillers when the token is absent and skip them when it's present.

The acoustic side never "understands" what a filler is — it just learns, statistically, that certain acoustic regions (low-energy nasalised vowels surrounded by pauses, with no following content word) tend to map to no output token in the cleaned label distribution. This is the same machinery that lets the model learn to skip silence. Filler is just "vocalised silence" from the model's perspective.

Deepgram exposes this as a `filler_words` parameter (default behaviour suppresses them; set to `true` to keep them). AssemblyAI exposes `disfluencies`. Both names point to a single conditioning bit on a model trained both ways.

This is also, by the way, why **Whisper sometimes drops fillers and sometimes doesn't** — its 680k hours of internet training data contain a mix of verbatim and cleaned transcripts, with no explicit conditioning. The behaviour is uncontrolled.

### Mechanism 2: A small text-only post-processing chain

After the acoustic model emits raw tokens, production systems run a chain of tiny specialised text models. None of them is an LLM in the GPT sense — they're typically small transformers (10s of millions of parameters, often distilled), each fine-tuned on one task:

- **Punctuation and casing restoration** — adds commas, periods, question marks, capitalisation. Trained on text pairs (lowercase-no-punct → properly-cased-with-punct).
- **Inverse Text Normalisation (ITN)** — converts spoken forms to written forms: "twenty twenty six" → "2026", "doctor smith" → "Dr. Smith", "at gmail dot com" → "@gmail.com". Often a finite-state transducer (Sparrowhawk, NeMo's text processing module) plus a small neural fallback.
- **Disfluency removal (sometimes called *cleanup*, *smoothing*, or *fluency*)** — a small encoder-only model (often a distilled BERT) trained on the Switchboard disfluency-tagged corpus to delete fillers, false starts, and repetitions: "I think uh I think we should go" → "I think we should go". Repairing false starts is a richer task than dropping "um" and is where the pipeline starts to look like rewriting.
- **Entity formatting** — phone numbers, currency, dates, addresses.

Each of these models is small enough to run inline on the streaming output without breaking latency. The combined effect *looks* like an LLM rewriting your dictation; it's actually four narrow models in series, each doing pattern-matching it was specifically trained for.

Deepgram bundles much of this under `smart_format`. AssemblyAI calls it `format_text` plus `disfluencies`. NVIDIA Riva exposes the components individually.

### Mechanism 3: Two-pass / delayed-rewrite

For richer cleanup, some systems run a second pass over each finalised utterance:

- **Pass 1 (real-time):** the streaming transducer emits raw partials and finals into the live caption.
- **Pass 2 (utterance-final, ~100–300 ms after endpointing):** a small seq2seq model (encoder-decoder, often a distilled T5 or BART variant) takes the finalised raw chunk and rewrites it — fluent disfluency removal, sentence restructuring, light grammar repair. The rewritten chunk replaces the raw chunk in the transcript.

This is effectively a small text-to-text rewriting model with a very narrow task definition. It's not an LLM in the conversational sense — it's a domain-specific seq2seq trained on `(disfluent → fluent)` pairs. Total parameter count is typically <500M and inference fits in tens of ms on CPU.

This pattern shows up in dictation products that promise "clean dictation" output (e.g. several enterprise medical/legal dictation systems, Apple's on-device dictation post-iOS 17). When live captions briefly show "um" before it disappears, that's pass 1 → pass 2 in action.

### Mechanism 4: Lexical biasing and constrained decoding

Less about filler removal, more about why the rewriting feels accurate: streaming ASR APIs let you bias the decoder toward expected vocabulary (Deepgram's `keywords`, AssemblyAI's `word_boost`, NVIDIA's `boosted_lm_words`). This isn't rewriting per se, but it sharpens the raw transcript so that the downstream cleanup chain has less to fix. Combined with mechanisms 1–3, the user experience is: a clean, well-punctuated, filler-free, domain-aware transcript appearing in near-real-time, with no LLM in the loop.

### Why it stays out of "audio-LLM" territory

A true audio-multimodal LLM (Gemini Live, GPT-4o realtime, Qwen2-Audio) does end-to-end audio understanding: it can answer questions about the audio, summarise it, translate, or rewrite freely. That capability comes at a cost — billions of parameters, hundreds of ms of latency per token, and unpredictability in the rewrite (the model may editorialise).

Live STT pipelines stay deliberately on the *narrow* side of this line:

- The acoustic model is trained for transcription, not understanding. It doesn't "know" what it transcribed.
- Each post-processor is trained on a narrow input/output pair, so its behaviour is bounded and predictable.
- Total parameter budget across the pipeline is typically <1B, vs. >100B for a frontier multimodal LLM.
- The pipeline can be audited and individual stages disabled (turn off `smart_format`, get raw tokens).

This is why dictation users prefer the pipeline approach: it produces the exact same clean output every time, doesn't hallucinate beyond what was said, and runs at <300 ms first-token latency on commodity hardware. The "rewriting" is real, but it's the predictable rewriting of a small specialist, not the open-ended rewriting of a generalist LLM.

## Where this leaves Whisper

Whisper isn't going away — it's the right tool when:

- You have full audio in advance (post-hoc transcription, podcast subtitles, meeting recordings).
- You care about WER ceiling more than latency.
- You want one model that handles 99 languages without engineering a pipeline.
- You're willing to do your own cleanup downstream (you can absolutely run the same punctuation / ITN / disfluency chain on Whisper's output).

It's the wrong tool when:

- You need first-token latency under a second.
- You need stable partials that the user can react to.
- You need predictable behaviour on short utterances.
- You need controllable filler suppression (Whisper's behaviour is uncontrolled).

The cleanest mental model: **Whisper is a transcription model; Deepgram/AssemblyAI/Streaming-Conformer are dictation models.** They're optimising for different objectives, and the architectural differences follow from that.

## Caveats

- **"Deepgram is a single model" is marketing shorthand.** All production streaming STT vendors run pipelines internally. The end-to-end-deep-learning framing refers to the acoustic model, not the full transcript shaped by `smart_format`.
- **Streaming Whisper variants are improving.** `whisper-streaming` (UFAL), `WhisperLive`, and faster-whisper with VAD all narrow the gap on perceived latency. But they remain chunked-offline under the hood and inherit the architectural ceiling described above. They cannot cross the partial-stability / first-token-latency line that true streaming RNN-T crosses.
- **Open-source streaming is catching up.** NVIDIA's streaming Parakeet/Conformer, Moonshine (designed for streaming on edge), Vosk's streaming Kaldi models, and several streaming wav2vec2 fine-tunes all exist. Quality is approaching commercial closed models but they generally lack the polished post-processing chain.
- **Latency budgets are end-to-end.** Audio capture buffer + VAD lookahead + model RTF + post-processing chain + injection round-trip all stack. A 200 ms model with 600 ms of buffering doesn't feel fast.
- **The post-processing chain is where vendor lock-in lives.** Swapping the acoustic model is easy; replicating Deepgram's `smart_format` quality with open components is non-trivial. NeMo and Riva ship the closest open equivalents.
- **"Multimodal" overloading.** All of these models are technically multimodal in input (audio in, text out). The relevant distinction in this answer is whether the model is an *open-ended audio-LLM* (Gemini Live class) versus a *narrow audio-to-text transducer* (Whisper, Deepgram, etc.). Both consume audio; only the former does flexible reasoning over it.

## References

- Radford et al., *Robust Speech Recognition via Large-Scale Weak Supervision* (Whisper paper): <https://arxiv.org/abs/2212.04356>
- Whisper reference implementation (note the 30 s windowing in `audio.py`): <https://github.com/openai/whisper>
- Graves, *Sequence Transduction with Recurrent Neural Networks* (RNN-T): <https://arxiv.org/abs/1211.3711>
- Gulati et al., *Conformer: Convolution-augmented Transformer for Speech Recognition*: <https://arxiv.org/abs/2005.08100>
- Yu et al., *FastEmit: Low-latency Streaming ASR with Sequence-level Emission Regularization*: <https://arxiv.org/abs/2010.11148>
- NVIDIA NeMo streaming ASR documentation: <https://docs.nvidia.com/deeplearning/nemo/user-guide/docs/en/main/asr/intro.html>
- NVIDIA Parakeet-TDT (TDT architecture): <https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2>
- Moonshine — designed for streaming on-device ASR: <https://github.com/usefulsensors/moonshine>
- Deepgram API reference (`smart_format`, `filler_words`, `endpointing`): <https://developers.deepgram.com/docs/>
- AssemblyAI Universal-Streaming announcement: <https://www.assemblyai.com/blog/universal-streaming>
- Switchboard disfluency annotations (the corpus most disfluency-removal models are trained on): <https://catalog.ldc.upenn.edu/LDC99T42>
- NVIDIA NeMo text processing (ITN / punctuation / casing): <https://github.com/NVIDIA/NeMo-text-processing>
- Whisper-Streaming (UFAL) — example of chunked-offline approximating streaming UX: <https://github.com/ufal/whisper_streaming>
- Related in this workspace: [`streaming-vs-batch-injection`](streaming-vs-batch-injection.md) — separates the recognition-mode axis (this guide) from the injection-mode axis.
