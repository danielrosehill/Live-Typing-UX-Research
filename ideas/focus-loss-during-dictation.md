# Handling focus loss between dictation start and transcript arrival

**Question:** [`questions/focus-loss-during-dictation.md`](../questions/focus-loss-during-dictation.md)
**Written:** 14/04/26
**Stack:** Desktop live voice typing (real-time speech-to-text injecting into the focused window). Author's primary target is Ubuntu 25.10 / KDE Plasma / Wayland, but the patterns generalise to X11, macOS, and Windows.

## TL;DR

Cursor-injection dictation has an inherent race: the user starts speaking with one window focused, but by the time the transcript is ready to inject, focus may have moved. The standard mitigation is to also place the text on the clipboard so nothing is lost. Better designs go further — capture the *target window + caret* at dictation start, then either re-inject when the user returns to that window, or surface the pending text in a non-modal overlay the user can commit deliberately. On Wayland, what's actually implementable is sharply constrained by the compositor's input/focus security model, and that should drive the choice of pattern.

## Background

A live voice typing tool's job is to take audio and put text where the cursor is. The "where the cursor is" part is the unstable bit:

- ASR has latency (often hundreds of ms; seconds for longer utterances or chunked decoding).
- The user does not freeze while waiting. They alt-tab to read something, click a notification, scroll a doc, switch to a chat window to grab a quote.
- When the transcript arrives, the focused window is no longer the one the user was talking *to*. The tool's synthetic keystrokes land in the wrong place — sometimes harmlessly (a search box), sometimes destructively (a terminal, an IDE shortcut binding, a chat that auto-sends on Enter).

This is not an ASR problem. It is a UX/state-management problem at the boundary between the dictation tool and the windowing system. Every serious live-typing tool has to take a position on it.

## The patterns

### Pattern 1 — Inject blindly into whatever is focused now

The naive default. Tool listens, transcribes, calls `xdotool type` / `ydotool type` / `wtype` / Windows `SendInput` / macOS Accessibility into the currently focused window.

- **Pros:** trivial to implement; works fine for users who hold still.
- **Cons:** silently destructive when focus has moved. The user has no signal that anything went wrong until they look at the wrong window and find a sentence pasted into it.
- **Verdict:** unacceptable as a sole strategy. Usable only if combined with a strong "you must hold focus" affordance (push-to-talk + visible recording overlay anchored to the target window).

### Pattern 2 — Clipboard fallback (the "standard mitigation")

Inject *and* copy to the clipboard. If the keystrokes go to the wrong window, the user can undo and paste manually into the right one.

- **Pros:** zero loss of content; one extra Ctrl+V recovers. Implementable on any platform without privileged APIs.
- **Cons:** clobbers the user's existing clipboard contents (a real cost — they may have had something important copied). Recovery is manual: user must notice, undo the wrong injection, switch windows, paste. The wrong-window injection still happens.
- **Variants worth considering:**
  - **Clipboard-only mode** (no injection at all): the tool never types, it only copies; the user always pastes themselves. Eliminates the wrong-window problem at the cost of one extra keystroke per utterance. Some users prefer this as the *default* once they've been burned a few times.
  - **Clipboard ring / save-and-restore:** snapshot the existing clipboard at dictation start, place the transcript on the clipboard for N seconds or until next clipboard event, then restore. Reduces collateral damage. `clipnotify` / `wl-paste --watch` make this tractable.

### Pattern 3 — Capture-target, defer-inject

At the moment dictation *starts*, capture:

- The focused window's identifier (X11 window ID, Wayland — see caveats; macOS AXUIElement; Windows HWND).
- Where possible, the caret position within that window (rarely retrievable cross-app; usually you settle for "the window").

Then, when the transcript is ready:

