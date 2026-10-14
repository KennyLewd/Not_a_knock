# T05 — MacBook accelerometer detection and calibration

## Objective

Recognize physical chassis vibration using the built-in accelerometer, per the
user's September 9 request. The previous microphone implementation is superseded.
Use public IOKit functions; document the unsupported vendor report format clearly.

## Acceptance criteria

- Document the actual sensor, access path, compatibility limits, and source evidence.
- Remove microphone capture from the active app and its microphone permission request.
- Permission denial, missing/unsupported input, and interrupted delivery have clear recovery paths.
- Calibration measures resting vibration and proposes a threshold for explicit application.
- Sensitivity and cooldown controls update detection live; preserve pattern grouping.
- Filter gravity/slow movement and sustained vibration; test physical taps separately
  from typing, movement, speech, and speaker vibration.
- Include repeatable manual checks and actual results on the available Mac. Record
  chassis and desk taps separately; desk vibration must physically reach the laptop.
- Measure sample delivery and processing cost. Do not assume energy savings over
  microphone capture without a matched comparison.

## Checks

Build the native app; run Tests/run-checks.sh; verify native access, calibration,
start/stop/restart, and action suppression. Perform five single, five double, and
five triple patterns with 1.5 seconds between patterns. Measure quiet, typing,
speech/music, and laptop movement separately. Record outstanding manual checks
rather than claiming completion from synthetic signals.
