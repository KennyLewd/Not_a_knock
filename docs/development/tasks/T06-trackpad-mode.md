# T06 — Trackpad gestures, Morse shortcuts, and permissions

## Objective

Rescoped by the user on 2026-09-10. The original plan was a universal fallback that
detected clicks while a modifier key was held. That is superseded by two new ideas:

1. A three-finger double-tap on the trackpad toggles detection on and off, using the
   same gesture for both, so Knock can be armed without touching its window.
2. Trackpad taps are interpreted as Morse code, and a decoded letter activates a
   running application whose name starts with that letter. The user's example is
   tap-tap-tap for `S`, activating Safari.

Trackpad mode must still serve its original purpose: a usable input path on Macs
whose accelerometer is unsupported.

## Blocking feasibility question — resolve before building anything else

Whether a global three-finger double-tap is detectable with public APIs is unknown
and must be settled first, inside the app where permissions already exist.

- `NSEvent.addGlobalMonitorForEvents` plus `NSEvent.touches(matching:in:)` can report
  finger counts, but macOS may deliver no event at all for a stationary multi-finger
  tap, because touch data usually rides along with a recognized gesture.
- The framework third-party tools use for arbitrary multi-finger taps is
  `MultitouchSupport`, which is **private**. PROJECT.md requires public APIs and no
  private symbols. T05's accelerometer work is not a precedent for this: it used
  public IOKit functions against an undocumented report *format*, a deliberately
  narrower exception than linking a private framework.
- A CLI probe cannot answer this. Without Accessibility it fails identically to an
  unsupported API, so the spike must run inside the signed app bundle.

Report the finding before implementing. If public APIs cannot see the gesture, stop
and put the alternatives to the user rather than reaching for a private framework:
a two-finger or four-finger variant, a modifier-plus-click chord, a global hotkey, or
an explicit decision to accept a private dependency with its breakage risk recorded.

## Design conflicts to settle with the user

- **Morse collides with the existing pattern model.** `···` is Morse for `S` and is
  also Triple Knock. The same taps cannot mean both, so Morse has to be a distinct
  mode rather than an addition, and switching modes must be explicit.
- **Dots alone cover only four letters.** Without long presses the reachable set is
  E `·`, I `··`, S `···`, H `····`. That happens to line up with 1–4 taps, and the
  user's tap-tap-tap example is exactly the all-dots case. Anything beyond needs a
  short/long distinction, which is a real jump in required input fidelity and needs
  its own timing thresholds and calibration.
- **Letter to application is ambiguous.** Several running apps commonly start with
  the same letter — Safari, Slack, Spotify, System Settings. A rule is required.
  Suggested default: the most recently used running application with that initial,
  with a user-visible list showing what a letter currently resolves to, since the
  answer changes as apps open and close.
- **Activate or launch.** The user said "is currently open", implying activation of a
  running app via `NSRunningApplication.activate()`. Decide whether an unmatched
  letter does nothing or falls back to launching.
- **Interaction with T05 suppression is fine and should stay.** MacBook mode ignores
  trackpad contact for 300 ms, so the toggle gesture will not also register as knocks.
  That is desirable, not a conflict.

## Acceptance criteria

- Document whether the three-finger double-tap is achievable with public APIs, with
  evidence, before any gesture code ships.
- The toggle gesture arms and disarms detection reliably, is not triggered by ordinary
  trackpad use, and cannot leave detection in a state the UI misreports.
- Trackpad mode detects deliberate input on a Mac without accelerometer support, and
  states which permission it needs and why.
- Morse mode is separate from pattern mode, with an explicit switch and clear UI about
  which is active and what the current mapping resolves to.
- Letter-to-application resolution is deterministic, visible to the user before use,
  and does nothing harmful when no match exists.
- Ordinary trackpad use — pointing, clicking, scrolling, dragging, tap-to-click —
  does not trigger Morse input or the toggle.
- Actions report a user-actionable error instead of failing silently. This is T07's
  main job but the silent-failure defect found in T05 must not be extended here.

## Checks

Run Tests/run-checks.sh and build the native app. Unit-test Morse decoding and
letter-to-application resolution with injected clocks and a stubbed application list,
so no test depends on which apps happen to be running. Physically verify the toggle
gesture, a full Morse trial, and that normal trackpad work triggers nothing. Record
real results and the user's trackpad settings, including whether tap-to-click is on,
which changed the outcome in T05.
