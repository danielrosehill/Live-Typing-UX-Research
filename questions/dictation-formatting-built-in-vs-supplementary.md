# Dictation formatting features — built-in model support vs supplementary post-processing

**Asked:** 14/04/26
**Slug:** `dictation-formatting-built-in-vs-supplementary`
**Response:** [`ideas/dictation-formatting-built-in-vs-supplementary.md`](../ideas/dictation-formatting-built-in-vs-supplementary.md)

## The question

Several formatting behaviours are essential for dictation output to feel usable — if the STT model doesn't handle them, they require a second-pass processor. Enumerate these requirements, then identify for each requirement which local and cloud STT models provide it as built-in tooling versus which ones need a supplementary model. Where a supplementary model is required, identify which ones are typically used.

The core requirements to cover:

1. **Sentence boundary inference** — segmenting a continuous audio stream into discrete sentences.
2. **Punctuation prediction** — inserting commas, periods, question marks, exclamation marks in the right places.
3. **Filler-word removal** — stripping "um", "uh", "like", "you know", false starts.
4. **Paragraph breaks** — inserting paragraph separators based on pause length or topic shift.

For each: which engines do it natively, which don't, and what the standard drop-in supplementary models are.

## Follow-up — 2026-04-14

Paragraph break detection seems to be the least implemented of the four formatting features across both cloud and local models. Is there a technical reason for this, or is it purely a frontend responsibility (emulating a blank line)?
