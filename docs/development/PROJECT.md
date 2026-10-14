# Knock-inspired macOS app

## Product vision

Build an original macOS utility with the same core concept as Knock: recognize single, double, and triple physical taps and immediately run user-selected Mac actions. The experience should feel small, fast, premium, and native.

## MVP experience

- A dark SwiftUI control panel with a compact sidebar.
- Separate action assignments for Single, Double, and Triple Knock.
- Two input modes:
  - MacBook mode detects short impact impulses through supported public input APIs.
  - Trackpad mode detects clicks while the user holds a configurable modifier key.
- Built-in test buttons that exercise every pattern without hardware input.
- Useful actions: copy, paste, screenshot, lock, mute, play/pause, Mission Control, app launch, Apple Shortcut, and visual reactions.
- Menu bar control, launch-at-login option, permission guidance, activity history, and local persistence.

## Product boundaries

- This is an original implementation, not a copy of proprietary source or artwork.
- Version 1 targets macOS 14 or newer and Apple silicon first.
- The app works offline. No account, analytics, or cloud backend is required for the MVP.
- Chassis taps use the built-in accelerometer on compatible Macs. Access uses public IOKit functions, but the Apple SPU report format is undocumented and must be validated per hardware/OS. No microphone fallback; unsupported Macs use Trackpad mode (T06).
- App Store distribution is not assumed. Some automation features may be better suited to direct distribution because of sandbox restrictions.

## Architecture

- `Knock/Models`: patterns, actions, settings, and activity models.
- `Knock/Services`: detection engines, action execution, permissions, persistence, and launch-at-login.
- `Knock/Views`: SwiftUI app shell, dashboard, action picker, activity, settings, onboarding, and reactions.
- Detector implementations conform to one protocol so hardware experiments do not leak into the UI.
- Action execution is centralized and reports success or a user-actionable permission error.
- User preferences are stored locally with `UserDefaults`; activity history is bounded.

## Design direction

- Near-black layered surfaces, subtle borders, rounded cards, restrained shadows.
- Blue, orange, and purple/pink gradients distinguish the three knock patterns.
- SF Symbols and original visuals only.
- Minimal copy, strong hierarchy, responsive hover/press states, full keyboard access, and reduced-motion support.

## Decisions

- 2026-09-08: Build a native macOS SwiftUI app rather than an iPhone app or website.
- 2026-09-08: Use public APIs and provide a universal Trackpad fallback.
- 2026-09-08: Organize work into one verified task per Codex turn to reduce repeated context and usage.
- 2026-09-08 (T01): Use `dev.local.Knock` as a temporary development bundle identifier and ad-hoc signing for local runs without a developer account. The development target is unsandboxed to accommodate the existing automation draft; distribution decisions remain open.

- 2026-09-08 (T04): Group raw input using a monotonic clock, 75 ms debounce and
  460 ms timeout by default. Cap a sequence at three accepted taps; extra input
  after that cap does not extend its timeout. A simulated test replaces unfinished
  input and temporarily excludes hardware impulses, then resumes normal listening.

- 2026-09-08 (T05, superseded by the user on September 9): Use AVAudioEngine microphone transients; the installed public
  CMMotionManager API is unavailable on native macOS. Use 10 ms peak/RMS windows,
  ambient calibration, onset/crest/decay filtering, and live cooldown. Calibration
  profiles are tied to the default input UID and invalidated on route changes.
  Setup is detection-only and stops microphone capture when closed. Following
  user-observed double/triple splitting on the built-in microphone, use a 650 ms
  app grouping window and expose a live 300–1000 ms tap-spacing control. Longer
  windows accommodate slower patterns at the cost of later single-tap execution.

