# Developer notes

Detailed build, behavior and testing notes for the Knock prototype. For an overview, see the [main README](../../README.md).

## Overview

An original, offline SwiftUI utility for assigning Mac actions to single, double,
and triple knocks. Requires macOS 14 or newer and Xcode 15 or newer. The foundation
was verified with Xcode 26.6 on Apple silicon. There are no third-party dependencies.

## Open and run in Xcode

1. Open `Knock.xcodeproj`.
2. Select the shared **Knock** scheme and **My Mac** destination.
3. Press **Command-R**. The dark dashboard opens with listening paused.

The target uses **Sign to Run Locally**, so no developer account is required.
Keep Xcode's default Derived Data location outside this Documents folder. Building
an app bundle inside a file-provider-managed folder can add Finder metadata that
causes code signing to fail.

## Build and run from Terminal

Run from this project folder on an Apple silicon Mac:

```sh
knock_build_dir=$(mktemp -d /private/tmp/Knock-build.XXXXXX)
xcodebuild -project Knock.xcodeproj -scheme Knock -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$knock_build_dir" clean build
open "$knock_build_dir/Build/Products/Debug/Knock.app"
```

Each invocation creates a fresh Derived Data folder. On Intel, replace `arm64`
with `x86_64`; Intel execution has not yet been verified.

## App shell smoke check

- Confirm the dashboard appears and stays open.
- Find **Single**, **Double**, and **Triple** under **Take it for a tap**; these
  controls are available while listening is paused. The menu bar also has all
  three test commands.
- **Triple** uses the draft Shockwave action by default and should display an
  in-window ripple. Single defaults to Play / Pause, and Double to Screenshot;
  these attempt system actions and may require Accessibility permission.
- Open any action card, search or browse the categories, and choose an action.
  The card updates immediately; quit and reopen to verify the saved assignment.
  Selecting an action configures it without running it.
- Open **Activity** and **Settings**, then return to **Knocks**.

## Navigation and window controls

- **Command-1 / 2 / 3** opens Knocks, Activity, or Settings.
- **Option-Command-1 / 2 / 3** opens the corresponding action sheet.
- **Control-Command-1 / 2 / 3** tests the corresponding knock pattern.
- **Tab / Shift-Tab** moves focus. **Space / Return** activates focused controls.
  In the action picker, **↑ / ↓** browses results and scrolls the focused row into
  view. **Command-F** returns to search; **Return** in search chooses the first
  result. **Cancel / Escape** closes without changing the assignment.
- **Window → Compact Size** uses the minimum 900 × 620 content area (900 × 652
  including the hidden title bar on the verified host). **Window → Default Size**
  restores the 1020 × 700 window. The dashboard can scroll vertically as needed.
- The app follows macOS **Reduce Motion**: controls do not scale, reaction
  transitions do not animate, and Shockwave becomes a static acknowledgment.

Visual tokens and reusable controls live in `Knock/Views/DesignSystem.swift`.

## Current limits

T01–T04 supply a launchable app, the shared visual foundation, and a searchable
action picker with local persistence. All 15 actions appear under No Action,
Essentials, Media, Reactions, and Automation. Search matches names, descriptions,
and categories; an exact category name shows only that category. Activity and
Settings are intentionally placeholders. Knock grouping and simulation are tested;
accelerometer calibration and impulse filtering are implemented, with manual
validation in progress. Trackpad detection still uses its draft input adapter. Hardware
reliability, action execution, permissions, and lifecycle behavior
belong to later tasks. MacBook mode uses the built-in accelerometer, with no audio
capture. Its undocumented Apple SPU format is experimental and is not supported
on every Mac. The temporary bundle identifier is `dev.local.Knock`; release naming,
signing, and packaging remain undecided.

## Detection and simulation

Hardware sources and the simulator implement `KnockDetector`: normalized level,
status, raw impulse, and error events plus start/stop. Events reach one shared
`KnockSequenceRecognizer` on the main actor. The views contain no sensor or system event-monitor code.

- App defaults: 75 ms debounce, 650 ms silence after the last accepted impulse,
  maximum three taps. Tap spacing adjusts the grouping window live (300–1000 ms);
  debounce/count remain configurable in the recognizer constructor.
- An impulse exactly at the debounce boundary is accepted. At the timeout boundary
  it starts a new sequence. Rejected noise does not extend the timeout; once the
  maximum count is reached, extra input cannot postpone completion.
- Test buttons emit raw impulses 120 ms apart through the same recognizer. They
  work while listening is paused, and the panel shows the last recognized pattern.
- A new test replaces unfinished input. Hardware impulses are ignored during the
  test; normal recognition resumes afterward if hardware is listening.
- Stop and mode changes discard unfinished sequences and scheduled test taps.
  Generation checks reject events from sources that have already been stopped.

## MacBook calibration

Open **Calibrate & test…** beside MacBook mode. This pauses assigned actions and
opens the accelerometer setup screen. Start the accelerometer, keep the Mac still,
and measure resting vibration for three seconds before applying the suggested
threshold. The live readouts update independently of the dashboard. Sensitivity,
cooldown, and tap-spacing changes take effect live and
persist. The counters show physical single/double/triple recognition; closing
setup releases Knock's sensor connection. Sleep pauses MacBook detection and
requires starting again after wake. No microphone is used.

Chassis and desk taps work only when vibration reaches the laptop. A nearby desk
that is mechanically isolated from the Mac cannot be sensed. Speakers and moving
the Mac can also produce physical vibrations.

Typing and trackpad clicks strike the same chassis the sensor sits in, so they are
indistinguishable from taps by waveform. Knock instead ignores taps for 300 ms
after any keypress or trackpad press, controlled by **Ignore taps while typing**
and **Ignore taps while using the trackpad** in the setup screen; both default on.
The ignored counts appear in the setup metrics line so the filter is visible. Knock
reads only how long ago input happened, never which keys were pressed, and this
needs no Input Monitoring or Accessibility permission.

The available M5 Mac successfully delivers approximately 800 samples/second through
public IOKit HID functions. The report format is undocumented, so other hardware
or OS versions may fail. Knock requests 800 Hz because the driver advertises only
50, 100, 200, 400 and 800 Hz; an earlier build asked for an unsupported 125 Hz, which
some boots ignored and one boot answered with no samples at all. Energy savings over
microphone capture have not been established.

For compatibility, recovery, filtering details, and the hardware test protocol,
see [docs/ACCELEROMETER-DETECTION.md](../ACCELEROMETER-DETECTION.md). Real-world results remain separate from
synthetic signal tests. The superseded microphone implementation is not included in this repository;
its design is described in `docs/MICROPHONE-DETECTION.md`.

## Automated checks

Run from the project directory with Xcode installed:

```sh
bash Tests/run-checks.sh
```

The script builds a native XCTest bundle in a fresh temporary directory, runs 32
detector/engine/accelerometer-filter and recovery tests, then runs the 45 assignment round-trip and
search checks. It uses isolated preferences, mock hardware, and No Action mappings;
it does not request permissions or execute system actions. No network is required.

`Package.swift` also exposes the core and XCTest sources for standard `swift test`
workflows. This environment cannot launch SwiftPM's nested manifest sandbox, so
the verified script invokes Xcode's compiler and XCTest runner directly, within
the existing filesystem permissions.

Planning documents: [PROJECT.md](PROJECT.md) and the task board in [TASKS.md](TASKS.md). These are
historical working notes; their references to `HANDOFF.md` and the `work/` folder point to local
build logs and backups that are not part of this repository.
