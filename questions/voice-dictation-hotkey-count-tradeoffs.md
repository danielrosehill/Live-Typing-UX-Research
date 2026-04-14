# Hotkey count tradeoffs for voice dictation control (single key, macro pads)

**Asked:** 14/04/26
**Slug:** `voice-dictation-hotkey-count-tradeoffs`
**Response:** [`ideas/voice-dictation-hotkey-count-tradeoffs.md`](../ideas/voice-dictation-hotkey-count-tradeoffs.md)

## The question

A friction point I'm hitting with Handy using its single-hotkey transcription model: there's no way to release or discard a dictation in flight. The single hotkey is a start/stop toggle, so there's no retake — if I misspeak, the only option is to let it finish and then delete what was inserted.

This is a fundamental limitation of the single-hotkey approach. You could overload it with something like a quick double-tap, but that's not a control I'd have proactively identified as a user.

For documenting macro-pad designs built specifically for voice dictation, the progression seems to be:

- **One key** — start/stop toggle. No retake.
- **Two keys** — separate start and stop triggers.
- **Three keys** — add restart (cancel current, begin a new utterance).
- **Four keys** — add discard without restarting (cancel without immediately starting again).

What's the full design space here, and what are the tradeoffs at each level?
