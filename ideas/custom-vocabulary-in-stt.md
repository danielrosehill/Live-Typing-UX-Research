# Custom vocabulary in STT — what's actually happening under the hood, and how big the list can get

**Question:** [`../questions/custom-vocabulary-in-stt.md`](../questions/custom-vocabulary-in-stt.md)
**Written:** 14/04/26
**Stack:** Desktop live voice typing. Covers cloud streaming ASR (Google, Deepgram, AssemblyAI, Azure, AWS Transcribe, Speechmatics, Soniox), local engines (Whisper / faster-whisper, NVIDIA Parakeet / Riva, Vosk / Kaldi, wav2vec2), and post-processing tools (Handy, Wispr Flow, Superwhisper, MacWhisper, Aqua, plus LLM-based rewrite passes).

## TL;DR

"Custom word" features are almost never a single thing — they're a **family of five mechanisms** that sit at very different points in the pipeline, and most serious STT products expose two or three of them under one UI label. In rough order from deepest to shallowest:

1. **Pronunciation lexicon injection** — teach the acoustic/lexicon layer how a word is *spoken* (G2P entries).
2. **Decoder biasing / shallow fusion** — at beam-search time, add a log-prob boost to hypotheses that match the user's phrase list.
3. **Contextual attention biasing (CLAS-style)** — embed the phrase list and let the decoder attend to it as a soft "remember these" signal.
4. **Prompt/context conditioning** — Whisper's `initial_prompt`, or an LLM post-pass prompted with your glossary.
5. **Pure post-processing find-and-replace** — regex or fuzzy-match rewrites on the finalised text. No acoustic awareness at all.

The UX-level "custom dictionary" is essentially a frontend form that routes into one or more of these. It is **not** generally a system prompt in the LLM sense, except in the specific case of Whisper's prompt field and LLM-rewrite tools like Wispr Flow or a Handy post-pass.

**Practical size limits before inference degrades:**

