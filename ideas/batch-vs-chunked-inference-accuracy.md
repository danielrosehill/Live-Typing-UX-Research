# End-of-utterance batch inference is genuinely more accurate than chunked streaming — it's not just frontend engineering

**Question:** [`../questions/batch-vs-chunked-inference-accuracy.md`](../questions/batch-vs-chunked-inference-accuracy.md)
**Written:** 14/04/26
**Stack:** Desktop live voice typing. Local NVIDIA Parakeet (offline TDT-0.6B-v2 checkpoint) driven by Handy in a "press hotkey, speak, release, get text" pattern (offline ASR + utterance-final injection — see [`streaming-vs-batch-injection`](streaming-vs-batch-injection.md)). Compared against the same model family's streaming-configured variants and the broader streaming RNN-T / Conformer-Transducer family.

## TL;DR

The accuracy difference is real, measurable, and traces directly to the attention mechanism — it is not just frontend engineering. End-of-utterance batch inference lets the model attend bidirectionally over the entire encoded clip; chunked streaming inference forces a causal or short-lookahead encoder that has not seen the future of the utterance when it commits each token. On clean speech the gap is typically **1–4 absolute WER points** in favour of batch; on hard material (technical jargon, long sentences, names, code-switching, low SNR) it can widen to 5–10 points or more.

There are *also* training-objective and post-processing differences that compound the architectural one. A streaming model is trained to emit good *partials* (low emission latency, stability), which trades against final accuracy. A batch model is trained purely for final WER. So the streaming model is doubly disadvantaged: a weaker context window *and* a divided objective.

What "frontend engineering" *can* buy you is cosmetic — perceived latency, the look of words appearing as you speak, the option to stop early. It cannot recover the right-context information the encoder never saw.

## Background

The question reduces to: when a transducer emits the token for word *N*, how much of the surrounding audio has the encoder been allowed to attend to?

- **Batch (offline) inference:** the encoder sees frames `[1 … T]` (the whole utterance) before the decoder emits any token. Every token decision is made with full bidirectional context.
- **Chunked streaming inference:** the encoder is invoked on chunk *k* with access to past chunks `[k-c … k]` and possibly a small lookahead `[k+1 … k+l]` (commonly 80–480 ms, sometimes up to ~1 s). Token emission happens within or shortly after each chunk. The encoder *cannot* see frames beyond `k+l` when committing the chunk's tokens.

That's the whole story, mechanically. Everything else is a consequence.

## Why batch is more accurate: the attention-mechanism argument

### 1. Bidirectional self-attention disambiguates phonetically ambiguous spans

English (and most languages) are riddled with phonetic ambiguity that is only resolvable from later context:

- "I read the book" — past or present tense? Disambiguated by tense markers downstream.
- "recognise speech" vs "wreck a nice beach" — disambiguated by topical coherence over seconds.
- Garden-path sentences ("the horse raced past the barn fell"), proper noun boundaries ("New York Times" vs "new york times"), prosodic boundaries that fall after a content word — all benefit from right context.

In a bidirectional encoder, frame *t* can attend to frames `t+1, t+2, …, T`. The representation for the audio around "read" carries information from the inflection on the verb that comes 800 ms later. In a causal encoder, that information is structurally unavailable when the token is emitted.

This isn't a minor refinement — it's exactly the kind of disambiguation transformers were invented to do. Stripping it out is the cost of streaming.

### 2. Cross-attention over a long encoder output beats monotonic alignment

Whisper-class offline architectures use a transformer decoder with **cross-attention over the entire encoder output**. The decoder, when emitting token *N*, can attend to *any* frame in the encoded clip — beginning, middle, or end — and weight those frames by relevance.

Streaming ASR replaces this with a **monotonic alignment** mechanism (RNN-T, CTC, or TDT). The decoder is structurally constrained to emit text in lockstep with audio time. Monotonic alignment is what makes streaming *possible* — but it forfeits the ability to "look back" with content-conditioned attention.