- If the captured window is still focused: inject normally.
- If not: do *not* inject into the wrong window. Instead, hold the transcript in a pending state and either:
  - **Re-focus the original window automatically and inject** (most aggressive — may yank the user out of what they're now doing; usually a bad idea).
  - **Inject when the user next focuses the original window** (passive; the transcript "lands" the moment they return). This is the option the question asks about and it's the most respectful of user intent.
  - **Show a non-modal overlay** ("Transcript ready — click here, press hotkey, or refocus original window to insert") and let the user pick.

This is the strongest pattern and the one most worth building toward. It treats the *target* as part of the dictation session, not just "wherever focus happens to be".

### Pattern 4 — Anchored overlay / inline preview

Show the streaming transcript in a floating overlay anchored near the original caret position. Nothing is committed to the underlying app until the user explicitly accepts (Enter, hotkey, click). Focus changes during dictation are harmless because nothing is being typed into anything yet.

- **Pros:** removes the race entirely; user sees what they said before it goes anywhere; trivial editing/correction surface.
- **Cons:** breaks the "transparent typing" illusion — feels like a separate tool, not a keyboard replacement. Adds a commit step. Anchor positioning is hard on Wayland.
- **Where it shines:** longer utterances, dictation into apps with no undo, anything safety-critical.

### Pattern 5 — Confirmation-on-mismatch

Hybrid. Inject only if the focused window matches the captured target. On mismatch, fall back to overlay or clipboard with a notification ("Focus changed — transcript saved to clipboard / pending in tray"). Cheap to implement, sharply reduces silent failures.

## What's actually implementable on Wayland

The platform constrains the design space more than the design space constrains the platform.

- **X11:** every part of patterns 3/4/5 is feasible. `xdotool getactivewindow` gives you a stable window ID at start; you can re-check it later, you can warp focus back, you can inject with `xdotool type --window <id>` directly into a target window even when it isn't focused (with caveats per app).
- **Wayland (KDE/Plasma, GNOME):** by design, no client can globally enumerate windows or know which client owns focus. There is no portable equivalent of `getactivewindow`. Synthetic input via `wtype` requires a virtual-keyboard protocol the compositor must allow; `ydotool` works at the uinput level but injects into *whatever is focused now*, which is exactly the problem pattern 3 is trying to solve.
  - KWin (KDE) exposes some of this via D-Bus / KWin scripting, but it's KDE-specific.
  - The XDG desktop portals do not currently provide a "remember target window and re-inject later" primitive. This is a real gap.
  - Practical consequence: on Wayland, **pattern 4 (overlay) is often the only honest option** for the deferred-inject case, because you can't reliably distinguish "same window" from "different window" later. The overlay sidesteps the whole problem by never injecting at all until the user explicitly commits.
- **macOS:** Accessibility APIs give you AXUIElement references to text fields; with permission, you can read and write them directly. Patterns 3 and 4 are both clean.
- **Windows:** UI Automation + HWND tracking make patterns 3 and 5 straightforward.

## A recommended layered default

For a tool that has to work across desktops, layer the patterns:

1. **Always** copy the transcript to the clipboard (pattern 2), with a clipboard save-and-restore variant if feasible. This is the floor — content is never lost.
2. **Capture the target window at dictation start** where the platform allows (X11, macOS, Windows). On Wayland, capture whatever the compositor will give you (sometimes nothing).
3. **At injection time**, check whether focus is still on the captured target.
   - Same target → inject inline.
   - Different target → do **not** inject. Show a non-modal overlay/notification ("Transcript ready — refocus <Window> or click to insert"). Inject automatically when the captured target regains focus, with a short timeout (e.g. 30 s) after which the transcript is left only on the clipboard and the pending state is dropped.
4. **Offer pattern 4 (anchored overlay with explicit commit)** as a per-session or per-app mode, for users who want zero surprise injection.

This gives the user three escape hatches — automatic re-injection on return, clipboard paste, overlay click — and removes the silent-wrong-window failure mode entirely.

## Verification

A focus-loss strategy is working if all of the following hold during deliberate testing:

- Start dictation in window A, immediately switch to window B, finish speaking. **No text appears in B.**
- Return to window A. The transcript appears at the caret (or the user can trigger it with one action).
- Clipboard contains the transcript as a fallback regardless.
- If a pre-existing clipboard value was present, it is either preserved (save-and-restore) or the user has been warned.
- On Wayland, where target tracking is unavailable, the tool degrades to the overlay/clipboard path rather than blindly injecting into B.

## Caveats / things that can go wrong

- **Auto-injection on return can still fire into the wrong place** if the user returned to window A but moved the caret elsewhere within A (e.g. clicked a different field). Mitigation: also verify the focused *widget* matches, where the platform exposes that; otherwise prefer the overlay/click-to-commit path.
- **Re-focus warping** (forcing window A back to the front to inject) is hostile UX and prone to fighting the user's current action. Avoid except as an explicit user choice.
- **Clipboard managers** (KDE Klipper, CopyQ, etc.) will record every transcript as a clipboard history entry unless the tool tags clipboard writes as transient. KDE's Klipper respects the X-KDE-Klipper-Selection-Manager hint; check the equivalent for the user's clipboard manager.
- **Password fields** should never receive auto-injection. Detect where possible (macOS AX, Windows UIA expose this; Linux generally does not) and refuse to inject; force the overlay path.
- **Terminals** interpret some characters specially (Ctrl-sequences, multi-line paste behaviour). Bracketed paste mode helps. Many users will want a terminal-specific mode that only ever uses the clipboard.
- **Wayland compositor differences:** what works on KWin won't work on Mutter or Sway. Don't promise pattern 3 cross-compositor without per-compositor implementations.
- **Latency-vs-correctness:** the longer the deferred-inject window, the more likely the user has moved on mentally. A 30 s pending overlay is reasonable; a 5 minute one is just clutter.

## References

- `wtype` — Wayland virtual-keyboard typing utility: <https://github.com/atx/wtype>
- `ydotool` — uinput-based input injection (Wayland-compatible, root/uinput required): <https://github.com/ReimuNotMoe/ydotool>
- `xdotool` — X11 keyboard/mouse/window automation: <https://www.semicomplete.com/projects/xdotool/>
- KWin scripting / D-Bus interface (KDE Plasma window introspection): <https://develop.kde.org/docs/plasma/kwin/>
- XDG Desktop Portal — Global Shortcuts and RemoteDesktop portals (closest thing to a cross-compositor input API): <https://flatpak.github.io/xdg-desktop-portal/>
- nerd-dictation — minimal local dictation tool, useful reference for the inject-on-finalise pattern: <https://github.com/ideasman42/nerd-dictation>
- Talon Voice — production voice-control system, exemplar of pattern 4 (overlay + explicit commit) and target-aware behaviour: <https://talonvoice.com/>