| Mechanism | Typical ceiling | Where degradation shows up |
|---|---|---|
| Whisper `initial_prompt` | ~224 tokens (≈150–180 words) | Hard cap — tokens past the limit are silently dropped; too much content biases the model to hallucinate the glossary. |
| Cloud decoder boost (Google, Deepgram, AssemblyAI, Azure, AWS) | 500–5,000 phrases per request, 10k–100k in a server-side "custom class" | False positives (the model hears the boosted word when you didn't say it); decoding latency grows roughly linearly past a few thousand entries. |
| Contextual attention (Google CLAS, NVIDIA Riva `word_boost`) | ~1,000–3,000 bias phrases | Diminishing returns past a few hundred; very long lists dilute the attention signal. |
| WFST / lexicon injection (Kaldi, Riva, Vosk) | 10k–100k+ words | Mostly graph-size / RAM limited rather than accuracy-limited. |
| LLM rewrite pass (Wispr Flow, custom Handy pipeline) | Whatever fits the LLM context window (thousands of terms) | Latency and cost scale linearly with prompt size; the LLM may over-correct and swap in a glossary term that wasn't actually said. |
| Post-hoc find-and-replace | Effectively unlimited | Won't fix anything the ASR didn't produce in a recognisable shape in the first place. |

The honest headline: if the ASR has never **heard** the word — no acoustic pattern, no pronunciation — no amount of frontend biasing will conjure it from nothing. Custom vocabulary is a **tilt**, not a teach. Teaching (new pronunciations, new tokens) requires either a G2P entry or actual fine-tuning.

## Background — why this feature exists at all

ASR models are statistical. They emit the most probable token sequence given the audio. "Probable" is determined by:

1. **Acoustic likelihood** — how well the waveform matches the phoneme sequence for a candidate word.
2. **Language-model likelihood** — how plausible that word sequence is in normal text.

Niche words lose on both fronts. A company called *Rosehill* has:

- An acoustic profile ambiguous with *rose hill*, *roast hill*, *Rose Hill* (two words), *rosetta*…
- A vanishingly small language-model prior — in training data, "rose" is followed by "garden", "petals", "wine", not "hill" as a surname.

So the decoder quite reasonably picks *rose hill*. Custom vocabulary features exist to **re-weight the probabilities in the user's favour**, without retraining. The art is that you want to nudge the balance just enough to win on the cases where the user actually said the niche word, *without* hallucinating it everywhere else.

That tradeoff — **recall gain vs. false-positive cost** — is the single most important thing to keep in mind when evaluating any tool's custom-word implementation.

## The five mechanisms, in depth

### 1. Pronunciation lexicon injection (G2P entries)

**Where it lives:** inside the ASR's lexicon / grapheme-to-phoneme (G2P) stage, before decoding.

**What it does:** tells the system "the written form *Rosehill* is pronounced /ˈroʊz.hɪl/". From then on, the decoder knows that audio matching those phonemes can be emitted as *Rosehill* as a single unit.

**Where you see it:**

- **Kaldi / Vosk** — you edit `lexicon.txt` and rebuild the decoding graph (HCLG).
- **NVIDIA Riva** — custom pronunciations via the `inverse_text_normalization` and lexicon override configs.
- **Google Speech-to-Text v2** — you can attach phoneme hints in a `CustomClass` for very rare words, but most users stop at the plain-text phrase.
- **Azure Custom Speech** — dedicated pronunciation upload (.txt with SAPI or IPA).
- **AWS Transcribe** — vocabulary entries accept `IPA`, `SoundsLike`, and `DisplayAs` fields.

**Strengths:** the *deepest* and most accurate form of customisation — it actually teaches the engine a new word, not just re-ranks existing hypotheses. Once a pronunciation is registered, the word competes fairly with the rest of the vocabulary.

**Weaknesses:** requires phonetic knowledge (IPA or an ASCII phoneme set the engine understands), not exposed by most consumer tools, and not available at all in end-to-end models that have no explicit lexicon (Whisper, Parakeet, wav2vec2, Conformer-CTC trained with BPE tokens — all of them produce subword tokens directly from audio, with no pronunciation table in the middle).

**Size ceiling:** tens of thousands of entries is routine in production Kaldi / Riva deployments. The cost is decoding-graph compile time, not runtime inference.

### 2. Decoder biasing / shallow fusion

**Where it lives:** during beam search at inference time.

**What it does:** for each hypothesis in the beam, if it contains one of the user's boost phrases (or a prefix of it), add a **log-probability bonus** — typically +2 to +15 in log space. That pushes the hypothesis up the ranking so it survives pruning and can win the final argmax.

**Where you see it:**

- **Deepgram** — `keywords` (legacy) and `keyterm` (Nova-3) parameters; you can pass the term plus an intensifier (e.g. `Rosehill:5`).
- **AssemblyAI** — `word_boost` with a `boost_param` of `low` / `default` / `high`.
- **AWS Transcribe** — custom vocabulary list with implicit boost.
- **Google Speech-to-Text** — `SpeechAdaptation` with `PhraseSet` and a per-phrase `boost` float.
- **Local Kaldi / Vosk** — word-level biasing by editing the LM or injecting a class-based LM.
- **Whisper + ctranslate2 (faster-whisper)** — partial support via logit processors, but not exposed in the typical wrapper UIs.

**Strengths:** cheap, fast, request-scoped (no retraining, no server-side state). The list can be swapped per utterance, which is why "context-aware" tools can load a different vocabulary depending on the focused application.

**Weaknesses:** it's a **tilt**, not a teach. If the acoustic model never emitted *Rosehill* as a candidate in the beam — e.g. because the subword tokens *rose* + *hill* dominated — no amount of boost can promote a hypothesis that doesn't exist. This is why users observe that custom words sometimes "just don't work": the bias fires only when the correct tokens were already in contention.

The symmetric failure is overshooting: boost too high and the model starts emitting *Rosehill* whenever you say anything resembling "rose hill", "roast hill", or even unrelated audio.

**Size ceiling:** empirically, the top ~100–500 boosted phrases do most of the work. Past a few thousand, you start seeing:

- **Beam saturation** — too many low-bias phrases compete with each other, diluting the signal.
- **Latency growth** — string-matching against the bias list during beam search is O(beam × phrases × max-phrase-length). Providers mitigate with tries / Aho-Corasick, but you still see ms-scale growth past ~10k.
- **False positive drift** — the broader the list, the higher the chance a common utterance happens to trigger a bias.

Typical documented caps: Deepgram 100 keyterms/request (Nova-3), AssemblyAI 1,000 word-boost entries, Google 5,000 phrases per SpeechAdaptation (with a separate CustomClass ceiling of 10k–100k items server-side), Azure up to ~2,048 phrases per request, AWS Transcribe 50k entries in a vocabulary.

### 3. Contextual attention biasing (CLAS and friends)

**Where it lives:** inside the decoder network itself, as a learned attention mechanism.

**What it does:** at inference, the phrase list is embedded and passed as an additional attention target alongside the encoder output. The decoder learns to "look at" the bias list when the current audio is ambiguous, and softly copy from it.

**Where you see it:** Google's **CLAS** (Contextual Listen, Attend, and Spell) paper, Meta's **Neural Associative Memory**, NVIDIA's **context-biasing adapters** for Conformer/Parakeet. Usually not directly exposed to end users — it powers the server-side implementation of Google's phrase hints and similar cloud features.

**Strengths:** unlike shallow fusion, the network has been **trained** to use the bias list — so it generalises better to morphological variants and doesn't require the token sequence to already be in the beam. It's the closest thing to "teach at inference time" without retraining.

**Weaknesses:** requires a model trained with the biasing mechanism baked in; retrofitting to a vanilla Whisper/Parakeet is a research project, not a config flag. Also, the attention has a finite "slot budget" — past a few hundred phrases, the quality of the biasing signal degrades because the attention weights spread too thin.

**Size ceiling:** 500–3,000 phrases in published benchmarks; some providers page through larger lists by selecting a subset per request based on the application context.

### 4. Prompt / context conditioning

This is the one that most resembles what the user asked about with "is it system-prompted?" — and yes, for a small but growing slice of tools, it literally is.

**Where it lives:** either in the ASR's own prompt field (Whisper) or in a downstream LLM rewrite pass.

**Two sub-flavours:**

#### 4a. Whisper-style `initial_prompt`

Whisper accepts an optional text prompt that is injected into the decoder's context as if it were prior transcript. The model then continues decoding conditioned on that prior. In practice this:

- Biases toward the vocabulary, casing, punctuation style, and language of the prompt.
- Has a **hard 224-token cap** (half of Whisper's 448-token decoder context window). Tokens past that are silently truncated from the *front*.
- Does not "teach" pronunciation — if the audio doesn't match the word, the prompt can't save you. But it does sharply improve recall on words the audio *could* produce, by raising their language-model prior.

This is what tools like **MacWhisper**, **Superwhisper**, **whisperX**, **faster-whisper**, **Aqua**, and many Whisper-wrapper apps use when they expose a "custom vocabulary" field. It's genuinely a prompt — but at the ASR level, not the LLM level.

224 tokens is the *only* hard ceiling in this whole document. Past it, content is dropped. Keep custom vocabulary under ~150 words and you'll never hit it.

#### 4b. LLM rewrite pass

The ASR produces a raw transcript. A second stage (a small LLM, a GPT-4o-mini call, or a local Llama) rewrites it, with a system prompt like:

> Correct the following transcript for spelling and proper nouns. Known terms: Rosehill, DSR Holdings, Speechmatics, Parakeet, …

This is exactly how **Wispr Flow**, some **Handy** users' post-pipelines, and LLM-enhanced Whisper wrappers implement "custom dictionary". It is, literally, system-prompted.

**Strengths:** extremely flexible. Can handle style, formatting, abbreviation expansion, tone adjustment, not just vocabulary. Can fix words the acoustic model mangled badly, because it has full sentence context.

**Weaknesses:**

- **Latency**: even a fast local model adds 200–1000 ms to finalisation — a killer for streaming.
- **Cost**: per-transcript API calls add up.
- **Overcorrection**: the LLM will sometimes insert a glossary term that the user didn't say, simply because it's in the system prompt and the surrounding text is semantically adjacent.
- **Hallucination risk**: the LLM can rewrite beyond the narrow scope of vocabulary correction and invent content. Mitigated with tight prompts and temperature=0, but never fully eliminated.

**Size ceiling:** whatever fits the LLM context. A 128k-context model can hold tens of thousands of glossary entries, but you'll see latency and cost creep well before you run out of tokens. Practical sweet spot: a few hundred terms; past ~2,000 you're paying real cost per utterance.

### 5. Post-processing find-and-replace

**Where it lives:** a regex / fuzzy-match step on the final transcript, after the ASR is done.

**What it does:** `rose hill → Rosehill`, `deep gram → Deepgram`, `g p t 4 → GPT-4`.

**Where you see it:** almost every wrapper tool has this as a fallback, even if they also use one of the deeper mechanisms. It's the "replacements" or "text substitutions" tab.

**Strengths:** trivial to implement, zero latency impact, deterministic, can do things like casing/hyphenation that acoustic biasing can't.

**Weaknesses:** can only fix what the ASR already emitted *in a shape you can match*. If the ASR heard *Rosehill* as *roast still*, no regex will catch it unless you write a fuzzy-match rule — and fuzzy rules are where spurious replacements happen ("roast beef" → "Rosehill beef").

**Size ceiling:** thousands of rules is fine; the ordering matters more than the count (first-match-wins versus longest-match-wins).

## How a typical "custom words" UI maps to these mechanisms

| Tool | Custom word feature calls into | Scope | Hard limit |
|---|---|---|---|
| Deepgram Nova-3 | Decoder biasing (`keyterm`) + contextual biasing (server-side) | Per-request | ~100 keyterms; higher via custom models |
| AssemblyAI | Decoder biasing (`word_boost`) | Per-request | 1,000 words |
| Google Speech-to-Text | Decoder biasing (`PhraseSet`) + contextual (CLAS) + optional phoneme hints | Per-request or server-side class | 5k phrases/request, 100k in server class |
| Azure Speech | Lexicon injection (pronunciation file) + phrase list + Custom Speech fine-tune | Mix of per-request and model-level | 2,048 phrases, larger via Custom Speech |
| AWS Transcribe | Lexicon (SoundsLike/IPA) + custom vocabulary filter | Model-level | 50k entries |
| Speechmatics | Decoder biasing (`custom_dictionary`) + optional SoundsLike | Per-request | ~1k entries documented |
| Whisper wrappers (MacWhisper, Superwhisper, faster-whisper, Aqua) | `initial_prompt` | Per-utterance | 224 tokens |
| Wispr Flow | LLM rewrite pass with glossary in system prompt | Per-utterance | LLM context |
| Handy (default) | Mostly post-processing find-and-replace; some users add LLM rewrite | Per-utterance | Unlimited rules; LLM-limited if rewrite added |
| Vosk / Kaldi | Lexicon injection + optional LM class | Model-level (requires graph rebuild) | Tens of thousands |
| NVIDIA Parakeet / Riva | Lexicon + word boost + context biasing adapters | Mix | Thousands |

Most consumer-facing apps **don't disclose which mechanism they use**. Treat any tool that claims "custom vocabulary just works for millions of words" with skepticism — the physics of beam search says otherwise for the shallow-fusion path, and the 224-token cap is a hard physical limit for Whisper-prompt path.

## Is it a frontend feature?

Partially yes, partially no, depending on the tool:

- **Frontend storage and UI** — always. The list of custom words lives in the app's config file, database, or cloud settings, and is shown to the user as a form.
- **Frontend enforcement** — only for post-processing find-and-replace (mechanism 5) and for the LLM-rewrite case (mechanism 4b).
- **Backend enforcement** — for everything else. The word list is serialised into the ASR request (cloud) or the decoder config (local), and the biasing happens inside the model.

In cloud STT products, "custom vocabulary" is typically a server-side object that the client references by ID (e.g. Google's `PhraseSet` resource, AWS Transcribe's `Vocabulary`). The frontend stores the *list*, but the *biasing* happens during decoding on the server.

## Is it system-prompted?

Only in two specific cases:

1. **Whisper `initial_prompt`** — yes, literally a prompt. Limited to 224 tokens.
2. **LLM-rewrite tools (Wispr Flow, post-ASR GPT passes)** — yes, a system prompt to a second-stage LLM, not to the ASR itself.

For everything else — Deepgram, AssemblyAI, Google, Azure, AWS, Speechmatics, Kaldi, Vosk, Parakeet, Riva — it is **not** a prompt. It's a structured parameter (list of strings, optionally with boost weights or pronunciations) that modifies beam search or lexicon lookup. Calling it a "system prompt" would misrepresent the mechanism.

## When degradation actually sets in

Users asking "how big can this dictionary be" are usually worried about one of three things. Each has a different answer:

### Accuracy degradation

- **Pronunciation lexicon / WFST**: essentially no accuracy ceiling up to 100k+ entries, as long as the new words don't *collide* phonetically with high-frequency existing words.
- **Decoder biasing**: degrades above a few hundred phrases if boosts are high, because false positives start firing on unrelated audio. With low boosts and a few thousand entries, accuracy is usually fine — but the gain per entry is diminishing.
- **Whisper prompt**: degrades fast past ~100 entries — the model starts hallucinating glossary terms into unrelated utterances. The cap is 224 tokens anyway.
- **LLM rewrite**: degrades with list size and with generic terms; rare proper nouns stay fine, but common English words in the glossary cause the model to over-apply them.

### Latency degradation

- **Pronunciation lexicon**: zero runtime cost — it's all compile-time.
- **Decoder biasing**: low ms-scale growth; usually imperceptible below 10k phrases.
- **Whisper prompt**: the prompt tokens go through the decoder, so longer prompt = more autoregressive steps = worse first-token latency. Small effect (~10–50 ms) at the 224-token cap.
- **LLM rewrite**: dominant latency cost. Scales roughly linearly with prompt size for the prefill phase. A 2,000-word glossary at ~1.3 tokens/word = 2,600 tokens of prompt, which is 40–200 ms of prefill on a fast model and much more on a slow one. Added to the streaming output phase.

### Memory / deployment overhead

- **WFST/lexicon**: the decoding graph grows with vocabulary. 100k new words can add hundreds of MB to the graph in Kaldi. Fine for servers; annoying for local installs.
- **Everything else**: negligible until you're into hundreds of thousands of entries.

## Recommendations for this workspace's use case (live desktop dictation)

For a pause-tolerant prompt dictator who wants custom words to work reliably in streaming mode:

1. **Tier the list**. Only the 20–50 words that *actually get mis-transcribed repeatedly* need to be in the biasing layer. Dumping a 2,000-word glossary in makes the model worse, not better.
2. **Use the deepest mechanism the tool offers**. If you're on a cloud API with both a phrase list and a custom class / pronunciation field, use the pronunciation field for genuine novel words (surnames, product names) and the phrase list for existing-but-rare words.
3. **Don't use LLM rewrite for streaming**. The latency cost is incompatible with the feel of live dictation. Reserve it for batch-style "record then paste" flows.
4. **For Whisper-based local stacks**, the `initial_prompt` is the single most useful lever — keep it under 150 words, lead with the most important terms, and refresh it per application context if possible.
5. **Keep a post-processing find-and-replace layer as a safety net** for deterministic fixes (casing, hyphenation, brand spelling). It's cheap and it cleans up what the acoustic layer can't distinguish anyway.

## References

- OpenAI Whisper paper and `openai/whisper` decoder prompt handling — Whisper GitHub repo (`decoding.py`, `initial_prompt`).
- Google CLAS: Pundak et al., *Deep Context: End-to-End Contextual Speech Recognition*, Interspeech 2018.
- Google Cloud Speech-to-Text `SpeechAdaptation` and `CustomClass` — cloud.google.com/speech-to-text/docs/adaptation.
- Deepgram `keywords` / `keyterm` parameter docs — developers.deepgram.com.
- AssemblyAI `word_boost` docs — assemblyai.com/docs.
- AWS Transcribe Custom Vocabulary (IPA / SoundsLike / DisplayAs) — docs.aws.amazon.com/transcribe/latest/dg/custom-vocabulary.html.
- Azure Custom Speech pronunciation files — learn.microsoft.com/azure/ai-services/speech-service/how-to-custom-speech-test-and-train.
- NVIDIA Riva word-boosting and custom pronunciation — docs.nvidia.com/deeplearning/riva.
- Kaldi WFST / lexicon construction — kaldi-asr.org docs.
- Speechmatics `custom_dictionary` — docs.speechmatics.com.
- Related in this workspace: [Why Whisper isn't built for live dictation](whisper-vs-streaming-asr-for-dictation.md), [Interim results and stabilisation](partial-transcript-rewriting.md).
