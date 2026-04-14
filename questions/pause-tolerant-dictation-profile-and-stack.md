# Pause-tolerant dictation — codify this user profile and recommend an STT stack

**Ideas:** [`ideas/pause-tolerant-dictation-profile-and-stack.md`](../ideas/pause-tolerant-dictation-profile-and-stack.md)
**Asked:** 14/04/26

Given the user profile below, produce a specification for the ideal live-typing STT stack and recommend concrete models and tooling (cloud and local).

## User profile

- **Long thinking pauses** mid-dictation, commonly 3–20 seconds. Requires **absolute certainty** that pauses do not trigger hallucinated content — applies equally to cloud and local models. Hard requirement, not a preference.
- **Output should be post-processed**: inferred paragraph breaks, sentence structure, removal of filler words ("um", "uh", "you know") and false starts.
- **Primary workload**: general desktop typing, with heavy emphasis on dictating prompts to AI agents — precision and nuance matter, especially for editing instructions where a misheard word changes the meaning of an edit.
- **Framing**: STT is a flow-state productivity tool, not just transcription. The goal is to minimise friction between thought and instruction.
- **Preferred frontend UX**: periodic text output at roughly a **~20-second cadence**. Too-real-time rendering creates a "being watched" pressure that breaks flow. A ~20 s cadence provides reassurance that inference is working without turning typing into a performance.

## What the answer should contain

1. A named user archetype and a codified checklist of requirements.
2. A derived technical specification — pause tolerance, post-processing pipeline, injection cadence, accuracy bar.
3. A cloud recommendation table (Deepgram, AssemblyAI, Speechmatics, OpenAI, ElevenLabs) with the specific knobs that matter for this profile.
4. A local recommendation (Whisper-family with VAD, Parakeet/Canary, Moonshine, whisper-streaming).
5. Frontend tools whose UX already matches this profile.
6. A concrete recommended architecture (the "ideal spec" as a pipeline).
7. Anti-patterns to avoid.
