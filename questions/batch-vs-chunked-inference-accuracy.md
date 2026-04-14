# Does end-of-utterance batch inference give better accuracy than chunked streaming, or is it just different frontend engineering?

**Asked:** 14/04/26
**Slug:** `batch-vs-chunked-inference-accuracy`
**Response:** [`ideas/batch-vs-chunked-inference-accuracy.md`](../ideas/batch-vs-chunked-inference-accuracy.md)

## The question

Is there any meaningful difference in accuracy when you have a model that does the inference at the end — in the pattern I've described for my local Parakeet with Handy, whereby you wait until you're finished dictating and then it does it all in one go?

In terms of the accuracy and the attention mechanism, is it going to struggle more than if you use that chunked approach, or is it just different frontend engineering?

## Related

- [`streaming-vs-batch-injection`](streaming-vs-batch-injection.md) — separates the recognition-mode axis from the injection-mode axis.
- [`whisper-vs-streaming-asr-for-dictation`](whisper-vs-streaming-asr-for-dictation.md) — why offline-trained models like Whisper resist being made streaming.
