# When Handy prints the transcript over 10–20 seconds, is that real-time inference or an artificial frontend delay?

**Asked:** 14/04/26
**Slug:** `handy-inference-vs-typing-delay`
**Response:** [`ideas/handy-inference-vs-typing-delay.md`](../ideas/handy-inference-vs-typing-delay.md)

## The question

Explore the determinants of the speed of inference in Handy, which records in one shot and then prints the transcript to the screen. For a few paragraphs of speech, that print stage can take 10–20 seconds.

Is that delay artificial — created by the way the frontend chooses to print words to the screen — or is the inference output being displayed in real time, so that as each word appears it reflects speech being transcribed live?

## Related

- [`batch-vs-chunked-inference-accuracy`](batch-vs-chunked-inference-accuracy.md) — the accuracy side of batch-on-stop inference.
- [`streaming-vs-batch-injection`](streaming-vs-batch-injection.md) — separates the recognition-mode axis from the injection-mode axis.
- [`inference-cadence-and-sentence-entry`](inference-cadence-and-sentence-entry.md) — the three intervals that govern how live-feeling dictation feels.
