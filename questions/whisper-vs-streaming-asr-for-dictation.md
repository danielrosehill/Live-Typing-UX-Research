# Why Whisper isn't ideal for live dictation, and how live STT models rewrite on the fly

**Asked:** 14/04/26
**Slug:** `whisper-vs-streaming-asr-for-dictation`
**Response:** [`../ideas/whisper-vs-streaming-asr-for-dictation.md`](../ideas/whisper-vs-streaming-asr-for-dictation.md)

## The question

Whisper is the gold standard in transcription, but I've often heard it observed that it's not ideal for live dictation, and we commonly see that specific models like Deepgram are actually preferred for this use case.

Let's explore technically:

1. What makes the difference between a speech-to-text model that's inherently suitable for live dictation vs one that isn't?
2. How can live STT models incorporate things like filler-word removal — not getting "ums" and "ahs" — without being audio-multimodal LLMs? How do they achieve that powerful rewriting ability while staying within this specific space?
