# What is the dynamic-rewriting display in tools like Deepgram called?

**Asked:** 14/04/26
**Slug:** `partial-transcript-rewriting`
**Response:** [`ideas/partial-transcript-rewriting.md`](../ideas/partial-transcript-rewriting.md)

## The question

Certain live dictation tools — Deepgram is a good example as implemented — print the dictated text dynamically onto the screen as you speak, and rewrite it incrementally. Some text appears, then based on subsequent audio the sentence boundaries are re-inferred and the on-screen text is updated in place.

What is this methodology called? Is it a frontend feature, a backend feature, or a mixture? How does it actually work?

## Related

- [`whisper-vs-streaming-asr-for-dictation`](../ideas/whisper-vs-streaming-asr-for-dictation.md) — deeper architectural background on partial vs. final hypotheses in streaming ASR.
- [`streaming-vs-batch-injection`](../ideas/streaming-vs-batch-injection.md) — how (and whether) those rewritten partials should be pushed into a focused window.
