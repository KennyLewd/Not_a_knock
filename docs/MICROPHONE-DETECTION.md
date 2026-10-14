> Historical: superseded by the user-requested accelerometer pivot on September 9, 2026.
> No microphone capture remains in the active app. See ACCELEROMETER-DETECTION.md.

# MacBook microphone detection

## Signal and API choice

This app uses the system default microphone through AVAudioEngine's input tap,
not a motion sensor. On the installed macOS 26.5 SDK, the public CMMotionManager
class is annotated `API_UNAVAILABLE(macos)` in CoreMotion/CMMotionManager.h,
lines 85–86. No private accelerometer/HID sensor interface is used.

Primary references:
- [Apple: CMMotionManager](https://developer.apple.com/documentation/coremotion/cmmotionmanager)
- [Apple: AVAudioEngine.inputNode](https://developer.apple.com/documentation/avfaudio/avaudioengine/inputnode)
- [Apple: requesting microphone access](https://developer.apple.com/documentation/avfoundation/avcapturedevice/requestaccess(for:completionhandler:))
- [Apple: audio engine configuration changes](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange)

Use the built-in microphone for palm-rest taps. An external microphone may mainly
hear airborne sounds; its placement changes the result. This is a heuristic for
short impact sounds, not proof that a sound came from the chassis. Keyboard clicks,
claps, and other sharp sounds can still trigger it.

## Processing

- Reduce the first input channel into fixed 10 ms peak/RMS summaries on the audio
  callback, including when a window spans callbacks. No recording, transcript,
  raw audio file, or network transmission is created.
- Warm up for 200 ms. Track an adaptive noise floor.
- Candidate peak must exceed the calibrated/sensitivity-adjusted threshold and
  six times the ambient RMS estimate, rise to 2.5 times the previous peak, and
  have a peak/RMS crest factor of at least 2.2.
- Confirm only if the peak falls below 35% of the onset peak within 60 ms.
  Reject clipped samples and sustained candidates. Cooldown applies to accepted
  onset timestamps and defaults to 120 ms (live range 80–400 ms).
- Send confirmed raw impulses to the existing shared sequence recognizer. Its
  75 ms debounce and maximum count of three still apply. The app now defaults to
  a 650 ms grouping timeout, adjustable live from 300–1000 ms in setup. The reusable
  recognizer's standalone default remains 460 ms; the app explicitly supplies 650 ms.

Steady tones and broad speech/music envelopes are less likely to pass this filter
than the old peak-only trigger. It is not a trained speech/music classifier.
Real-world accuracy needs the manual protocol below; synthetic fixtures are not
substitutes for recorded speech, music, or physical taps.

## Calibration and recovery

The setup screen stops ordinary listening and suppresses all assigned actions.
Start microphone explicitly, then measure 3 seconds of representative ambient
sound with hands still. Use the proposal to save it; measuring alone does not
change the saved threshold. The proposal is the larger of 0.01, three times the
95th-percentile peak, and six times the 95th-percentile RMS. Clipping or a proposed
threshold at/above 0.8 asks for a quieter environment/lower input gain.

Sensitivity scales the proposal by `2^(2*(0.5-sensitivity))`; higher sensitivity
lowers the threshold. The UI reports the effective threshold in dBFS. Sensitivity,
cooldown, tap spacing, and the last accepted device-specific threshold are saved locally.

Microphone denial has a Privacy & Security link; missing/unusable input has a
Sound Settings link and retry button. The system default-input property listener
and AVAudioEngine configuration-change notification stop detection after a route
change and invalidate calibration. Restart explicitly and calibrate again. A
watchdog stops input if audio frames stop arriving for more than two seconds.
Closing setup always stops the microphone. Trackpad remains an alternative.

## Repeatable manual protocol

Record Mac model, OS, input name, surface, room conditions, sensitivity, cooldown,
room RMS, and effective threshold. Do not strike the display or use force; gentle
palm-rest taps are sufficient. All trials take place inside Calibrate & test.

1. Start input, measure ambient noise, and accept the proposal.
2. Reset counts. Stay quiet and still for 30 seconds; record false counts.
3. Reset counts. Perform 5 single taps, 5 doubles, and 5 triples. Use about
   150–250 ms within patterns and at least one second between patterns. Record all
   three resulting counts, not just the expected total. Repeat twice if practical.
4. Reset counts. Speak normally for 30 seconds without tapping; record false counts.
5. Reset counts. Play typical music for 30 seconds at normal volume, without
   tapping; record false counts. Repeat the tap block with music if desired.
6. Change sensitivity and cooldown during a test; verify the displayed settings
   and compare counts. Long cooldown intentionally rejects closely spaced taps.
7. Pause/restart input, unplug or change the selected input in Sound Settings, and
   confirm a recovery message with no stale action. Retry and recalibrate.
8. Close setup; the microphone must stop and assigned actions remain unchanged.

Pass target for initial tuning: each 5-pattern block classified correctly, zero
false patterns in each 30-second quiet/speech/music block. Failure means adjust
and repeat, or explicitly document the limitation; never claim reliability from
synthetic checks alone.

## Measured results — 2026-09-08

Available host: MacBook Pro, Mac17,2, Apple M5, 24 GB RAM, macOS 27.0. The shell's audio inventory
reported no devices, so it cannot establish usable input; the native app is the
hardware-test surface. No hardware identifiers are recorded here.

Automated PCM fixtures executed on this Mac:

| Fixture | Duration | Result |
|---|---:|---|
| Three exponentially decaying 2 kHz impulses, 44.1 kHz PCM | 3 s | 3 detected |
| Same impulses, 48 kHz PCM | 3 s | 3 detected |
| Steady 440 Hz sine | 10 s | 0 detected |
| 180 Hz carrier with speech-like smooth envelope | 10 s | 0 detected |
| 220/880/1760 Hz music-like mixture | 10 s | 0 detected |
| Sustained high-crest envelope | 2 s | 0 detected |
| Clipped impulse | 2 s | 0 detected |

Calibration fixture RMS 0.01 / peak 0.02 proposed 0.06. Clipped calibration rejected.
Native app observation during the first user run: microphone capture and ambient
calibration operated with AirPods as the selected system input. At 21 seconds,
the app displayed 21 confirmed impulses and counts Single=7, Double=5, Triple=1,
effective threshold -41.4 dBFS. Intended tap counts and noise conditions were not
yet confirmed, so this is a raw observation, not an accuracy score. The user was
asked to switch to the built-in microphone and repeat.

User-reported built-in microphone trial at the original 460 ms grouping window:
singles worked perfectly, doubles worked less consistently (sometimes split into
two singles), and triples split more often. The user did not report exact counts.
Based on that feedback, the app's default grouping window was increased to 650 ms
and a live 300–1000 ms tap-spacing control was added. A clock-controlled regression
test confirms three taps 550 ms apart form one triple after this change.

A repeat built-in-microphone trial and actual speech/music observations are pending.
Keep T05 open until those results are recorded.
