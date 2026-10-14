# Task board

Status values: `todo`, `in-progress`, `blocked`, `done`.

| ID | Status | Task | Specification |
|---|---|---|---|
| T01 | done | Project foundation and clean build | `tasks/T01-foundation.md` |
| T02 | done | App shell and design system | `tasks/T02-design-shell.md` |
| T03 | done | Action mapping and picker | `tasks/T03-action-mapping.md` |
| T04 | done | Detector protocol and simulation | `tasks/T04-detector-core.md` |
| T05 | in-progress | MacBook accelerometer detection and calibration | `tasks/T05-macbook-detection.md` |
| T06 | todo | Trackpad gestures, Morse shortcuts, and permissions | `tasks/T06-trackpad-mode.md` |
| T07 | todo | Reliable action execution | `tasks/T07-action-runner.md` |
| T08 | todo | Reactions, activity, and settings | `tasks/T08-polish-features.md` |
| T09 | todo | Menu bar, onboarding, and background behavior | `tasks/T09-app-lifecycle.md` |
| T10 | todo | QA, accessibility, performance, and packaging | `tasks/T10-release.md` |

Only one task may be `in-progress`. Complete it before advancing the next task unless the user explicitly reprioritizes the board.

Latest T05 progress (2026-09-09): the user reported typing registering as taps, so
impulses within 0.3 s of keyboard or trackpad input are now ignored, with a toggle
for each and visible ignored counts. 37 tests pass; Release build verified. Typing
suppression is physically confirmed by the user. Two trackpad leaks followed: bare
cursor movement, fixed by widening the pointer event group, then tap-to-click, whose
click is posted after the impact and so needed a 0.15 s held-impulse veto. That
second fix is confirmed. Labeled accuracy is recorded and clean: 5/5/5 patterns and
30 impulses for 30 intended taps, with 3 trackpad contacts correctly ignored during
the same run. Desk taps also passed 5/5/5 on a plastic office desk. Gently lifting
the Mac produced false singles, fixed by a 12 ms rise-time gate separating an impact
from arm movement and validated physically with no missed taps at 2.5x the earlier
sensitivity. Real sleep/wake and assigned actions firing are both confirmed. Only the
speech and speaker-music intervals remain untested, skipped by user decision on
2026-09-10.

T05 carries an unresolved limitation found 2026-09-11: since a reboot the SPU motion
block is not enabled, so the accelerometer delivers nothing while other SPU sensors
stream normally. Measured results above stand for the sessions they were taken in,
but MacBook mode cannot be relied on across boots and no public activation method was
found in the initial investigation. Superseded by the backed-up, user-authorized
activation experiment: targeted reporting/power requests restored sensor delivery.
The separate repaired build receives 795 decoded samples/sec and passes 48 tests.
T05 is reopened for physical-tap and fresh-boot validation; T06 is paused with its
existing recognizer work preserved. See HANDOFF.md for the pending test and paths.

September 15: T05 test reset/calibration now discard pending impacts, preventing
pre-reset taps from leaking into fresh counts. 50 XCTest cases and 45 assignment
round-trips pass. A separate Release app builds and verifies with the installed
Xcode after selecting the public State property wrapper explicitly. New app launch
and hardware checks remain unverified; physical-tap/reboot reply still pending.
T06 remains paused. See HANDOFF.md for build and backup paths.

September 15, later: user confirmed one physical tap increments Triple by one.
T05 therefore still fails physical accuracy. A ringing fixture reproduced this;
the new filter requires settled vibration or a distinct renewed impact. 54 tests
and 45 assignment round-trips pass; separate Verified build and signature pass.
Physical verification of that new build remains pending. See HANDOFF.md for the
exact app path; do not use the intermediate quiet-only build. T06 remains paused.
