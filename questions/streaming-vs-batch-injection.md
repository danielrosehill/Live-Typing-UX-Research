# Streaming injection vs batch transcription on stop

**Asked:** 14/04/26
**Slug:** `streaming-vs-batch-injection`
**Response:** [`ideas/streaming-vs-batch-injection.md`](../ideas/streaming-vs-batch-injection.md)

## The question

Some live-typing implementations keep an open audio stream and dump text at the cursor position incrementally — inference is happening on the fly and the screen updates as you speak.

What is *that* design choice called, as opposed to the one I'm currently using? My current setup runs NVIDIA Parakeet as essentially an asynchronous job: it waits for me to toggle the microphone off, then transcribes everything in one go and the full text appears at the cursor all at once.

What's the terminology for each side of this distinction, and where does each pattern sit in the wider design space?
