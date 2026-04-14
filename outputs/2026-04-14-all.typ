// SCOPE: all topics in the workspace (all were created on 2026-04-14) — Batch 1
// GENERATED: 2026-04-14
// MODEL: Claude Opus 4.6
// SLUGS: batch-vs-chunked-inference-accuracy, cursor-dictation-vs-clipboard-stt-adoption, custom-vocabulary-in-stt, dictation-formatting-built-in-vs-supplementary, focus-loss-during-dictation, handy-inference-vs-typing-delay, inference-cadence-and-sentence-entry, live-typing-models-saas-and-local, local-stt-builtin-vad, local-stt-inference-engines-gpu, partial-transcript-rewriting, pause-tolerant-dictation-profile-and-stack, streaming-vs-batch-injection, stt-enthusiastic-industry-adoption, vad-for-live-typing, voice-dictation-hotkey-count-tradeoffs, whisper-vs-streaming-asr-for-dictation

#import "_template.typ": workspace-doc, topic, batch-table

#show: workspace-doc.with(
  title: [Live Typing UX Research — Batch 1 (14/04/26)],
  scope: "Batch 1 — all 17 paired topics captured 14/04/26",
  slugs: (
    "batch-vs-chunked-inference-accuracy",
    "cursor-dictation-vs-clipboard-stt-adoption",
    "custom-vocabulary-in-stt",
    "dictation-formatting-built-in-vs-supplementary",
    "focus-loss-during-dictation",
    "handy-inference-vs-typing-delay",
    "inference-cadence-and-sentence-entry",
    "live-typing-models-saas-and-local",
    "local-stt-builtin-vad",
    "local-stt-inference-engines-gpu",
    "partial-transcript-rewriting",
    "pause-tolerant-dictation-profile-and-stack",
    "streaming-vs-batch-injection",
    "stt-enthusiastic-industry-adoption",
    "vad-for-live-typing",
    "voice-dictation-hotkey-count-tradeoffs",
    "whisper-vs-streaming-asr-for-dictation",
  ),
)

#batch-table(
  label: "Batch 1",
  items: (
    ("batch-vs-chunked-inference-accuracy", [Does end-of-utterance batch inference give better accuracy than chunked streaming, or is it just different frontend engineering?]),
    ("cursor-dictation-vs-clipboard-stt-adoption", [Cursor-level dictation vs record-then-paste STT — who loves which, and where]),
    ("custom-vocabulary-in-stt", [Custom vocabulary in transcription tools — how is it actually implemented?]),
    ("dictation-formatting-built-in-vs-supplementary", [Dictation formatting features — built-in model support vs supplementary post-processing]),
    ("focus-loss-during-dictation", [Focus loss during dictation]),
    ("handy-inference-vs-typing-delay", [When Handy prints the transcript over 10–20 seconds, is that real-time inference or an artificial frontend delay?]),
    ("inference-cadence-and-sentence-entry", [Inference cadence and sentence entry for pause-for-thought dictators]),
    ("live-typing-models-saas-and-local", [Leading STT models for live typing — SaaS/API and locally runnable]),
    ("local-stt-builtin-vad", [Local STT engines with built-in VAD (or equivalent silence-handling architecture)]),
    ("local-stt-inference-engines-gpu", [Local STT inference engines and GPU acceleration (NVIDIA vs AMD)]),
    ("partial-transcript-rewriting", [What is the dynamic-rewriting display in tools like Deepgram called?]),
    ("pause-tolerant-dictation-profile-and-stack", [Pause-tolerant dictation — codify this user profile and recommend an STT stack]),
    ("streaming-vs-batch-injection", [Streaming injection vs batch transcription on stop]),
    ("stt-enthusiastic-industry-adoption", [Industries that adopted speech-to-text enthusiastically through recognition of its effectiveness]),
    ("vad-for-live-typing", [VAD (voice activity detection) for live typing]),
    ("voice-dictation-hotkey-count-tradeoffs", [Hotkey count tradeoffs for voice dictation control (single key, macro pads)]),
    ("whisper-vs-streaming-asr-for-dictation", [Why Whisper isn't ideal for live dictation, and how live STT models rewrite on the fly]),
  ),
)

#topic("batch-vs-chunked-inference-accuracy", "../questions/batch-vs-chunked-inference-accuracy.md", "../ideas/batch-vs-chunked-inference-accuracy.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("cursor-dictation-vs-clipboard-stt-adoption", "../questions/cursor-dictation-vs-clipboard-stt-adoption.md", "../ideas/cursor-dictation-vs-clipboard-stt-adoption.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("custom-vocabulary-in-stt", "../questions/custom-vocabulary-in-stt.md", "../ideas/custom-vocabulary-in-stt.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("dictation-formatting-built-in-vs-supplementary", "../questions/dictation-formatting-built-in-vs-supplementary.md", "../ideas/dictation-formatting-built-in-vs-supplementary.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("focus-loss-during-dictation", "../questions/focus-loss-during-dictation.md", "../ideas/focus-loss-during-dictation.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("handy-inference-vs-typing-delay", "../questions/handy-inference-vs-typing-delay.md", "../ideas/handy-inference-vs-typing-delay.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("inference-cadence-and-sentence-entry", "../questions/inference-cadence-and-sentence-entry.md", "../ideas/inference-cadence-and-sentence-entry.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("live-typing-models-saas-and-local", "../questions/live-typing-models-saas-and-local.md", "../ideas/live-typing-models-saas-and-local.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("local-stt-builtin-vad", "../questions/local-stt-builtin-vad.md", "../ideas/local-stt-builtin-vad.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("local-stt-inference-engines-gpu", "../questions/local-stt-inference-engines-gpu.md", "../ideas/local-stt-inference-engines-gpu.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("partial-transcript-rewriting", "../questions/partial-transcript-rewriting.md", "../ideas/partial-transcript-rewriting.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("pause-tolerant-dictation-profile-and-stack", "../questions/pause-tolerant-dictation-profile-and-stack.md", "../ideas/pause-tolerant-dictation-profile-and-stack.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("streaming-vs-batch-injection", "../questions/streaming-vs-batch-injection.md", "../ideas/streaming-vs-batch-injection.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("stt-enthusiastic-industry-adoption", "../questions/stt-enthusiastic-industry-adoption.md", "../ideas/stt-enthusiastic-industry-adoption.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("vad-for-live-typing", "../questions/vad-for-live-typing.md", "../ideas/vad-for-live-typing.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("voice-dictation-hotkey-count-tradeoffs", "../questions/voice-dictation-hotkey-count-tradeoffs.md", "../ideas/voice-dictation-hotkey-count-tradeoffs.md", date: "2026-04-14", model: "Claude Opus 4.6")

#topic("whisper-vs-streaming-asr-for-dictation", "../questions/whisper-vs-streaming-asr-for-dictation.md", "../ideas/whisper-vs-streaming-asr-for-dictation.md", date: "2026-04-14", model: "Claude Opus 4.6")
