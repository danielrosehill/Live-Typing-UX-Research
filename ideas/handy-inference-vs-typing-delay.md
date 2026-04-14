# Handy's 10–20 second print delay is almost entirely keystroke-injection pacing, not inference

**Question:** [`questions/handy-inference-vs-typing-delay.md`](../questions/handy-inference-vs-typing-delay.md)
**Written:** 14/04/26
**Stack:** Handy (open-source desktop dictation, Rust + Tauri) running Parakeet-TDT or Whisper locally. Ubuntu 25.10 / KDE / Wayland. Local GPU inference.

## TL;DR

What you're watching is **not** streaming inference. Handy (like most "push-to-talk → transcribe-on-release" tools) is architecturally a **batch** pipeline: audio in → one offline inference pass → finished transcript string → typed out character-by-character into the focused window. For a few paragraphs on a modern GPU, Parakeet-TDT finishes inference in **~0.5–3 seconds** total. The remaining 10–20 seconds you observe is the **keyboard-injection layer** — the tool deliberately paces synthetic keystrokes at ~5–30 ms per character to avoid dropped events in target apps. On a 1500-character transcript at 15 ms/char, that's ~22 s of visible "typing". So yes, **the delay is essentially artificial**, and the mechanism is pacing of the input-synthesis layer, not live transcription.

## Background

Handy follows a well-known pattern for desktop dictation:

1. Hold PTT key → record audio to a buffer.
2. Release PTT key → pass the full buffer to an offline ASR model (Parakeet-TDT, Whisper, Moonshine-offline).
3. Model returns a finished transcript string.
4. Tool synthesises keystrokes that type that string into whatever window has focus.

Steps 2 and 4 are what the user experiences as "the delay". They are **independent stages** that can each contribute latency, and it matters which one dominates because the fixes are completely different.

The user's intuition — "am I watching the model think, or am I watching the UI deliberately feed characters slowly?" — is the right axis to separate. They have different scaling behaviour:

- **Inference time** scales roughly with audio duration (GPU compute per second of audio).
- **Injection time** scales with character count (keystroke count × per-keystroke delay).

A quick back-of-envelope test distinguishes them: speak a long, slow monologue (lots of audio, few words) vs. a short, information-dense burst (little audio, many words). If the delay tracks audio duration, it's inference. If it tracks character count, it's injection.

## Stage 1: the inference itself

Handy supports multiple backends, but the practical defaults are:

| Model | Engine / runtime | Approx RTF on consumer GPU | Approx wall time for 60 s of audio |
|---|---|---|---|
| **Parakeet-TDT 0.6B v2** | ONNX / `parakeet-rs` / NeMo | ~0.02–0.05× real-time (i.e., 20–50× faster than real-time) on RTX 3060+ | ~1.2–3 s |
| **Whisper large-v3** (ggml via whisper.cpp) | CPU: 0.3–0.8× RTF. GPU (CUDA): 0.05–0.15× RTF. | ~4–50 s on CPU, ~3–9 s on GPU |
| **Whisper medium** (whisper.cpp) | CPU ~0.2× RTF, GPU ~0.03× | ~2–12 s |
| **Moonshine-base** (ONNX) | ~0.05× RTF on CPU, faster on GPU | ~1–3 s |

RTF = "real-time factor" = processing_time / audio_duration. Smaller is faster.

Parakeet-TDT on a GPU is the "effectively instantaneous" tier — you dictate for a minute, and the model hands back the full transcript in 1–3 seconds. A "few paragraphs" of spoken content is maybe 30–60 s of audio, which puts inference comfortably under 3 s on GPU, under ~8 s on a reasonable CPU-only build.

**If you are seeing 10–20 s before the first character appears**, and nothing appears until the end, that could be inference. But if characters start appearing quickly and the "delay" is characters rolling out across the screen, inference is almost certainly already done.

### How to confirm inference time directly