- 2026-09-09 (T05, user-requested pivot): Replace microphone detection with the
  built-in accelerometer. Core Motion is unavailable on native macOS, but this
  M5 Mac exposes an AppleSPUHIDDevice accelerometer (vendor page 0xff00, usage 3).
  Use public IOKit HID calls with an experimental, undocumented report format;
  this is not an Apple-supported motion API. Native app access and sample delivery
  succeeded without a new permission grant or privileged helper. Remove audio
  capture and the microphone usage description. Archive the old implementation
  under work/T05-microphone-archive for reversibility. Keep T05 in progress until
  physical taps, false triggers, recovery, and performance have been checked.
  Requesting 125 Hz still yielded approximately 800 Hz on this Mac; do not claim
  lower energy consumption without measurements. Never wake unrelated sensors or
  change global SPU power properties.

- 2026-09-09 (T05 performance/recovery): Native process samples showed substantial
  SwiftUI/layout work when the calibration display was active. Move the meter,
  calibration state, and metrics into separate small ObservableObjects; sensor
  updates must not invalidate the shared KnockEngine. Preserve full-rate filtering
  and 4 Hz display delivery. Inject the sensor connection and clock for recovery
  tests. On macOS willSleep, release MacBook input and clear recognition via the
  stopped/failed status path; restarting is explicit after wake.

- 2026-09-09 (T05 typing/trackpad suppression): The user reported typing being
  recognized as taps. A keystroke and a fingertip tap are physically the same
  impulse to a chassis accelerometer, so waveform filtering cannot separate them.
  Gate impulses on recent input activity instead: drop any impulse within 0.3 s of
  a keyboard or trackpad event, read from
  `CGEventSource.secondsSinceLastEventType(.hidSystemState, …)`. That API reports
  elapsed time only, never key identity, and needs no Input Monitoring or
  Accessibility grant, so the feature cannot become a keystroke log — this
  constraint is deliberate and must hold for any future change here. Never adopt a
  CGEventTap or global NSEvent monitor for this purpose. Two toggles, both default
  on, let the user opt out per input. Suppressed impulses are counted and displayed
  rather than dropped silently. Cursor movement counts as trackpad contact: it was
  excluded at first, but physical testing showed non-clicking trackpad contact still
  registering as taps, so `mouseMoved` is included and an external mouse pauses taps
  while it moves. Contact that generates no event at all cannot be suppressed by
  this approach. Because tap-to-click posts its click only after the fingertip has
  already struck the glass, a backward-looking check is not sufficient on its own:
  hold every impulse 0.15 s and re-check before treating it as a knock, accepting
  that delay on all knocks. Keep the hold uniform so pattern grouping is unaffected.

- 2026-09-10 (T05 movement false positives): Gently lifting the Mac registered as
  single knocks while lifting firmly did not. The filter checked that an impulse
  decays within 80 ms but never how fast it rose, so a firm lift was rejected as
  sustained displacement while a gentle lift's small brief transient matched a light
  tap. Amplitude cannot separate them. Require the level to come out of quiet within
  `AccelerometerSignal.riseWindow` (12 ms) before arming an onset: an impact rises in
  one to three samples at 793 Hz, while arm movement cannot ramp faster than tens of
  milliseconds. Keep the pre-existing detection tests as the guardrail — they use
  single-sample rises, so they fail if the gate is ever tightened too far. Also show
  a build timestamp in the setup screen, because several visually identical dev
  builds run at once and a stale window already produced one invalid measurement;
  revisit whether that belongs in a release build at T10.

- 2026-09-10 (T05 closed): All acceptance criteria are met except testing taps
  against speech and speaker music, which the user chose to skip. Closed with that
  recorded as an accepted exception rather than silently treated as passing. Also
  renamed the user-facing "Listening" wording to detection wording; it came from the
  superseded microphone implementation and had confused the user twice. The internal
  `isListening` API keeps its name, since "listening" for events is ordinary
  programming vocabulary and renaming it would churn roughly forty test lines for no
  user benefit.

- 2026-09-10 (T06 rescoped by the user): Replace the modifier-plus-click fallback
  with a three-finger double-tap that toggles detection, and interpret trackpad taps
  as Morse code where a decoded letter activates a running application starting with
  that letter. Two constraints follow. Morse must be a separate mode, because `···`
  is both Morse `S` and Triple Knock and the same input cannot mean both. And the
  three-finger gesture may not be reachable with public APIs at all — third-party
  tools use the private `MultitouchSupport` framework for arbitrary multi-finger
  taps. T05's undocumented *report format* behind public IOKit functions is not a
  precedent for linking a private framework; if the gesture needs one, stop and ask
  rather than assuming the earlier exception extends. Without long presses Morse
  reaches only E, I, S and H, which conveniently matches one to four taps.

