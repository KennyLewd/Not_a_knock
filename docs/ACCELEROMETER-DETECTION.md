# Accelerometer detection — T05

## Signal and compatibility

MacBook mode now reads chassis acceleration, replacing microphone capture at the
user's request on September 9, 2026. No audio is captured, saved, or transmitted;
NSMicrophoneUsageDescription and the audio sources are removed from the target.

The public Core Motion CMMotionManager API is unavailable on native macOS in the
installed SDK. This does not mean the computer lacks an accelerometer. IOKit
inspection on the available M5 Mac found an AppleSPUHIDDevice with vendor usage
page 0xff00, usage 3 (accel). Native app access and continuous delivery succeeded.

Format evidence: [apple-silicon-accelerometer research](https://github.com/olvvier/apple-silicon-accelerometer),
particularly [its SPU implementation](https://github.com/olvvier/apple-silicon-accelerometer/blob/main/macimu/_spu.py).
The experimental format is a 22-byte report with signed little-endian Q16 axes at
offsets 6, 10, and 14, expressed in g. Knock independently implements these format
facts, with no third-party code dependency.

IOService enumeration and IOHIDDevice open/report/close are public IOKit functions.
The device identity and report format are undocumented Apple vendor details, not
an Apple-supported motion API. Future hardware or OS updates may change them.
Only the accelerometer is opened, nonexclusively. No root helper, private symbols,
all-driver activation, global SPU power writes, or security-setting changes are used.

## Processing and lifetime

- Reject incompatible report lengths and axes outside +/-16 g.
- Track gravity with a 200 ms low-pass baseline; subtract it and use vector magnitude.
- Warm up for 300 ms; require an above-threshold impulse to decay below 35% of its
  threshold within 80 ms. Require a quiet rearm and cooldown (default 120 ms).
- Sustained offsets and slow tilt are rejected by synthetic checks. Real repetitive
  vibration, typing, and speaker-induced vibration are not proven distinguishable
  from taps; manual measurements are necessary.
- Filter samples locally. No raw stream is retained. Update the display at 4 Hz only while Knock is active; continue recognizing taps
  at the full sensor rate while in the background.
- Three-second resting calibration uses 4x the 99th percentile, minimum 0.008 g.
  Reject a proposal above 0.4 g. Applying the suggestion is explicit. Sensitivity
  scales it by 0.5–2x. Sensor preferences are separate from old microphone profiles.
- A shared recognizer groups impulses with 75 ms debounce and 650 ms timeout;
  users can adjust spacing from 300–1000 ms. Longer spacing delays single actions.
- Stop, setup dismissal, mode changes, and delivery failure cancel the watchdog
  and release callbacks, buffer, and the sensor connection. The detector reports
  running only after an actual valid sample, not merely a successful open.
- Every two seconds, a watchdog detects at least 1.5 seconds without samples and
  stops with retry/fallback guidance. Generation checks reject old callbacks.

## Compatibility and recovery

Missing devices, failed open, incompatible reports, and stalled delivery produce
visible errors. Retry after reopening Knock. If macOS lists Knock under Input
Monitoring, access there may be relevant; this is not a guaranteed remedy for a
vendor sensor restriction. Trackpad mode is the fallback, with its full permission
implementation still scheduled for T06. Knock does not silently revert to audio.

The shell probe was denied with kIOReturnNotPermitted (0xe00002e2); the native app
succeeded on the same host. A denied sandbox probe therefore does not establish
that ordinary native app access is impossible. No new permission was granted in
this test. Existing system permissions were not audited or changed.

## Measured results — September 9, 2026

Host: MacBook Pro Mac17,2, M5, macOS 27.0, native ad-hoc-signed development build.

- Native open and delivery succeeded. Observed 793–794 samples/second during the
  first roughly 36 seconds of calibration. Live vibration values varied.
- A request for an 8,000 microsecond report interval (125 Hz) did not lower observed
  delivery. Treat it as a request, never as a verified hardware sampling rate.
- Three-second resting calibration proposed 0.0112 g; applying it updated the live
  threshold. Counts remained zero while measuring/waiting for application, as intended.
- Five single/double/triple physical trials requested from the user; result pending.
- A clean, controlled quiet interval and false-trigger trials remain pending. Early
  incidental counts have no labeled physical ground truth and are not accuracy results.
- 25 automated XCTest cases and 45 action-mapping/catalog round-trip checks pass.
  Accelerometer cases cover signed report decode, malformed data, 125/800 Hz pulse
  fixtures, gravity/noise/tilt, sustained offset, bounce/cooldown, thresholds,
  warmup/gaps/invalid samples, and persisted settings. These are synthetic fixtures.

## Performance and energy

The sensor delivers about 800 Hz on this host. Knock performs bounded scalar
filtering per report and updates the visible diagnostics at 4 Hz while the app is active. Background
meter publication is suppressed; recognition continues at the full report rate. Closing input
removes its callback connection; it does not force a shared system sensor off.
These design choices alone do not prove battery savings over microphone input.

Process inspection from the current shell was unavailable (sysmond service not
found). Activity Monitor was available through native UI. A paused debug reading showed
0.0% CPU and 0 idle wakeups. Debug calibration readings after sustained delivery
showed 31.9–34.1% CPU, including with its window hidden. The initial release build also showed about 33% CPU. Reducing UI publication
from 10 to 4 Hz brought foreground readings to 15.2–16.1%. The final release build
was verified as a separate process, and the older comparison process was stopped.
Later background/hidden-window spot readings remained 15.2–17.5%, despite the
isActive publication gate. An earlier background reading was 2.8–2.9%; that was
not sustained reliably. Further profiling is required; do not advertise low CPU
or treat the display change as a completed energy optimization. Activity Monitor
can retain old process rows until brought forward; verify PID and screenshot.
Native pause/restart and setup dismissal succeeded. The app is left paused. These spot readings include the whole app, not just filtering; they
are not battery measurements. A matched microphone comparison remains unmeasured. Use Activity Monitor or Instruments with matched duration, power mode,
UI visibility, and workload. Report foreground calibration and normal background
listening separately; UI cost can dominate a calibration-screen measurement.
Do not promise lower energy consumption until that comparison is available.

## Sensor rate regression — September 11, 2026

After a reboot the accelerometer opened successfully and delivered no samples, so the
watchdog reported that the Mac "may require an unsupported sensor activation method".
That message was wrong and cost real debugging time: a missing Input Monitoring grant
and an idle sensor produce identical silence, and the message asserted the worse of
the two. It now names both possibilities and puts the permission check first.

Diagnosis came from the I/O Registry rather than from the app:

```
ioreg -r -c AppleSPUHIDDevice -l
```

- `"HIDRMDeviceState" = "Allowed"` — access was permitted all along, which ruled out
  TCC immediately. Treat this key as the authority instead of guessing from silence.
- `"sensor_rates" = "50 100 200 400 800 "` on AppleSPUHIDDriver — the only rates the
  driver supports.
- `"ReportInterval" = 8000` — what Knock requested, 125 Hz, not on that list.
- `"MaxInputReportSize" = 22` — confirms the 22-byte report layout is unchanged.

The request was changed to 1250 µs (800 Hz), but this did **not** restore delivery.
The original causal explanation here was premature and is superseded by the
measurements below. Registry Allowed describes the service; it does not guarantee
that each process can open it. The diagnostic CLI later received NotPermitted while
its separate signed app could open the same service.

## Motion block not enabled after reboot — September 11, 2026, UNRESOLVED

This is the most important limitation found so far and it undermines the premise of
MacBook mode. After the 2026-09-10 13:15 reboot the accelerometer stopped delivering
samples and has not recovered. macOS is unchanged at 27.0 build 26A5425a, so this is
not an OS update.

What was ruled out, each by direct measurement rather than inference:

- **Permission.** `HIDRMDeviceState` reads `Allowed`, every open returns
  `kIOReturnSuccess`, and other SPU sensors deliver reports to the same unprivileged
  probe process. Input Monitoring is not the problem, despite being the first thing
  the app's error message suggests.
- **Sample rate.** Zero reports at all five advertised rates — 50, 100, 200, 400 and
  800 Hz — over both 2 s and 12 s windows. The 125 Hz bug documented above was real
  but was never the cause of this.
- **Code path.** `IOHIDDeviceOpen`, `IOHIDManagerOpen`, and an open with
  `kIOHIDOptionsTypeSeizeDevice` all succeed and all deliver nothing.
- **Wrong device.** Exactly one device matches usage page 0xff00 with usage 3, so the
  first-match loop cannot be picking a decoy.
- **Enable via reports.** The device advertises `MaxOutputReportSize` 0 and
  `MaxFeatureReportSize` 0, so there is no output or feature report to turn it on.
- **A dead SPU.** Other sensors on the same bus are alive: `als` delivered 6 reports,
  `las` 1, `cma` 2, in the same 1.2 s window each.

What is actually wrong: the motion sensors as a group are not enabled. `accel`,
`gyro` and `devmotion6` are all silent while the non-motion sensors stream. That
points at a shared gate for the motion block which something outside Knock used to
hold open — note the sibling device literally named `wakehint`, and that
`DeviceOpenedByEventSystem` reads `No` on the accelerometer.

No public way to enable that block has been found. The two known candidates are both
off-limits under current constraints, and neither was attempted:

- Writing SPU power or enable properties, which PROJECT.md forbids precisely because
  the block is shared with sensors Knock has no business touching.
- `IOHIDEventSystemClient`, which is private API and forbidden. Note this is a
  categorically bigger step than reading an undocumented report *format* through
  public functions, which is the exception T05 already took.

Consequence to state plainly: MacBook mode works only when something else has the
motion block enabled, and Knock cannot tell the difference between that and
unsupported hardware. Every T05 result above remains valid for the sessions it was
measured in, but the feature is not dependably available across boots. This is the
risk PROJECT.md flagged from the start — validate per hardware and OS — now realized,
and it applies to activation, not just the report format.

## The September 11 "motion block" conclusion was wrong — September 17, 2026

**The accelerometer was never dead.** The section above concludes that the motion
block is gated outside Knock and that MacBook mode is undependable across boots.
That conclusion rests on a probe process reading zero reports, and the probe was the
problem: a second unprivileged `IOHIDDevice` client opened on `accel` succeeds and
then receives nothing while another client is streaming. Silence in a side process
is not evidence about the sensor.

Measured on September 17: a standalone probe reported `accel`, `gyro` and
`devmotion6` at 0 reports in a 5 s window while `als`, `las` and `cma` streamed —
the exact September 11 signature — and Knock was simultaneously detecting taps from
the same device. The user resolved it in one sentence by reporting that physical
mode counted singles.

Rules that follow, for anyone diagnosing this again:

- **Never conclude the sensor is dead from a second process.** The authority is what
  Knock itself reports: a live sample rate in Calibrate & test, or the orange
  "opened but isn't delivering samples" warning. Ask the user what the app shows.
- The `DeviceOpenedByEventSystem = No` and `ReportInterval = 8000` registry readings
  are not evidence of a gate either; they read the same when the sensor is working.
- The LockDown Browser correlation (installed, three sessions on September 10 at
  13:26/13:36/13:38, bracketing the last known-good reading) explains nothing and
  should be dropped. macOS retains no log from that window, so it cannot be tested.

No source change was needed for any of this. The September 11 section is retained
for its measurements, but its conclusion must not be acted on.

## Sensitivity cliff, and the tap-feel repair — September 17, 2026

The user reported light taps ignored and doubles/triples counting as singles at
sensitivity 0.80, having raised the slider precisely because detection felt weak.
Raising it was the cause, not the remedy.

The quiet floor was `threshold * 0.35`, and the threshold falls as sensitivity
rises, so the floor fell with it. Their saved state was base threshold 0.0655 —
which implies a calibration-measured resting noise p99 of 0.0164 g, about 4x the
0.0039 g of September 10. Simulated against that noise, with three impacts 220 ms
apart:

```
sensitivity  effective   quiet floor   vs noise p99   taps detected (of 3)
   0.50        0.0655      0.0229      above                 3
   0.65        0.0532      0.0186      above                 3
   0.80        0.0430      0.0150      BELOW                 0
   1.00        0.0328      0.0115      BELOW                 0
```

Past ~0.65 the floor sinks under the desk's own vibration, the level never reads as
quiet, impacts never complete, and taps are dropped in silence. The user confirmed on
hardware that dropping to 0.50 restored detection. **This is exactly the fragility
recorded in the September 10 rise-gate section** — quiet floor at ~1.4x measured
noise, symptom "taps that feel ignored". It was predicted, then not recognised when
it happened. Sensitivity must stay monotonic; a control that disables the feature at
one end is a defect regardless of the reading behind it.

Two repairs, both in `AccelerometerSignal`:

- `quietFloor = min(max(threshold * 0.35, noiseFloor * 1.5), threshold * 0.8)`. The
  floor now tracks measured noise, not the slider. `noiseFloor` is recovered as
  `baseThreshold / 4`, since calibration proposes p99 * 4 — no new stored state, and
  it survives the `dt > 0.5` stream-gap reset, which would otherwise discard it.
- Renewed-impact gate from `1.8x` an 0.08 s envelope to `1.20x` a 0.12 s envelope.
  The envelope is a peak tracker, so a decaying vibration can never exceed it and
  only a real new impact can; the margin only has to clear sample-to-sample decay,
  not the ringing. At 1.8x a second tap had to be nearly as hard as the first, which
  is what cost the fast light doubles and triples.

Measured over 34 tap gaps from 0.13–0.30 s on a two-mode synthetic ring (a single
pure tone cancels against its own tail near half-cycle gaps and is not
representative):

| ring decay | taps | before | after |
|---|---|---|---|
| 0.035 s | even / light | 0 / 0 | 0 / 0 |
| 0.08 s | even | 5 missed | 0 |
| 0.08 s | light 2nd/3rd | 8 missed | 1 |
| 0.16 s | even | 4 missed | 1 |
| 0.16 s | light 2nd/3rd | 14 missed | 9 |

A single impact is still counted once at every decay rate tested, so the September 15
overcount repair is intact. 57 tests pass.

**Not solved.** A deliberately light second and third tap on a long-ringing (0.16 s)
chassis still misses roughly a quarter of gaps: the new impact can land out of phase
with the tail and partially cancel. This is in the signal, not in a constant, and
`testLightTapsOnALongRingAreMostlyCounted` pins it at its current level so it cannot
regress quietly. The real fix is onset detection on a smoothed envelope rather than
the raw level — a deliberate rewrite, not a tuning pass.

Still open: the user's stored base threshold of 0.0655 is stale and now feeds the
noise floor as well. Recalibrating on a still desk should return it near 0.015 and
will help light taps more than any slider position can.

## Repeatable manual protocol

1. Open Calibrate & test, start the accelerometer, keep the Mac on a stable desk,
   measure resting vibration for 3 seconds, then apply the suggestion.
2. Reset counts. Perform 5 singles, 5 doubles, and 5 triples on the palm rest. Leave
   1.5 seconds between patterns. Record all three counts and the impulse total.
3. Repeat separately for desk taps with the laptop resting on that same desk.
   Record desk material, laptop support/padding, and whether vibration reaches it.
4. Reset before each 30-second interval: hands-off quiet, typing, speech near the
   Mac, speaker music, and moving/repositioning the Mac. Record false patterns.
   For the typing and trackpad intervals also record the ignored counts; a rising
   ignored count with flat pattern counts is the suppression working, whereas flat
   ignored counts with false patterns means the settle window is too short.
5. If doubles/triples split, increase tap spacing. If individual taps bounce,
   increase cooldown; if light taps are missed, increase sensitivity. Re-run the
   complete labeled trial after changing controls.
6. Pause and restart; verify sample counts stop then resume. Close setup and confirm
   listening is paused. Reopen to check saved calibration. Exercise sleep/wake and
   delivery failure recovery; do not infer it from a normal start/stop trial.
7. Record matched CPU/energy measurements and real results before completing T05.


## September 9 continuation — isolated display updates and recovery

Native Activity Monitor profiles saved in work/Knock-profile-before.txt and
work/Knock-profile-foreground-before.txt showed a mostly waiting main thread when
inactive and much more SwiftUI layout/accessibility work with live calibration.
The shared KnockEngine previously published every meter and snapshot update,
invalidating the root view, dashboard, and menu bar even when their data had not
changed. These profiles describe this app run, not universal macOS behavior.

The meter, calibration state, and displayed metrics now have separate readout
objects and small observing views. Equal values do not republish. Metrics compare
the displayed integer seconds/rate rather than every underlying sample. Full
sensor samples still reach the signal filter; the app-level diagnostic snapshot
remains available without broadcasting it through the shared engine. The Swift
Observation macro was unavailable in this build sandbox, so this uses ordinary
Combine ObservableObjects with no macro dependency or permission expansion.

Native release comparison on the same M5 Mac: new PID 21742, source at
/private/tmp/Knock-T05-isolated. Continuous input remained ~793 Hz; observed CPU
readings were 5.3%, 6.9%, and later 5.3%, compared with earlier 15–18% calibration
readings. They are spot readings under real desktop activity, not a controlled
battery benchmark. Activity Monitor confirmed the previous PID 19472 terminated.
No reduction in physical sensor report frequency was claimed.

## September 9 continuation — typing and trackpad suppression

The user reported that typing registers as taps during normal use. A keystroke and
a fingertip tap are the same event to a chassis accelerometer: a brief, high-onset
impact with fast decay. They are not separable by waveform, threshold, or decay
shape, so no amount of filter tuning fixes this. The keyboard and trackpad are
mechanically part of the same chassis the sensor is bolted to.

Knock therefore uses a non-acoustic side channel: it asks the window server how
long ago the user last pressed a key or pressed the trackpad, and drops any impulse
that lands within a settle window of that input.

- `Knock/Services/InputActivityMonitor.swift` wraps
  `CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType:)`.
- This returns elapsed time only. It never exposes which key was pressed, so the
  feature cannot become a keystroke log. It required no Input Monitoring or
  Accessibility grant and produced no TCC prompt; verified on macOS 27 by an
  unprivileged binary reading plausible, advancing values for keyDown, keyUp,
  flagsChanged, leftMouseDown, scrollWheel, and mouseMoved.
- `.hidSystemState` counts physical hardware input only, so key events that Knock's
  own actions post do not read back as the user typing.
- Keyboard group: keyDown, keyUp, flagsChanged. Modifier presses shake the chassis
  too, and key release is its own impact.
- Pointer group: left/right/other mouse down and up, left/right drag, scrollWheel,
  and `mouseMoved`. `mouseMoved` was excluded in the first version on the theory
  that a gliding fingertip barely disturbs the chassis; the user's physical test on
  September 9 disproved that — pattern counts rose during trackpad use while the
  ignored counter also rose, meaning clicks were being suppressed correctly and the
  leaks came from contact that produces no click. Including `mouseMoved` costs
  external-mouse users a 0.3 s tap pause while the mouse moves, even though a mouse
  cannot shake the chassis; the toggle exists for exactly that case.
- Tap-to-click required a second mechanism. A backward-looking check cannot see an
  event that has not been posted yet, and with tap-to-click enabled the fingertip
  strikes the glass *before* the trackpad driver recognizes the gesture and posts
  the click. The user observed exactly this asymmetry on September 9: physical
  trackpad presses were suppressed correctly while tap-to-click taps were not.
  Every impulse is therefore held for `inputVetoWindow` (0.15 s) and re-checked
  before it counts as a knock, so a late click can still cancel it. Held impulses
  are cancelled on stop, so none can arrive after the sensor is released.
  Cost: every knock is delayed 0.15 s. The hold is uniform, so relative impulse
  spacing is unchanged and pattern grouping, debounce, and the sequence timeout are
  unaffected. Single-tap actions already wait out the pattern window, so this adds
  to an existing wait rather than introducing a new one. If tap-to-click still
  leaks, this window is the knob to raise; if knocks feel sluggish, lower it.
- Settle window: `AccelerometerKnockDetector.inputSettleWindow`, 0.3 s. It does not
  need to bridge the gap between keystrokes, because each keystroke's own impulse
  is suppressed by its own event; it only has to cover detection lag. Tap
  confirmation trails the physical impact by up to 80 ms, and a heavy press can
  ring into a second impulse one cooldown later, so 0.3 s covers both with margin.
  The cost is that a deliberate tap within 0.3 s of typing is ignored.
- The query runs once per detected impulse, never per sample, so it adds nothing to
  the ~793 Hz sample path.
- Two independent user toggles, both default on, persisted as
  `knock.ignoreWhileTyping` and `knock.ignoreWhileUsingTrackpad`. Turning both off
  restores the previous behavior.
- Suppressed impulses are counted separately as `ignoredTyping` / `ignoredPointer`
  and shown in the setup metrics line, so the filter is observable rather than a
  silent drop. `impulses` now counts only impulses that reached recognition.
- Applies to MacBook (accelerometer) mode. It is unrelated to T06 Trackpad mode,
  which uses trackpad clicks as deliberate input.

Known limitation: an event-timing side channel can only suppress contact that
generates an event. A finger that lands on the trackpad and stays completely still
produces no event at all, so its impact cannot be attributed to pointer input and
will still register as a tap. This is inherent to the approach, not a tuning issue.

Known limitation: suppression is per impulse. If a keystroke coincides with one tap
of a deliberate multi-tap pattern, that tap is dropped and the pattern can register
as a lower count rather than being discarded. Firing a smaller pattern is possible;
the alternative — voiding any in-flight sequence — was not implemented because it
would move grouping knowledge into the detector, which owns raw impulses only.

`InputSuppressionTests` covers a tap during typing, a tap during trackpad contact,
the settle boundary, each toggle off independently, metric reset, and preference
defaults/persistence. The tests use a fake activity monitor, so they verify the gate
but not which CGEventTypes populate each group — that list is only verifiable
physically, which is how the `mouseMoved` omission slipped through.

Physical results, September 9, user reports:

- Knock-T05-typing: typing no longer produces taps, confirmed against the rising
  ignored-while-typing counter.
- Knock-T05-typing: trackpad use still produced pattern counts alongside a rising
  ignored counter. Prompted adding `mouseMoved`.
- Knock-T05-pointer: physical trackpad presses were correctly suppressed, but the
  user has tap-to-click enabled and those taps still registered as knocks. Prompted
  the held-impulse veto. The user's trackpad settings matter to this result and
  should be recorded with any future trackpad trial.
- Knock-T05-veto: the user reports deliberate taps working and no detection from
  trackpad touch, trackpad clicks, or keyboard typing. Suppression is therefore
  confirmed against all three real-world false-trigger sources that were reported.
  The 0.15 s hold was not reported as perceptible, so it stays at 0.15 s.

This is a user report from normal use, not a counted trial: it establishes that
false triggers stopped, not a false-positive rate. No interval counts were recorded.

Confound to keep in mind: the user recalibrated between trials, raising the saved
base threshold from 0.02643 g to 0.03955 g — effective 0.0214 g to 0.0320 g at
sensitivity 0.6533, roughly 50% less sensitive. A higher threshold suppresses false
triggers on its own, so the improvement in trackpad behavior cannot be attributed
entirely to input suppression. Typing suppression is separately evidenced by the
ignored-while-typing counter rising, which threshold changes cannot explain.

### Labeled 5/5/5 trial — September 9, Knock-T05-veto (authoritative)

Single Knock instance verified running (PID 24240) so no other build could be
confused for it. Settings: sensitivity 0.6533, base threshold 0.03830 g, effective
0.0310 g, pattern window 0.75 s, cooldown 0.12 s, 793 samples/s, 32 s of input.

Intended 5 single / 5 double / 5 triple. Recorded: **Single 5, Double 5, Triple 5**,
30 impulses, 0 ignored while typing, 3 ignored while using the trackpad.

- 15/15 patterns correct, and 30 impulses for exactly 30 intended taps. No extra, no
  missing, no splitting.
- The 0.15 s held-impulse veto does not disturb grouping in physical use. This was
  the open risk of the veto — the hold is uniform in theory, and doubles and triples
  grouping correctly confirms it in practice.
- The 3 trackpad-ignored impulses happened during the run, from touching the
  trackpad to operate the app. Suppression therefore rejected real trackpad contact
  in the same session in which it passed all 15 deliberate patterns, which is
  stronger evidence than either test alone: the filter is not simply muting
  everything.
- The spurious extra single from the earlier trial did not recur, so it was a stray
  contact rather than an impact rebound. No cooldown change is needed.

### Desk taps — September 9, Knock-T05-veto

Same settings, effective threshold 0.0310 g, 793 samples/s, 34 s of input. Fresh
run: patterns are exactly 5/5/5, which could not happen on a continued session.
Tapping the desk rather than the chassis, intended 5 single / 5 double / 5 triple.

Recorded: **Single 5, Double 5, Triple 5**, 34 impulses, 0 ignored while typing,
1 ignored while using the trackpad.

- All 15 desk-tap patterns recognized at the correct count. Desk coupling works on
  this surface without changing sensitivity, which is not guaranteed in general —
  the criterion is that vibration physically reaches the laptop.
- 34 impulses against 30 intended taps: 4 extra, absorbed without creating false
  patterns. Consistent with desk taps producing a less clean single impact than
  chassis taps — a struck desk rings, and extra impulses inside an already-capped
  sequence are discarded by T04's three-tap cap.
- Surface: a standard office desk with a plastic/laminate top, user-described. The
  result is specific to that surface. A compliant or decoupled top — thick rubber
  mat, felt pad, glass on standoffs, or a laptop on a stand — transmits far less,
  and desk-tap support must not be presented as universal.
- Run order was laptop movement first, then this desk trial.

### Laptop movement — September 9, Knock-T05-veto, clean re-run: FALSE POSITIVES

Reset, then laptop handling only, no tapping. Effective threshold 0.0310 g, 793
samples/s, 20 s of input. Recorded: **Single 2, Double 0, Triple 0**, 2 impulses,
0 ignored while typing, 2 ignored while using the trackpad.

Handling the laptop therefore does produce false single knocks — roughly one per
10 s of gentle handling. This fails T05's requirement to filter gravity and slow
movement, and supersedes the ambiguous earlier reading.

The user's key observation: **lifting firmly does not trigger, lifting gently does.**
That inversion identifies the mechanism precisely. `AccelerometerSignal` confirms a
tap when level crosses `threshold` and then falls below `threshold * 0.35` within
80 ms; it never checks how *fast* the level rose.

- A firm lift produces a large acceleration that stays above the floor for well over
  80 ms, so the onset expires and the impulse is correctly rejected as sustained
  displacement — the behavior `testSustainedDisplacementDoesNotBecomeTapOnRelease`
  covers.
- A gentle lift produces a small, brief transient: it barely crosses the threshold
  and settles back inside 80 ms once the arm reaches constant velocity. To this
  filter that is identical to a light fingertip tap. Amplitude does not save it,
  because amplitude only matters for crossing the threshold at all.
- The 200 ms gravity tracker makes it worse rather than better: it follows roughly a
  third of a deviation within 80 ms, which helps pull a gentle transient back under
  the 35% floor and satisfy the confirmation rule.

The discriminator the filter is missing is **rise time**. A fingertip impact excites
the chassis at high frequency and jumps from quiet to peak in one to a few samples,
about 1–4 ms at 793 Hz. Human arm dynamics cannot ramp a lift faster than roughly
10–30 ms, which is 8–24 samples — close to an order of magnitude of margin.

Fix implemented as `AccelerometerSignal.riseWindow`, 0.012 s. The filter records the
last time level sat below `threshold * 0.35` and arms an onset only if that quiet
moment was within the rise window. A tap comes straight out of quiet; a gentle lift
spends far longer ramping through the band between the floor and the threshold.

Why 12 ms: at the observed 793 Hz a real impact's quiet-to-threshold gap is one to
three samples, 1.3–4 ms, so 12 ms leaves roughly 9 samples of headroom. It also
still admits a tap captured at 125 Hz, where one sample step is 8 ms — relevant only
if slower-delivering hardware appears, since this Mac ignored the 125 Hz request.
Tightening much below 10 ms would start to risk single-sample-rate hardware.

Every pre-existing detection test passes unchanged — single/double/triple at both
sample rates, cooldown rejection, sensitivity, resting noise and slow tilt, and
sustained displacement — which is the guardrail against over-tightening. The new
test isolates rise time from amplitude: the same 0.05 g peak delivered as a 60 ms
ramp is rejected while delivered as an impact it is accepted. Amplitude alone was
never the discriminator, so a test that varied amplitude would have proved nothing.

### Rise-gate re-validation — September 10, Knock-T05-rise

Build stamp confirmed as Sep 10 2026 11:09:47, so the build identity is no longer in
question. The user recalibrated first: base threshold 0.01554 g, sensitivity 0.6514,
effective **0.0126 g** — roughly 2.5x more sensitive than the 0.0310 g baseline of
the earlier clean trials. Results are therefore not directly comparable to those.

Chassis protocol, 40 s: **Single 6, Double 5, Triple 5**, 31 impulses, 1 ignored
while typing, 5 ignored while using the trackpad.

- **No taps were missed.** All 15 intended patterns registered, and doubles and
  triples grouped at the correct counts. This is the regression question the rise
  gate had to answer, and it answered it at 2.5x the sensitivity of the baseline —
  a harder test than the one originally proposed.
- One spurious single and one extra impulse. At 2.5x sensitivity that is expected
  and cannot be attributed to the rise gate, which only ever rejects impulses.
  A gate cannot manufacture one.

Movement re-test: the user reports gentle lifting no longer registers, and that no
taps felt missed. The rise gate therefore fixes the defect it targeted without
introducing its inverse, and does so at 2.5x the sensitivity at which the defect was
originally found. Recorded as a user report — no counter screenshot was captured for
the lift interval specifically, unlike the chassis run above.

Fragility worth tracking, found while reasoning about this threshold. The gate's
quiet floor is `threshold * 0.35`, and calibration proposes a threshold of about
4x the 99th-percentile resting noise. The floor therefore lands around 1.4x that
noise level — a thin margin. At the current 0.0126 g the floor is 0.0044 g against a
measured noise p99 near 0.0039 g. If ambient vibration rises after calibration, or a
user applies a very low threshold on a noisy surface, `lastQuiet` stops updating and
taps are silently rejected rather than falsely detected. Symptom would be taps that
feel ignored, so ask about missed taps whenever the threshold is low. Consider
deriving the floor from measured noise rather than from the threshold if this
appears in practice.

### Laptop movement — earlier ambiguous reading, superseded

Reading taken during pick-up and tilt: 59 s of input, 31 impulses, patterns still
5/5/5, 1 ignored while typing, 5 ignored while using the trackpad, and the dashboard
showing "Last recognized: Single knock".

The user states they pressed Reset before moving, moved before the desk trial, and
did not use the dashboard test buttons. Taken literally, that means laptop handling
alone produced 31 impulses and 15 false patterns, which would be a serious defect.
The evidence does not support that reading:

- The counts are *exactly* 5 single / 5 double / 5 triple, matching the tap protocol.
  Random handling producing precisely that distribution is vanishingly unlikely;
  chassis rattle would skew heavily toward one pattern.
- Every counter increased monotonically from the preceding accuracy run — 32→59 s,
  30→31 impulses, 3→5 trackpad-ignored, 0→1 typing-ignored — which is exactly the
  signature of a session that was never reset.
- 31 impulses is 30 tap impulses plus one, and 5/5/5 accounts for exactly 30.

So the likely truth is a continuation in which handling added a single impulse and no
false pattern. That is a good result, but it rests on contradicting the user's own
recollection, so it is NOT recorded. Resolve it with a clean re-run: reset, then only
handle the laptop, no tapping at all, and read the counters. Both outcomes matter —
15 false patterns from movement would block T05.

Superseded earlier trial, kept for context: an identical protocol run on
Knock-T05-typing recorded Single 6, Double 5, Triple 5 with 32 impulses. The user
had photographed an older window — the builds are visually near-identical, which is
what made the misidentification possible. All doubles and triples were correct
there too; the two extra impulses were one spurious single plus one absorbed by
T04's three-tap cap.

Assigned actions, September 10, Knock-T05-rise: confirmed firing. Double knock ran
the screenshot action and triple knock ran the shockwave reaction, the first time any
assigned action has executed from a real tap. Detection therefore reaches
ActionRunner correctly.

Cause of the initial failure was a stale Accessibility grant: the grant had been
given to the Knock-T05-typing binary, and ad-hoc signed builds are identified by path
and code hash, so it did not carry to Knock-T05-rise. Re-adding the current bundle
fixed it immediately. Expect this on **every** rebuild until the project adopts a
stable signing identity. Because ActionRunner reports nothing when a post fails, the
symptom is total silence, which is indistinguishable from a detection failure — the
useful discriminator is the shockwave reaction, which is drawn in-app and needs no
permission at all.

Sleep/wake, September 10, Knock-T05-rise: confirmed working. The user slept the Mac
and detection stopped, matching the `willSleep` path that closes the input and
reports the paused status. This is a real sleep cycle, not a pause/resume trial.
Whether taps stay inert until an explicit restart was not separately confirmed
beyond detection having stopped.

Not tested, by the user's explicit decision on 2026-09-10: hands-off quiet, speech
near the Mac, and speaker music. T05's criteria call for testing taps separately
from speech and speaker vibration, so this is an accepted gap, not a pass. Residual
risk is concentrated in speaker music, the one sustained-vibration source never
exercised — sustained vibration is what the 80 ms decay rule and the 12 ms rise gate
are both meant to reject, so it is the least likely to leak and the least evidenced.
Quiet and speech are lower risk still: speech couples into a chassis poorly. If a
user ever reports phantom knocks while music plays, start here.

Recovery now has an injectable input connection/clock and explicit, idempotent
native close. A willSleep notification closes the sensor, clears recognition
through stopped/failed status, and asks the user to restart after wake. Tests
exercise open denial, no delivery, interrupted delivery, restart, late callbacks,
sleep notification, deferred callback failure teardown, and explicit calibration
application. The tests inject notifications/fake input; a physical sleep/wake
trial on the user's Mac remains a distinct manual check.

There are now 32 passing XCTest cases plus 45 action-mapping/catalog checks.
Regression checks also show 1,000 changing meter values cause zero shared-engine
notifications and unchanged readouts do not notify other panels.

The user was prompted for five of each physical pattern. During their current
run, the screen showed Single 7 / Double 7 / Triple 6, 46 impulses in 63 seconds,
793 Hz, effective threshold 0.0382 g; the intended pattern sequence has not yet
been confirmed, so these counts are not a labeled accuracy result. Sensitivity
was user-adjusted to ~65.33%, cooldown 120 ms, spacing 750 ms. Preserve them.


Final verification of this continuation: Release build at
/private/tmp/Knock-T05-verified/Build/Products/Release/Knock.app, PID 22115, passed
strict signature verification. Native start delivered 794 Hz, then settled at
793 Hz. Resting measurement proposed 0.0149 g; it was deliberately not applied,
preserving the user's 0.0382 g effective threshold. Pause discarded the proposal
and showed 0 samples/s; restart delivered 792 Hz and retained tuning. Done returned
to the paused dashboard. Final Activity Monitor CPU spot reading was 4.6%. These
observations supplement the 5.3–6.9% readings above and do not establish battery
savings or real sleep/wake accuracy. The user closed their test screen; their
confirmation of intended taps and misreads is still pending.

## Backed-up activation experiment — September 11, 2026

The user authorized the prepared experiment subject to backing up the app. Verified
archives of the original app and complete source, plus an exported preferences file,
are in `../al/knock-recovery/backup-20260911-145722` (relative to the project root).
Checksums and archive-integrity results are in its manifest.json.

CLI access returned `0xe00002e2` (NotPermitted), before any writes. A separate signed
native diagnostic, PID 2357, opened successfully without a new grant. It measured
zero reports over two seconds, then set SensorPropertyReportingState=1,
SensorPropertyPowerState=1 and ReportInterval=1250 on exactly the accel driver
(page 0xff00, usage 3). All writes succeeded; 3,781 reports of the expected 22-byte
size arrived over five seconds, with no invalid reports. No private API was used.

ReportInterval was restored to its observed zero. The other two original properties
were unexposed and could not be safely restored. Driver selection limits write scope,
but does not prove the physical motion block is unshared. Power-off on pause and
battery savings remain unverified; a reboot may be needed to reset the sensor.

The main app repair attempts this activation once only when startup delivers no
samples, waits again for actual decoded readings, and fails cleanly on write errors
or continued silence. Stop and sleep release the HID connection, cancel the recovery
watchdog, and restore exposed prior properties. The activation is experimental and
hardware/OS-specific. Fresh-boot and physical-tap verification remain separate checks.

## Clean test boundaries — September 15, 2026

Regression tests reproduced old taps appearing after Reset counts: impacts awaiting
quiet/decay confirmation and taps held for the 150 ms input veto both survived the
counter reset. Beginning calibration could likewise deliver held pre-calibration taps.
The reset path now clears both stages, rejects cancelled-but-queued callbacks, and
zeros the displayed sampling average. Gravity tracking and threshold/cooldown settings
are preserved, and the device stays open; the filter waits for quiet before rearming.
Calibration entry/exit use the same pending-input cancellation.

50 XCTest cases and 45 assignment round-trips pass. Full Release build and signature
verification pass; automatic app launch failed and no GUI tool is available this
session. Therefore no fresh physical or reboot result is claimed. Earlier 795 Hz
observations remain September 11 measurements only.

## One physical tap counted as Triple — September 15, 2026

User report: one physical tap increases Triple by one. This supersedes the pending
question about basic accuracy: the repaired sensor streams, but recognition fails.
It is a within-pattern overcount, rather than three separate single counts. No raw
waveform from the user's Mac was recorded, so the mechanical cause remains inferred.

The previous signal filter sets armed=true whenever a single sample falls below
35% of threshold. A decaying oscillation repeatedly crosses that floor. With the
saved 120 ms cooldown, the same physical vibration can be accepted multiple times.
A synthetic 0.12 g, 40 Hz oscillation with 160 ms amplitude decay at 800 samples/sec
produced detections at 0.50625, 0.63125 and 0.74375 seconds: one impact becomes Triple.
25 Hz produced four accepted impulses; the recognizer caps that at Triple too.

Fix: require 30 ms of continuous below-floor input before another ordinary onset.
A quiet-only rule also rejected deliberate new impacts over a long residual tail;
a second regression test exposed that before delivery. Track a fast-attack envelope
with 80 ms decay, allowing a fresh peak at least 1.8x the preceding envelope within
500 ms of the prior tap. This path requires a meaningful residual envelope (at least
the quiet floor), and retains the absolute threshold, cooldown and 80 ms decay
confirmation. It permits a clear new impact without treating every zero crossing as
rest. Gravity tracking, input suppression, reset cancellation and sensor activation
remain unchanged. User settings are not migrated or silently adjusted.

54 XCTest cases and 45 assignment round-trips pass, including full detector-to-engine
Single counting with no Double/Triple or actions, one ringing impact at 795/800 Hz,
and separate short/long ringing doubles/triples 220 ms apart. The original tests for
movement, noise, cooldown and reset still pass. These are synthetic fixtures, not a
hardware accuracy result. An initial 125 Hz long-ring fixture missed short zero
crossings in the pre-existing decay rule; that low-rate omission is recorded rather
than claimed fixed. Other 125 Hz fixtures still pass. The observed Mac runs ~795 Hz.

Remaining: test the new build physically, starting with five single taps 1.5 s apart,
then deliberate doubles/triples. Especially check lighter second/third taps during
strong residual vibration: the renewed-strength rule may reject weak impacts that
are indistinguishable from the existing tail. If the issue persists, capture bounded
sensor diagnostics in a detection-only test rather than blindly increasing cooldown.
Fresh-boot and power-restoration limitations remain as previously documented.