Handy logs inference duration to its console / log file (Handy's dev builds print this; release builds may require turning on verbose logging). Alternatively, run the model under the same runtime outside Handy:

```bash
# Parakeet via nemo (or parakeet-mlx / parakeet-rs)
time python -c "import nemo.collections.asr as nemo_asr; m = nemo_asr.models.ASRModel.from_pretrained('nvidia/parakeet-tdt-0.6b-v2'); print(m.transcribe(['/tmp/sample.wav']))"

# Whisper via whisper.cpp
time ./main -m models/ggml-medium.bin -f /tmp/sample.wav
```

Compare the `real` time to the audio length. If it's <10% of the audio length, inference isn't your bottleneck.

## Stage 2: the injection — this is almost certainly the real culprit

Desktop dictation tools have to choose an input-synthesis strategy. On Linux/Wayland specifically, the options are:

| Mechanism | How it works | Speed characteristics |
|---|---|---|
| **Synthetic keystrokes via virtual keyboard** (`ydotool`, `wlrctl`, `enigo` with `uinput`) | Tool emits KEY_DOWN/KEY_UP events per character via `uinput`. Each character = 1–3 kernel events + a short sleep. | Paced. Typically 5–30 ms/char. |
| **Input method / IME injection** (IBus, Fcitx protocol) | Tool pretends to be an IME, commits a string in one shot. | Nearly instantaneous; complex to implement; some apps ignore IME. |
| **Clipboard + paste** | Transcript → clipboard → synthesise Ctrl+V. | Instant once the clipboard is set. |
| **X11 XTest / XSendEvent** | On X11 only. Fast, but Wayland sessions don't expose it for arbitrary windows. | Instant-ish, but X11-only. |

**Most cross-platform dictation tools, including Handy, default to the "synthesise keystrokes one at a time" path.** The reason is reliability — it works in every focused app (terminals, browsers, IDEs, chat boxes, address bars) without per-app quirks. The cost is that it is **paced**.

### Why it's paced at all

Without a delay between keystrokes, you hit several failure modes:

1. **Dropped events** — target apps with expensive per-keystroke work (IDEs running syntax analysis, terminals with bracketed-paste handlers, web apps with oninput listeners) drop characters if they arrive faster than the event loop can process.
2. **Auto-completion interference** — editors with autocomplete or snippet engines interpret mid-stream characters and inject unwanted text.
3. **Modifier-key sequencing** — capital letters, accented characters, and non-ASCII glyphs need SHIFT held, dead-key compositions, or Unicode code-point entry. These require multi-event sequences that can't reliably run back-to-back without a hold time.
4. **`uinput` syncing** — the kernel batches events; too-rapid submission drops some devices.

So every mature tool settles on a **per-character delay**, usually configurable. Typical defaults:

| Tool | Default per-key delay |
|---|---|
| `ydotool` | ~12 ms |
| `xdotool type --delay` | default 12 ms |
| `enigo` (Rust crate, used by many Tauri apps including Handy) | no built-in delay, but applications using it typically add a sleep |
| AutoHotkey `Send` modes | `SendInput` ~0 ms, `SendEvent` 10 ms, `SendPlay` variable |

### The math of the visible delay

At 15 ms/character:

| Transcript length | Visible typing time |
|---|---|
| 200 chars (~40 words) | 3 s |
| 500 chars (~100 words) | 7.5 s |
| 1000 chars (~200 words, a short paragraph) | 15 s |
| 1500 chars (~300 words, a few paragraphs) | 22.5 s |
| 3000 chars (~600 words, a page) | 45 s |

This is the shape that matches the user's observation exactly. "A few paragraphs → 10–20 s" is the injection layer doing its paced thing, not the model thinking.

## So is it "artificial"?

It's **designed**, not accidental — but from the user's point of view, yes: the delay between "inference complete" and "all characters on screen" exists purely because the tool chose keystroke synthesis with pacing as its injection strategy. Three things are true simultaneously:

1. **You are not watching the model transcribe live.** Inference finished seconds ago; the string is sitting in memory waiting to be typed.
2. **The pacing is deliberate and reasonable by default.** Removing it would cause dropped characters and mangled output in many target apps.
3. **It is still the dominant contributor to the perceived latency** for any transcript longer than a sentence. On a GPU with Parakeet, inference is 1–3 s and injection is 10–20 s.

## What you can do about it

If the goal is to make the output *appear* faster without rewriting Handy:

### Switch injection mode to paste

Paste is instant. Many dictation tools expose a "paste instead of type" setting, sometimes called "fast mode" or "clipboard mode".

- Pros: transcript appears in one go, ~0 ms after inference.
- Cons: overwrites the clipboard (mitigable with save/restore); some apps block programmatic Ctrl+V; loses the "typing character-by-character at the cursor" UX that matches keyboard input.

Check Handy's config for `paste` / `inject_mode` / similar; if absent, it's a reasonable feature request.

### Lower the per-keystroke delay

If Handy exposes a keystroke delay (or uses `enigo` / `ydotool` with a configurable interval), drop it. Going from 15 ms → 3 ms per character cuts a 20-second "typing" to 4 seconds. Watch for dropped characters in your target apps; dial it back up if you see them.

### Use an IME-based injection

Fcitx/IBus commit-string injection puts the full transcript into the IME's composition buffer in one go. This is how Japanese/Chinese input methods work natively, and it's the cleanest mechanism on Wayland. Not many cross-platform tools implement it (complexity, per-desktop wiring), but if Handy ever grows an IME backend, this is the path to near-instant injection without a clipboard round-trip.

### Or: switch the entire pattern to streaming

If you want to actually watch words appear as they are transcribed (not as they are typed out of a finished string), that's a **different architecture** — streaming ASR (Deepgram, AssemblyAI Universal-Streaming, Parakeet-TDT-streaming, Moonshine-streaming) where interim results arrive every ~200–300 ms during dictation. See [`whisper-vs-streaming-asr-for-dictation`](whisper-vs-streaming-asr-for-dictation.md) and [`inference-cadence-and-sentence-entry`](inference-cadence-and-sentence-entry.md) for that shape.

## Verification — quick test you can run

1. **Time-to-first-character test.** Dictate a long passage and watch the time from PTT release to the first character landing. If that gap is short (<3 s) but the full transcript takes 15 s to finish typing, injection is the bottleneck. If time-to-first-character is long and then the rest lands quickly, inference is.
2. **Character-count scaling.** Dictate (a) 30 s of slow speech vs. (b) 10 s of very dense speech of roughly the same word count. If both take similar total "print" time, it's injection. If (a) takes ~3× longer, it's inference.
3. **Log inspection.** Run Handy with verbose logging (or check its log file) for an "inference time" or "transcribe ms" line. That number is almost always much smaller than the observed total delay.

## References

- `ydotool` default delay and config: [github.com/ReimuNotMoe/ydotool](https://github.com/ReimuNotMoe/ydotool)
- `xdotool type --delay` default: [man.archlinux.org/man/xdotool.1](https://man.archlinux.org/man/xdotool.1)
- `enigo` Rust crate (commonly used by Tauri desktop apps for key injection): [github.com/enigo-rs/enigo](https://github.com/enigo-rs/enigo)
- Parakeet-TDT 0.6B v2 model card (RTF benchmarks): [huggingface.co/nvidia/parakeet-tdt-0.6b-v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)
- `whisper.cpp` benchmarks: [github.com/ggerganov/whisper.cpp#benchmarks](https://github.com/ggerganov/whisper.cpp)
- Moonshine: [github.com/usefulsensors/moonshine](https://github.com/usefulsensors/moonshine)
- Wayland input synthesis background — `wlroots` virtual-keyboard protocol: [wayland.app/protocols/virtual-keyboard-unstable-v1](https://wayland.app/protocols/virtual-keyboard-unstable-v1)
- Related topics:
  - [`batch-vs-chunked-inference-accuracy`](batch-vs-chunked-inference-accuracy.md) — why a batch pipeline like Handy can be a deliberate accuracy choice.
  - [`streaming-vs-batch-injection`](streaming-vs-batch-injection.md) — the injection axis on its own.
  - [`inference-cadence-and-sentence-entry`](inference-cadence-and-sentence-entry.md) — what the three "live-feel" intervals are for true streaming systems.
  - [`focus-loss-during-dictation`](focus-loss-during-dictation.md) — why paced injection is a liability when focus shifts mid-type.

## Caveats

- Exact defaults depend on the Handy version and which backend is compiled in (Parakeet vs Whisper vs Moonshine) — run the time-to-first-char test on your own build to confirm the split.
- The 5–30 ms/char range is typical of `uinput`-style keystroke synthesis; some builds use shorter delays with batching or longer delays for reliability. If Handy exposes a config key for injection speed, its value is the definitive answer.
- On X11 (not Wayland), XTest-based injection can be much faster (sub-millisecond per keystroke) because events go straight to the X server rather than through `uinput`. If you run Handy under Xwayland or an X11 session, the pacing math above changes.
- "Inference in 1–3 s" assumes a GPU backend. CPU-only whisper.cpp on Whisper-medium/large can reach inference times that genuinely contribute 5–15 s to the observed delay.

## Follow-up — 2026-04-14: one-shot automatic injection on Wayland

**Question:** ydotool paced typing feels like the worst of both worlds — you don't get live streaming, and you still wait through a fake typing animation. Manual paste isn't acceptable either. What is "set the clipboard, fire Ctrl+V automatically, done" called, and how do you implement it on Wayland?

### Names for the pattern

There isn't one universal term; these are the ones used interchangeably in dictation tooling:

- **Paste-based injection** / **paste injection** — most common name in open-source STT tools.
- **Clipboard injection** / **clipboard paste** — same thing, viewed from the clipboard side.
- **Auto-paste** / **programmatic paste** — user-facing label (often a config toggle: `use_paste = true`, `fast_mode`, `instant_mode`).
- **Bulk injection** — generic term contrasting with keystroke-by-keystroke synthesis.
- **Commit-string injection** — specifically the IME route (next section); distinct from clipboard paste because it doesn't touch the clipboard at all.

If you grep a dictation tool's source or config for any of these terms, you're looking at the same mechanism.

### Two real mechanisms on Wayland

**(1) Clipboard + synthetic Ctrl+V — the ubiquitous path.**

This is what almost every "fast mode" dictation tool actually does. Three steps:

```bash
# 1. Put the transcript on the clipboard
wl-copy "<transcript>"

# 2. Synthesise Ctrl+V into the focused window
ydotool key 29:1 47:1 47:0 29:0   # LCTRL down, V down, V up, LCTRL up
#   or, with key names: ydotool key ctrl+v

# 3. (Optional) Restore previous clipboard contents after a short delay
```

You already have `ydotool` installed — add `wl-clipboard` (`sudo apt install wl-clipboard`) and you have all the pieces. Total injection time: ~10–50 ms regardless of transcript length.

Gotchas that make this "not quite free":

- **Clipboard pollution.** The user's previous clipboard contents get overwritten. Robust tools save the prior clipboard with `wl-paste`, then restore it ~200 ms after pasting.
- **Primary vs clipboard selection.** Wayland, like X11, distinguishes the clipboard (`Ctrl+V`) from the primary selection (middle-click). `wl-copy -p` sets the primary; bare `wl-copy` sets the clipboard. Use the clipboard; it's what Ctrl+V consumes.
- **Terminals and bracketed paste.** Terminals that enable bracketed paste mode will wrap the injected text in `ESC[200~…ESC[201~`, which is usually desired (suppresses control-character interpretation). Some terminals or shells with bracketed paste disabled will interpret newlines and tabs in the transcript as input.
- **Apps that block programmatic Ctrl+V.** Rare on Linux, but some Electron/web apps listen for the `paste` event's `isTrusted` flag and reject synthetic events. Fallback is per-app.
- **ydotool daemon must be running.** `ydotoold` needs to be a running service with your user in the `input` group (or it needs `uinput` access). If `ydotool key ctrl+v` is silent, check `systemctl --user status ydotoold`.
- **Non-latin / mixed-script content.** The clipboard carries a UTF-8 string — no keycode mapping needed, no layout issues, no dead-key composition problems. This is a real advantage over keystroke synthesis: emoji, Hebrew, accented characters all Just Work.
- **Focus race.** If focus moves between the `wl-copy` call and the `ydotool` Ctrl+V, the paste lands in the wrong window. Same risk as paced typing, but now a single-shot mistake instead of a partial one. See [`focus-loss-during-dictation`](focus-loss-during-dictation.md).

**(2) IME commit-string via Fcitx / IBus — the "proper" way, rarely implemented.**

Wayland's native mechanism for an external process to put text into a focused editor is the input-method / text-input protocol pair (`zwp_input_method_v2` ↔ `zwp_text_input_v3`). An IME calls `commit_string`, and the app receives the text as a single atomic input event — no keystrokes, no clipboard.

- **Pros:** no clipboard pollution; no paste-event quirks; works in any text-input-v3-aware app regardless of key-layout; indistinguishable from a real IME like Fcitx typing Japanese.
- **Cons:** you have to implement (or piggyback on) Fcitx5 or IBus as an IME addon. Some apps still don't implement `zwp_text_input_v3` correctly — GTK4 and Qt6 do; Electron is patchy; terminals vary.
- **In practice:** almost no open-source dictation tool for the Linux desktop ships an IME backend. The path of least resistance has been clipboard-paste, and it's "good enough" for most users.

You can prototype the IME route by writing a small Fcitx5 addon that receives a transcript over a Unix socket and calls `commit_string`, but it's a weekend project and you get roughly the same user-visible result as wl-copy+Ctrl+V with fewer quirks.

### What to look for in Handy

Based on the pattern every similar tool follows, look for one of these in Handy's config (usually `~/.config/handy/config.toml` or similar):

- `output_mode`, `injection_mode`, `typing_mode` — a string/enum with values like `"type"` / `"paste"` / `"clipboard"`.
- A boolean like `use_paste` / `paste_on_commit` / `fast_mode` / `instant_inject`.
- A per-character delay (`type_delay_ms`, `keystroke_delay_ms`) — if present and there's no paste mode yet, dropping it to 1–2 ms gives you near-instant typing at the risk of dropped events.

If none of those exist, Handy hasn't exposed the choice and a small patch (set clipboard → send Ctrl+V → restore clipboard) is the minimum viable change. Filing it as a feature request is reasonable; most Linux-facing STT tools have landed this feature under a name like "paste mode" after enough users asked.

### Tools that already ship this

For reference — these all implement some variant of auto-paste as the default or an option:

- **nerd-dictation** (Blender-author's tool) — `--output SIMULATE_INPUT_TYPE=PASTE` uses the clipboard path.
- **Whispering** (open-source) — "Paste mode" toggle.
- **Talon Voice** — output strategies include clipboard paste.
- **Dragon for Linux** (there isn't one, but on macOS, all modern STT tools default to paste).
- **Vibe** / **Whisper-keyboard** / many GNOME extensions — clipboard paste is the near-universal default for batch-mode tools.

### Recommendation

For your stack (Ubuntu 25.10, KDE Wayland, ydotool already present): the one-line answer is **"paste-based injection via `wl-copy` + synthesised Ctrl+V"**, and you can validate the UX immediately with a shell pipeline before touching Handy's source:

```bash
# Swap Handy's typing call for this, in spirit:
TEXT="<whatever Handy just transcribed>"
OLD_CLIP="$(wl-paste 2>/dev/null)" || OLD_CLIP=""
printf '%s' "$TEXT" | wl-copy
ydotool key ctrl+v
sleep 0.3
printf '%s' "$OLD_CLIP" | wl-copy
```

That's the whole pattern. When someone says "paste mode" / "fast mode" / "instant injection" in the dictation-tool ecosystem, this is what they mean. The IME-commit route is the same outcome through a cleaner protocol, but it's not something you wire up in an afternoon.

## Follow-up — 2026-04-14: Handy's "Paste Method" setting, decoded

**Question:** In Handy's settings there's a "Paste Method" dropdown with options *Direct*, *Clipboard (Ctrl+V)*, *Clipboard (Ctrl+Shift+V)*, *Clipboard (Shift+Insert)*, *None*, *External Script*. Does "paste" here mean automatic injection, or does it require the user to press Ctrl+V manually?

Handy's "Paste Method" is the **umbrella name for the output stage**, not a setting specifically about manual pasting. Mildly confusing naming — "Output Method" would have been clearer. Per the [official docs](https://handy.computer/docs/paste-methods), only **one** of the six options requires user intervention:

| Option | Mechanism | Automatic? |
|---|---|---|
| **Clipboard (Ctrl+V)** | Sets clipboard, then synthesises Ctrl+V. Default on macOS and Windows. | Yes |
| **Clipboard (Ctrl+Shift+V)** | Same, with Ctrl+Shift+V — for apps that intercept plain Ctrl+V. | Yes |
| **Clipboard (Shift+Insert)** | Same, with Shift+Insert — recommended for Windows Terminal / PowerShell. | Yes |
| **Direct** | Types character-by-character with no clipboard. This is the paced-typing path described in the main response. Caveat: doesn't respect non-US keyboard layouts (AZERTY, QWERTZ garble). | Yes, but paced |
| **None** | Copies to clipboard only; user hits Ctrl+V themselves. | **No — manual** |
| **External Script** (Linux only) | Runs a user-provided script; transcript passed on stdin. | Custom |

Two companion settings matter on Linux:

- **Typing Tool**: picks the backend used to *simulate the paste keystroke* for clipboard-based methods — `wtype`, `kwtype`, `dotool`, `ydotool`, `xdotool`, or `Auto`. Only relevant when Paste Method is one of the Clipboard variants or Direct.
- **Clipboard Handling**: `Don't Modify Clipboard` (saves and restores prior clipboard contents) vs `Copy to Clipboard` (leaves the transcript on the clipboard for reuse).

### Applied recommendation for Daniel's stack (Ubuntu 25.10 / KDE / Wayland)

1. **Paste Method** → `Clipboard (Ctrl+V)`. This is the auto-paste pattern from earlier in this note — one-shot, layout-safe, instant regardless of transcript length.
2. **Typing Tool** → `ydotool` (explicit) or `Auto`. `wtype` also works on wlroots but KDE/Kwin support for `wtype` has historically been patchy; `ydotool` via its daemon is the reliable path.
3. **Clipboard Handling** → `Don't Modify Clipboard` if you rely on clipboard managers or multi-item clipboards; `Copy to Clipboard` if you want the transcript to persist for re-paste.
4. Leave `Direct` aside — it's the slow one, and on a non-US layout it would also garble characters.

### Observed issues worth flagging

- [`cjpais/Handy#692`](https://github.com/cjpais/Handy/issues/692): `Direct` mode repeats/breaks text in terminals when dictating into Claude Code / Codex. Switching to any Clipboard variant fixes it — further evidence that Direct's per-character keystroke synthesis fights terminals' input handling.
- [`cjpais/Handy#439`](https://github.com/cjpais/Handy/issues/439): `Direct` doesn't respect non-US keyboard layouts.

Both arguments for preferring a Clipboard paste method on Linux regardless of the latency framing.