- 2026-09-11 (T05 sensor rate, corrected): Request 1250 µs (800 Hz), one
  of the driver's advertised rates. The earlier 8000 µs (125 Hz) request was not
  advertised. The initial claim that this caused the outage was disproved: all
  advertised rates also produced zero reports. Do not attribute recovery to rate
  selection alone or infer per-process permission from a registry Allowed value.

- 2026-09-11 (T05 unresolved limitation, motion block): The accelerometer has not
  delivered a sample since the 2026-09-10 reboot, on an unchanged macOS 27.0. Measured,
  not guessed: permission is `Allowed`, every open succeeds, no rate works, three
  separate public code paths deliver nothing, and there is no output or feature report
  to enable the device. Meanwhile `als`, `las` and `cma` stream normally to the same
  probe, while `accel`, `gyro` and `devmotion6` are uniformly silent. The motion block
  is therefore gated by something outside Knock, which earlier sessions happened to
  benefit from. No public activation method has been found; the candidates are SPU
  power properties and `IOHIDEventSystemClient`, both already forbidden, and neither
  was attempted. MacBook mode must therefore be treated as opportunistic rather than
  dependable, and the app cannot distinguish a disabled motion block from unsupported
  hardware. This raises the priority of Trackpad mode from fallback to primary input,
  and means T05's measured results stand for their sessions but its feature cannot be
  promised. Do not resolve this by reaching for private API or power writes without an
  explicit decision from the user.

- 2026-09-11 (T05 recovery, user-approved backup condition): In response to the
  prepared activation experiment, the user allowed proceeding with experimental
  access provided the app was backed up first. App, full source, and preferences
  were archived and verified before any power writes. The separate signed diagnostic
  app changed only the uniquely matched accelerometer driver's reporting=1, power=1,
  and interval=1250 µs using public IOKit functions and undocumented properties.
  Baseline was zero reports; activation delivered 3,781 correctly sized reports in
  five seconds. This supersedes the earlier claim that in-app recovery was impossible.
  No private framework or unrelated sensor writes are needed for this repair.
  Add one activation attempt after a silent startup; require real decoded samples
  before reporting running. Restore exposed prior properties on teardown, but do not
  guess missing prior states or blindly power down shared hardware. Both power and
  reporting originals were unexposed in the experiment: a reboot may be needed to
  restore those states. Do not claim that pausing guarantees hardware power-off or
  that this saves energy. Keep new builds separate and preserve all older builds.

- 2026-09-15 (build compatibility): The installed SDK exports a State macro as
  well as the existing property wrapper. Its compiler plugin cannot start a nested
  sandbox in this environment. Use the ViewState typealias to public SwiftUI.State
  for the six existing view-state properties; retain their state/binding behavior
  and macOS 14 compatibility. This avoids changing any sandbox or tool settings.

- 2026-09-15 (single tap counted as triple): The user confirmed one physical
  tap increments the Triple counter by one. The previous filter rearmed on any
  individual sample below its quiet floor, so a decaying oscillation could count
  again every cooldown. A synthetic 40 Hz ring at 800 samples/sec reproduced three
  impulses from one impact. Require 30 ms of continuous quiet before rearming;
  preserve deliberate overlapping impacts through a renewed-strength check against
  a peak envelope (80 ms decay, 1.8x increase, within 500 ms of a prior tap).
  Both paths still require threshold, cooldown and decay confirmation. This is a
  waveform-based candidate fix, not a recording of the user's tap or a claimed
  physical pass. Keep sensitivity and cooldown preferences unchanged. Tests retain
  distinct doubles/triples even when the prior impact's long tail remains active.

## Open questions

- Final product name and bundle identifier.
- Direct download, Mac App Store, or both.
- Whether Apple Shortcut selection belongs in the MVP or the first follow-up release.
