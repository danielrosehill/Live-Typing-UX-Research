# Dictation formatting features — built-in vs supplementary, across local and cloud models

**Question:** [`../questions/dictation-formatting-built-in-vs-supplementary.md`](../questions/dictation-formatting-built-in-vs-supplementary.md)
**Written:** 14/04/26
**Stack:** Desktop live voice typing. Covers cloud streaming ASR (Google, Deepgram, AssemblyAI, Azure, AWS Transcribe, Speechmatics, Soniox, OpenAI `gpt-4o-transcribe` / `whisper-1`), local engines (Whisper variants, NVIDIA Parakeet / Canary / Riva, Moonshine, Vosk / Kaldi, wav2vec2), and common supplementary post-processors (Silero punctuation, `deepmultilingualpunctuation`, NeMo PnC, punctuator2, NLTK / PySBD, LLM rewrite passes).

## TL;DR

There are **four formatting behaviours** that make the difference between dictation output you can send directly to an editor and output you need to clean up by hand. Most "modern" models — anything that came out of the post-2022 wave of seq2seq ASR (Whisper, Parakeet, AssemblyAI Universal, Deepgram Nova-2/3, Soniox, Speechmatics Ursa, `gpt-4o-transcribe`) — were trained on punctuated, capitalised data and therefore produce **sentence boundaries + punctuation natively as a side effect of decoding**. Older CTC-only stacks (classic Kaldi chains, Vosk's default models, raw wav2vec2) produce lowercase unpunctuated token streams and genuinely require a bolt-on punctuation model.

Almost no engine does **filler removal** or **paragraph breaks** well out of the box. Deepgram and AssemblyAI are the exceptions (both have native flags). Everyone else needs a supplementary pass — either a silence-gap heuristic you write yourself (for paragraphs) or an LLM rewrite (for filler removal that respects intent).

The practical summary:

- **Sentence boundaries + punctuation:** solved by the model for most cloud providers and modern local engines.
- **Filler removal:** usually a post-processor (LLM or word-list filter).
- **Paragraph breaks:** almost always a frontend heuristic you write yourself, informed by VAD silence timestamps.

## The four formatting requirements, restated precisely

### 1. Sentence boundary inference

The segmentation of a continuous audio stream into discrete sentence-sized units. Downstream, this is what lets the UI capitalise the next word, emit a terminal punctuation mark, or trigger a sentence-level commit.

Worth separating two sub-problems that are often conflated:

- **Acoustic sentence segmentation** — detecting that a sentence *ended*, typically from a pause + final intonation contour. Any VAD-gated pipeline implicitly does this.
- **Textual sentence segmentation** — deciding where sentences begin and end in the emitted text, independent of pauses (a speaker can run two sentences together with no pause and still need a period between them).

Modern seq2seq models do the textual version as part of decoding. CTC models do not.

### 2. Punctuation prediction

Inserting `. , ? ! : ;` at the right positions. Often bundled with **capitalisation** (together called "PnC" — punctuation and capitalisation). The hard cases are:

- Question marks — require semantic understanding, not just acoustic ones (many questions in English are not marked by rising intonation, e.g. "you're going where").
- Commas inside a clause — genuinely ambiguous; models vary wildly.
- Apostrophes / hyphens — usually handled by the tokenizer, not a separate prediction.

### 3. Filler-word removal

Stripping **disfluencies**: "um", "uh", "er", "mm", "hmm", "like" (when used as a filler), "you know", "I mean", plus partial words and false starts ("I was — I was going to"). This is genuinely hard because:

- You don't want to strip legitimate uses ("I like Python" ≠ filler).
- False starts require understanding that a span was replaced by a later span, not just deleting tokens.
- Whether to strip at all is a UX question. Medical / legal transcription typically *keeps* disfluencies. Dictation into a notes app wants them gone.

### 4. Paragraph breaks

Inserting `\n\n` between topically or rhythmically distinct passages. Two triggering heuristics dominate:

- **Silence-based** — a pause longer than some threshold (2–4 seconds is typical) is treated as a paragraph boundary.
- **Semantic** — topic shift detection, usually via an LLM or a dedicated segmentation model.

Silence-based is what almost every tool that supports paragraphs actually does. Semantic segmentation is rare in live pipelines because it adds latency.

## Cloud models — what's built in

| Provider / Model | Sentence boundaries | Punctuation | Filler removal | Paragraph breaks |
|---|---|---|---|---|
| **Google Cloud Speech-to-Text** (`chirp_2`, `chirp_3`, `latest_long`) | Native (from PnC) | Native — `enable_automatic_punctuation=true` | ❌ Not native (Google V2 has limited "spoken punctuation" handling but no filler filter) | ❌ Not native — you consume `resultEndOffset` silence gaps and segment yourself |
| **Deepgram** (Nova-2 / Nova-3) | Native | Native — `punctuate=true` | ✅ Native — `filler_words=true` returns them tagged, `filler_words=false` omits them; `smart_format=true` also strips most | ✅ Native — `paragraphs=true` returns a `paragraphs` array with start/end and sentence-level children |
| **AssemblyAI** (Universal / Universal-2) | Native | Native — `punctuate=true` | ✅ Native — `disfluencies=false` (default) removes them; `=true` keeps them | ✅ Paragraphs via `/transcript/:id/paragraphs` endpoint (post-hoc), plus `auto_chapters` for topical segmentation |
| **Azure Cognitive Services Speech** | Native | Native in "Display" output (`ResultReason.RecognizedSpeech`) with `OutputFormat.Detailed` | ⚠️ Partial — "profanity" masking and "disfluency removal" exist but are documented mainly for conversation transcription, not dictation mode | ❌ Not native — frontend heuristic |
| **AWS Transcribe** | Native | Native — on by default in real-time streams from ~2021 onward | ❌ Not native | ❌ Not native (has speaker segments but not paragraphs) |
| **Speechmatics** (Ursa / Enhanced) | Native | Native — `punctuation_overrides` config | ✅ Native disfluency handling — `transcription_config.enable_partials` returns disfluency markers; full removal needs `operating_point=enhanced` + post-filter | ⚠️ Partial — exposes speaker changes and segment boundaries, paragraphs you compose yourself |
| **Soniox** (2-channel real-time) | Native | Native | ✅ Native filler removal in `smart_format` mode | ⚠️ Partial — silence gaps exposed, you assemble paragraphs |
| **OpenAI `gpt-4o-transcribe` / `gpt-4o-mini-transcribe`** | Native | Native (model emits punctuated casedtext) | ⚠️ Inconsistent — sometimes removes "um"/"uh", not prompt-controllable in the transcription endpoint | ❌ Not native in streaming mode |
| **OpenAI `whisper-1` (API)** | Native | Native | ❌ Not native — Whisper keeps most disfluencies in verbatim mode, strips some in "concise" variants | ❌ Not native |

### What the cloud tier looks like overall

The two standouts for **built-in formatting coverage** are Deepgram and AssemblyAI — both expose all four requirements as simple boolean flags, and both are well-documented. If you want a single-API solution where you don't write any post-processing, pick one of those.

Google, AWS, Azure, OpenAI give you sentence boundaries + punctuation for free and leave filler removal and paragraphs to you. For a custom live-typing frontend that already does its own pause tracking (for VAD-gated commit), paragraph insertion is trivial to add on top — the harder piece to bolt on is filler removal.

## Local models — what's built in

| Engine / Model | Sentence boundaries | Punctuation | Filler removal | Paragraph breaks |
|---|---|---|---|---|
| **OpenAI Whisper** (`openai-whisper`, `faster-whisper`, `whisper.cpp`, all sizes) | Native (seq2seq decoder was trained on punctuated data) | Native | ❌ Keeps disfluencies (verbatim bias); `--suppress_tokens` can mask filler IDs but it's crude | ❌ Not native (but VAD-gated pipelines that chunk by silence give you pseudo-paragraphs for free) |
| **NVIDIA Parakeet-TDT 1.1B / 0.6B-v2** | Native | Native — trained with PnC | ❌ Not native | ❌ Not native |
| **NVIDIA Canary-1B** | Native | Native | ❌ Not native | ❌ Not native |
| **NVIDIA Riva** (ASR service) | Native | **Via a separate PnC model** — Riva ships PnC as a post-ASR component rather than fused in the acoustic model | ❌ Not native | ❌ Not native |
| **Moonshine** (tiny / base / small) | Native | Native (trained with PnC) | ❌ Not native | ❌ Not native |
| **Distil-Whisper** | Native (inherits from Whisper) | Native | ❌ Not native | ❌ Not native |
| **Vosk** (default small / large models) | ❌ Not native — lowercase unpunctuated output | ❌ Not native | ❌ Not native | ❌ Not native |
| **Kaldi chain / nnet3 models** (most pretrained) | ❌ Not native | ❌ Not native | ❌ Not native | ❌ Not native |
| **wav2vec2** (CTC fine-tunes from Hugging Face, e.g. `facebook/wav2vec2-large-960h`) | ❌ Not native — raw CTC, no casing, no punctuation | ❌ Not native | ❌ Not native | ❌ Not native |
| **Silero STT** (community models) | Partial — some community variants ship PnC, many don't | Partial | ❌ Not native | ❌ Not native |

### The practical divide for local models

There's a clean split:

- **Anything seq2seq trained on modern web data after ~2022** (Whisper, Parakeet, Canary, Moonshine) gives you sentence boundaries + punctuation for free. Filler removal and paragraphs are always on you.
- **Anything CTC-based and trained before PnC was routine** (Vosk, raw wav2vec2, older Kaldi recipes) gives you none of the four requirements. You need a full post-processing chain.

Riva sits oddly in the middle — it's modern and high-quality, but NVIDIA ships PnC as a separate deployable component rather than baking it into the acoustic model, so you compose it yourself at the server layer.

## Supplementary models — when you need a post-processor

### For punctuation + casing on an unpunctuated stream

- **`deepmultilingualpunctuation`** (Oliver Guhr's model on Hugging Face, based on XLM-RoBERTa). Drop-in Python library. Supports 12+ languages. The most common pick for wav2vec2 / Vosk pipelines.
- **Silero punctuation + capitalisation** (`silero-models` on GitHub / PyTorch Hub). Tiny (~30MB), CPU-friendly, multilingual. Used widely in privacy-focused / offline setups.
- **NVIDIA NeMo punctuation & capitalisation** (`nemo_asr.models.PunctuationCapitalizationModel`). Heavier but higher quality; the natural choice if you're already on a NeMo/Riva stack.
- **punctuator2** (Tilk). Older (2016), still works for English. Light and fast but lower ceiling than transformer-based ones.
- **LLM rewrite pass** (local: Llama-3-8B-Instruct, Phi-3, Qwen2.5; cloud: `gpt-4o-mini`, `claude-haiku-4-5`, Gemini Flash). Highest quality but highest latency and cost. Better for batch/post-editing than streaming.

Rule of thumb: for a live typing UI, Silero is the lightest option that still produces readable output. For a post-commit "polish" pass, an LLM is the right tool.

### For sentence segmentation from already-punctuated text

- **NLTK `sent_tokenize`** — Punkt model; good for English prose, confused by things like "Dr. Smith."
- **PySBD** — rules-based, handles edge cases (abbreviations, decimals) much better than NLTK.
- **spaCy** `Doc.sents` — requires a loaded model, slightly slower, but accurate on modern prose.

These are only relevant if you need explicit sentence spans (for sentence-level commits, citation, etc.) — the text itself already has the boundaries once punctuation is in.

### For filler / disfluency removal

This is the hardest category because word-list approaches over-strip and model-based approaches need context.

- **Word-list filter** — regex against `\b(um|uh|er|hmm|mm|like|you know|I mean)\b` with hedges. Fast, brittle, over-strips legitimate uses of "like" and "you know".
- **Disfluency detection models**:
  - **`Hugging Face` disfluency models** — e.g. `bhadresh-savani/bert-base-uncased-emotion` variants fine-tuned on Switchboard disfluency tags. Small and local-runnable.
  - **AssemblyAI's `disfluencies` flag** — if you're already on AssemblyAI, this is the right tool. They trained on conversational data and handle false starts reasonably.
- **LLM rewrite with a prompt like "clean up disfluencies but preserve meaning"** — currently the only approach that reliably handles false starts ("I went to the — I went to the store" → "I went to the store") rather than just deleting tokens. GPT-4o-mini / Claude Haiku / Gemini Flash are all capable; local 7B-8B instruction-tuned models work too for simpler cases.

For a dictation tool where the user is *prompting* an AI (the common modern case), filler removal is often unnecessary — the downstream LLM ignores fillers anyway. Only strip them if the output goes directly to a human reader.

### For paragraph breaks

- **Silence-gap heuristic** — the 5-line implementation everyone ships: emit `\n\n` whenever a pause exceeds N seconds (tunable, 2.5s is a reasonable default). Requires VAD or per-word timestamps from the ASR.
- **LLM rewrite** — prompt with "insert paragraph breaks at topic shifts, preserving wording". Higher quality but adds noticeable latency; better as a post-stop polish than a streaming operation.
- **Sentence-embedding topic shift** (e.g. `sentence-transformers/all-MiniLM-L6-v2` + cosine distance between adjacent sentence embeddings) — niche, mostly research-grade; rarely worth the complexity for a typing UI.

The honest recommendation: start with the silence-gap heuristic. Only move to an LLM rewrite if users specifically complain that paragraphs land in the wrong place.

## Putting it together — what a "full coverage" pipeline looks like

Three concrete configurations that hit all four requirements, from lightest to heaviest:

### Config A: Single-API cloud (lowest friction)

```
Deepgram Nova-3 (streaming)
  │
  ├─ punctuate=true          → punctuation + sentence boundaries
  ├─ filler_words=false      → filler removal
  ├─ smart_format=true       → ITN + casing + punctuation polish
  └─ paragraphs=true         → paragraph segmentation
```

One API call does all four. AssemblyAI is the equivalent with `punctuate / disfluencies=false / format_text / paragraphs`.

### Config B: Local Whisper + silence heuristic + optional LLM polish

```
faster-whisper (small or medium)
  │
  ├─ native → sentence boundaries + punctuation
  ├─ VAD silence gaps > 2.5s → paragraph breaks (frontend code)
  └─ post-stop LLM pass (optional) → filler removal + polish
```

Adds a post-processor only for filler removal, and only when the user asks for it. The cleanest local-first setup in practice.

### Config C: CTC engine (Vosk / wav2vec2) + full bolt-on chain

```
Vosk / wav2vec2 (streaming)
  │
  ├─ Silero punctuation    → punctuation + casing
  ├─ silence-gap heuristic → paragraph breaks
  └─ LLM rewrite pass       → filler removal + polish
```

Heaviest, most brittle, but also the most customisable. Only worth it if you have a hard constraint (GPU-free CPU inference, specific language support, air-gapped deployment) that rules out the seq2seq engines.

## Bottom line

- **Sentence boundaries + punctuation** are solved at the model layer by anything modern. If your engine doesn't do them, the quickest win is to switch engines, not to add a post-processor.
- **Filler removal** is genuinely model-dependent. Deepgram and AssemblyAI handle it; everyone else leaves it to you. For most dictation-to-AI use cases, leave it alone — the LLM ignores fillers and over-stripping causes real meaning loss.
- **Paragraph breaks** are almost always the frontend's job, even when the API says it supports them. A silence-gap timer in the VAD layer produces better results than blind reliance on a cloud provider's `paragraphs` output, because *you* know what pause length means "new paragraph" for *your* user.

The surprising result from surveying these is how little the built-in coverage varies among engines aimed at dictation specifically (Deepgram, AssemblyAI, Soniox): they all cover the four requirements. The gap is between dictation-optimised products and general-purpose ASR APIs (Whisper, Google, AWS) that produce high-quality transcripts but expect you to assemble the formatting layer yourself.

## Follow-up — 2026-04-14

### Why paragraph break detection is the least implemented of the four

**Short answer:** it's not a frontend-vs-backend split so much as a **problem-definition** split. Sentence boundaries, punctuation, and filler removal all have **objective training targets** — there's a correct answer you can label in a dataset. Paragraph breaks don't. What counts as a paragraph is a stylistic and domain-specific judgment, and models don't learn it reliably because there's no consistent supervision signal to learn from.

Pulling that apart into the actual technical reasons:

#### 1. No canonical ground truth in training data

The three "solved" features come with abundant labelled data:

- **Sentence boundaries / punctuation** — every piece of written text in the training corpus is a label. Books, Wikipedia, news, forum posts — they all have terminal punctuation and sentence structure already baked in. The model learns PnC essentially for free from the web-scale text side of its training pairs.
- **Filler removal** — labelled disfluency corpora exist (Switchboard, Fisher, plus modern conversational datasets like AMI and ICSI) with explicit `[DISFLUENCY]` / `[FILLED_PAUSE]` / `[PARTIAL]` tags annotated by humans. Small, but consistent enough to train on.
- **Paragraph breaks** — the label is *author intent about visual formatting*. The same spoken passage could legitimately be one paragraph or three depending on genre (blog post vs chat message vs legal brief), on the author's personal style, and on the rendering surface (Twitter vs a Word document). You cannot collect a corpus where annotators agree on where paragraph breaks "should" go with anything like the agreement you'd get for sentence endings.

Models don't learn well from inconsistent labels. So the feature gets left out of the training objective, and it shows up as a gap at inference time.

#### 2. The acoustic signal for paragraphs is weak

Pauses, intonation resets, and breath noise all correlate with paragraph breaks, but none are reliable:

- A 3-second pause can be "thinking about the next sentence" or "starting a new paragraph" or "phone notification distracted me" — same audio, different intent.
- Prosodic paragraph-ending cues (pitch reset, final lowering) exist in careful read speech but are largely absent in spontaneous dictation.
- Speakers often don't signal paragraph intent at all — they just produce a long run of connected sentences and decide visually later, when they see the text.

So even if you wanted a model to predict paragraph breaks acoustically, the signal is noisy enough that a simple silence threshold performs as well as a learned predictor, with none of the training cost.

#### 3. Paragraphs are a rendering-surface concept, not a text concept

A paragraph is "a chunk of text separated from other chunks by whitespace". That definition only makes sense relative to a rendering layer. Streaming ASR emits a token stream — it has no concept of a rendered surface.

Compare:

- Sentences end in `.` — the punctuation is *in the text itself*, unambiguous across surfaces.
- Paragraphs end with a newline — but `\n\n` means "new paragraph" in Markdown, `<p>` in HTML, a new `<p:Paragraph>` run in a Word document, pressing **Enter twice** in a plain textbox. In some contexts (terminal prompts, single-line chat inputs) a newline means *submit*, not "new paragraph".

An ASR pipeline that doesn't know where its output is going has no principled way to emit the right break character. Most pipelines solve this by leaving paragraph breaks entirely to whatever owns the cursor — i.e. the frontend, which does know.

This is the kernel of truth in the "is it just a frontend thing?" intuition. Strictly, paragraph emission requires a **two-line handoff**:

1. The ASR or VAD layer tags "long silence here" (timestamp + duration).
2. The frontend decides what that means in the current context — `\n\n`, two Enter presses, a new message, nothing at all.

Step 2 genuinely has to be at the frontend because only the frontend knows what app has focus.

#### 4. The live-streaming constraint

Paragraph break detection is least harmful as a *retrospective* decision — you can look at the whole transcript and decide where paragraphs go. But live dictation is irrevocably *prefix-only*: once you've emitted text, you can't go back and restructure it without a visible jump. So the model would have to decide "new paragraph starts here" in a single forward pass, with only the audio up to that point, and commit to the decision before knowing what comes next.

Contrast with punctuation: a streaming model can emit a period with reasonable confidence from a falling intonation and a short pause, because the downside of a wrong period is small (one mis-punctuated sentence). A wrong paragraph break is more jarring — a large visual artefact in the middle of what should be connected prose.

So even engines that *could* emit paragraph breaks live tend not to, because the cost of false positives is high and the user can add a break manually with one keystroke.

#### 5. Users already have a mechanism

For sentence-level punctuation, the "manual" alternative (typing a period) is laborious and slow. Automation pays off.

For paragraph breaks, the manual alternative (press Enter twice, or say "new paragraph" as a command) is fast and reliable. Several dictation products — Dragon NaturallySpeaking historically, and Wispr Flow more recently — let the user say `"new paragraph"` or `"new line"` as an explicit command. That sidesteps the detection problem entirely, costs almost nothing in UX, and is more predictable than any automatic detector.

When an explicit user command gives you 100% accuracy for one spoken phrase per paragraph, the incentive to build a detection model collapses.

### So: frontend thing, or deeper?

Both, but in a specific order:

- It's **deeper than a frontend quirk** — there are real training-data, signal-quality, and commit-latency reasons no one ships great automatic paragraph detection.
- And it's **also a frontend thing** — because the rendering surface genuinely has to decide what break character to emit, a frontend step is unavoidable even when the ASR does signal silence gaps.

The typical production pattern, across every dictation tool that handles paragraphs at all:

```
ASR / VAD → "pause of N ms at timestamp T" → frontend rule:
  if N > 2500ms  → emit \n\n  (or the surface-appropriate break)
  else if N > 800ms → emit \n    (soft break, rare)
  else            → no break
```

Plus an explicit voice command `"new paragraph"` as an override. That's it. The entire feature lives in ~20 lines of frontend code, which is why no backend model vendor bothers to own it properly.

The honest rephrasing of your observation: paragraph break detection is "the least implemented" because it's **the one feature where a trivial frontend heuristic works as well as anything a model could realistically learn**, and the rendering-surface dependency means it has to live on the frontend anyway. So the model vendors skip it and leave it to whoever owns the cursor.