For offline Parakeet-TDT-0.6B specifically, the architecture is still RNN-T-flavoured (transducer with limited audio context), not full cross-attention — so the gap to a hypothetical offline cross-attention model is smaller than the Whisper-vs-streaming gap. But the streaming-Parakeet vs offline-Parakeet gap still exists and follows the same logic at smaller magnitude: more context per emission decision = better decision.

### 3. Beam search at the end of an utterance prunes more confidently

Beam-search decoding with a language model rescore is much more effective when the whole utterance is available:

- Final beam selection sees the full sentence-level probability of each candidate. A high-likelihood mid-sentence path that becomes ungrammatical by the end of the sentence can be pruned in favour of an alternative that pays a small acoustic cost mid-sentence to gain a much larger language-model win.
- LM rescoring with a sentence-level model (or external transformer LM) is straightforward in batch and awkward in streaming (you don't have the future sentence yet).

Streaming systems use online beam search with shallow LM fusion at each emission step, which makes locally optimal but not globally optimal choices.

### 4. Punctuation, casing, and ITN are bidirectional problems

The downstream cleanup chain (punctuation/casing restoration, inverse text normalisation) inherently needs both left and right context to do its job well:

- Comma vs period vs question mark depends on what follows.
- "twenty twenty six" → "2026" requires seeing all four words before deciding it's a year.
- Capitalisation of "Smith" depends on whether "Dr." or "Mr." appeared earlier *and* on whether a name-like context follows.

In batch mode, the cleanup model sees the entire utterance and produces a coherent, well-punctuated result. In streaming mode, the cleanup model has to make local decisions and may revise punctuation as more text arrives — visible as the "comma turns into a period" flicker in live-caption UIs. The final text after enough revisions can match batch quality, but the intermediate states are noisier and the final state can still be slightly worse if the model committed too early.

## Why chunked streaming is less accurate beyond the attention argument

### Training objective is divided

A streaming model is trained against a multi-objective loss:

- WER on the final transcript (the same as batch).
- Emission latency (penalises tokens emitted "late" relative to the audio they correspond to — see FastEmit, alignment-restricted RNN-T, minimum-latency training).
- Partial stability (sometimes — penalises partials that get heavily revised).

These auxiliary losses *trade against* final WER. A model optimised purely for final WER (the batch case) can spend all its capacity there. A streaming model has to compromise.

### Chunk-boundary artefacts

When utterances span chunk boundaries, the model loses some context across them depending on the streaming strategy:

- **Cache-aware streaming Conformer** (NeMo's streaming config) maintains an attention cache across chunks, mitigating but not eliminating the loss.
- **Chunked-causal attention** with small lookahead loses information at every boundary.
- **VAD-segmented chunked-offline** ("streaming Whisper" approaches) loses *all* context across boundaries because each chunk is re-encoded from scratch.

Long sentences that cross boundaries see worse punctuation, worse name handling, and occasionally word-level errors at the seams.

### Per-utterance overhead is amortised differently

This is a subtle point but worth flagging: streaming models are typically trained and tuned for sustained speech. Their behaviour on very short utterances (1–2 words) can be slightly worse than offline models, which are trained on a broader distribution including short isolated utterances. (Offline Whisper has the *opposite* problem with very short clips because of the 30 s padding issue, but offline Parakeet does not — it's well-behaved across utterance lengths.)

## How big is the gap in practice?

Numbers from the public benchmarks, as of 2025:

- **Offline Parakeet-TDT-0.6B-v2** sits at the top of the [Open ASR Leaderboard](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard) with WER around 6–7% averaged across LibriSpeech / TEDLIUM / GigaSpeech / SPGISpeech / VoxPopuli / Earnings22 / AMI etc.
- **Streaming-configured Parakeet** (RNNT or Conformer with chunked attention) typically sits 1–3 absolute WER points worse on the same benchmarks, depending on chunk size and lookahead.
- **Whisper-large-v3** (offline) is in a similar range to offline Parakeet on most of those benchmarks.
- **Commercial streaming ASR** (Deepgram Nova-2/3, AssemblyAI Universal-Streaming, Soniox) sits 2–4 points worse than offline state-of-the-art on the same data, though they make up much of that ground with aggressive post-processing and domain biasing.

Translated into user-visible terms: on a 50-word dictation snippet, a 2-point WER gap is one extra word wrong on average. On a 200-word legal/medical/technical paragraph with names and acronyms, it can be 5–10 extra word errors.

The gap is **not constant across material**. It is small or invisible on:

- Short, common-vocabulary utterances ("send a message to John").
- Clean audio in well-represented accents.
- Material similar to the model's training distribution.

The gap is large on:

- Technical jargon, code-switching, proper nouns.
- Long sentences with subordinate clauses.
- Anything where the utterance-final words disambiguate earlier ones.
- Low SNR or far-field audio.
- Domain-specific vocabulary the streaming model wasn't biased for.

## What frontend engineering can and cannot fix

Frontend engineering — the chunking strategy, VAD endpointing, partial/final discipline, injection policy — controls the *user experience* of streaming, not the *accuracy ceiling* of the encoder.

Things frontend can buy you:
- Perceived latency (words appearing while you speak).
- Self-correction loop (stop early if misheard).
- Hands-free / VAD-gated operation.
- Stable injection (commit only finals, never partials).

Things frontend cannot buy you:
- The right-context information the causal encoder didn't see.
- The bidirectional attention disambiguation.
- The benefit of sentence-level LM rescoring on the full utterance.
- The cleaner punctuation/casing/ITN that comes from seeing the whole sentence.

If accuracy is the priority, batch wins. If perceived latency is the priority, streaming wins. The two are genuinely in tension at the model level — not just at the UI level.

## What the chunked-offline middle ground actually buys you

A common frontend pattern is **chunked-offline**: run an offline model on VAD-segmented chunks of audio, injecting each chunk's output as it completes. This is what most "streaming Whisper" tools do (`whisper-streaming`, `WhisperLive`, faster-whisper with VAD).

It is worth being precise about what this gives up vs full-utterance batch:

- Each chunk is still processed with full bidirectional attention *within the chunk*. So you keep most of the within-chunk accuracy benefit.
- You lose context *across* chunk boundaries — the model has no memory between chunks. Sentences that span boundaries suffer.
- Long-sentence LM rescoring is local to each chunk.
- Punctuation/casing is per-chunk and may be inconsistent across boundaries.

In practice, a sensibly tuned chunked-offline pipeline (with 5–15 s VAD chunks and overlap) gets within 1 WER point of full-utterance batch on most material, while *appearing* live. This is a more accurate way to "feel streaming" than running a true streaming model — at the cost of a chunk-sized latency floor (you don't see anything until the first VAD pause).

So the practical accuracy ranking, best to worst, is roughly:

1. **Offline batch on full utterance** (your current Parakeet + Handy setup).
2. **Chunked-offline with long chunks (10–30 s) and VAD**.
3. **Chunked-offline with short chunks (1–3 s) and VAD**.
4. **True streaming with large lookahead (~480 ms–1 s)**.
5. **True streaming with small lookahead (~80–160 ms)**.
6. **Strictly causal streaming (no lookahead)**.

Each step down trades accuracy for either latency, perceived liveness, or hands-free operation.

## Specific to your Parakeet + Handy setup

You're at the top of that ranking — **offline batch on full utterance**. You are paying the perceived-latency cost (no words appear until you toggle off) and getting the maximum accuracy the Parakeet family offers. The TDT-0.6B-v2 checkpoint is, as of writing, near the top of every offline benchmark.

If you ever switch to a streaming-configured Parakeet (NeMo supports it), expect:

- 1–3 absolute WER points regression on clean speech.
- A larger regression on technical / long-sentence material.
- A meaningful engineering jump in the injection layer (partial/final discipline, cursor management, undo behaviour).
- A different post-processing burden — the offline pipeline can run punctuation/ITN on the complete sentence; the streaming pipeline has to do it incrementally.

That regression is the *real* cost of moving to live-typing UX. It's not just engineering; the model is structurally seeing less.

## Recommendation for the workspace's "ideal UI" spec

Treat the recognition-mode choice as an **accuracy-vs-perceived-latency dial**, not an architectural detail. Document the WER cost of each step explicitly so future-you can make an informed tradeoff. Concretely:

- For dictation that targets **publish-quality prose, code, technical text, or anything reviewed carefully**, prefer offline batch. Accept the perceived latency.
- For dictation that targets **chat, ephemeral messages, search queries**, prefer streaming or chunked-offline with short chunks. Accuracy is secondary to feeling responsive.
- For **hands-free operation**, you have no choice — streaming with VAD endpointing is the only option. Accept the WER hit.
- Consider a **hybrid mode**: stream partials into an overlay (visible feedback) while running offline batch in the background on the same audio, then commit the offline result on toggle-off. This is the most accurate "feels live" pattern, at the cost of running both pipelines.

## Caveats

- **The numbers cited are benchmark averages.** Your domain (technical communications, AI/automation jargon, mixed English with occasional Hebrew) may sit far from the benchmark distributions. Run a small WER comparison on your own audio if accuracy matters at the margin.
- **Streaming models are improving fast.** The 2025 generation of streaming models (Universal-Streaming, Nova-3, streaming Parakeet variants) has narrowed the gap meaningfully vs the 2022–2023 cohort. Don't extrapolate from old comparisons.
- **The cleanup chain matters as much as the encoder.** Two systems with the same raw WER can have very different *user-perceived* accuracy after punctuation, casing, ITN, and disfluency removal. Streaming systems often invest more in this layer to compensate.
- **"Streaming" is overloaded.** Some APIs marketed as streaming are chunked-offline with VAD under the hood (this is fine, but it's not the same architectural class). Check whether the model emits true partials that get revised, or just one final per chunk.
- **LM fusion changes the picture.** A streaming model with a strong external LM and lookahead can sometimes match or beat an offline model without LM fusion. Vendor benchmarks may or may not include external LM rescoring; read the methodology.
- **End-to-end latency is not just model latency.** A "fast" streaming model with 600 ms of audio buffering and 200 ms of injection round-trip is not faster end-to-end than a "slow" offline model with no buffering.

## References

- Open ASR Leaderboard (where offline vs streaming models can be compared on identical data): <https://huggingface.co/spaces/hf-audio/open_asr_leaderboard>
- NVIDIA Parakeet-TDT-0.6B-v2 model card (offline checkpoint): <https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2>
- NVIDIA NeMo streaming ASR documentation (streaming Conformer / Parakeet configurations): <https://docs.nvidia.com/deeplearning/nemo/user-guide/docs/en/main/asr/intro.html>
- Graves, *Sequence Transduction with Recurrent Neural Networks* (RNN-T): <https://arxiv.org/abs/1211.3711>
- Yu et al., *FastEmit: Low-latency Streaming ASR with Sequence-level Emission Regularization* (a representative streaming auxiliary loss): <https://arxiv.org/abs/2010.11148>
- Mahadeokar et al., *Alignment Restricted Streaming Recurrent Neural Network Transducer*: <https://arxiv.org/abs/2011.03072>
- Gulati et al., *Conformer: Convolution-augmented Transformer for Speech Recognition*: <https://arxiv.org/abs/2005.08100>
- Handy (the desktop dictation client used in this setup): <https://github.com/cjpais/Handy>
- Related in this workspace:
  - [`streaming-vs-batch-injection`](streaming-vs-batch-injection.md) — separates recognition mode from injection mode.
  - [`whisper-vs-streaming-asr-for-dictation`](whisper-vs-streaming-asr-for-dictation.md) — why offline-trained models like Whisper resist streaming.
