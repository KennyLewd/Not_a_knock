# Not a Knock

> **Unofficial prototype.** This is an independent experiment inspired by the idea of controlling a Mac with physical taps. It is an original implementation: it is not the original Knock, contains none of its code or artwork, and is not affiliated with or endorsed by Knock, Apple or their creators.

Not a Knock is a small native macOS utility (SwiftUI) that detects single, double and triple taps on a compatible MacBook and runs an action assigned to each pattern. It is rough, experimental and known to have bugs, but it is usable if you are comfortable with occasional misfires, missed taps and some setup.

## Features

- **Tap detection** through a compatible MacBook's built-in accelerometer: single, double and triple taps on the chassis, or on a desk the Mac sits on.
- **Assignable actions** for each pattern: Copy, Paste, Screenshot, Lock Screen, Mute, Play/Pause, Mission Control, Launchpad, Finder, Music, visual reactions and more, with a searchable picker.
- **Calibration** of sensitivity, cooldown and tap spacing, with live counters to test each pattern.
- **Accidental-tap filtering:** taps within 300 ms of typing or trackpad use are ignored (each can be toggled), and a rise-time gate separates real taps from lifting or moving the Mac.
- **Test buttons** that simulate each pattern without touching the hardware.
- **Offline and private:** no account, analytics or network connection, and no microphone.
- **No third-party dependencies;** Apple frameworks only.

## Requirements

- macOS 14 (Sonoma) or newer.
- A Mac with compatible motion-sensor hardware. The sensor's data format is undocumented, so detection has only been validated on the developer's own Mac and may not work on every model or macOS version.
- To build: Xcode 15 or newer.

## Install a prebuilt app

1. Download `Knock.zip` from the [Releases](../../releases) page and unzip it.
2. Move `Knock.app` to your Applications folder and open it.
3. The app is not notarized, so macOS will probably block the first launch. Open **System Settings → Privacy & Security** and choose **Open Anyway**. Only do this if you trust where your copy came from.
4. Grant **Accessibility** when an action needs it, then restart the app if macOS asks you to.

## Build from source

### In Xcode

1. Open `Knock.xcodeproj`.
2. Select the shared **Knock** scheme and the **My Mac** destination.
3. Press **⌘R**.

The target uses **Sign to Run Locally**, so no developer account is needed. Keep Xcode's Derived Data in its default location rather than inside a synced folder such as Documents; building inside a file-provider folder can add Finder metadata that breaks code signing.

### From Terminal

```sh
build_dir=$(mktemp -d /private/tmp/Knock-build.XXXXXX)
xcodebuild -project Knock.xcodeproj -scheme Knock -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$build_dir" clean build
open "$build_dir/Build/Products/Release/Knock.app"
```

On Intel Macs, replace `arm64` with `x86_64` (Intel has not been verified).

### Run the tests

```sh
bash Tests/run-checks.sh
```

This builds an XCTest bundle in a temporary folder and runs the detector, engine, accelerometer-filter and recovery tests, followed by the action-mapping and search checks. It uses mock hardware and isolated preferences, so it requests no permissions, runs no system actions and needs no network. `Package.swift` also exposes the core logic and tests for `swift test`.

## Getting started

1. Next to MacBook mode, open **Calibrate & test…**.
2. Start the accelerometer, keep the Mac still on a solid surface, and measure resting vibration for three seconds. Apply the suggested threshold.
3. Tap the Mac and watch the single, double and triple counters.
4. Assign low-risk actions first (for example a visual reaction or Play/Pause) before using Paste or Lock Screen.

Keyboard shortcuts: **⌘1/2/3** open Knocks, Activity and Settings; **⌥⌘1/2/3** open the action picker for each pattern; **⌃⌘1/2/3** simulate each pattern.

## Known rough edges

- Tap detection relies on an undocumented sensor format and may stop working after a reboot, on other Macs or on other macOS versions.
- Desk vibration, moving the laptop, speakers or very light or fast taps can cause misfires or missed taps.
- Calibration quality matters; a vibrating or soft surface produces poor settings.
- Detection pauses on sleep and must be started again after wake.
- Some actions need Accessibility permission and may behave differently across macOS versions.
- Trackpad mode, Activity, Settings, the menu bar and packaging are incomplete or placeholders.

Do not rely on this prototype for security, safety, accessibility or other critical workflows.

## Project structure

```
not-a-knock/
├── Knock/
│   ├── KnockApp.swift        # App entry point
│   ├── Models/               # Knock patterns and actions
│   ├── Services/             # Detectors, sequence recognizer, engine, action runner
│   └── Views/                # Dashboard, action picker, calibration, design system
├── Knock.xcodeproj/          # Xcode project with the shared Knock scheme
├── Tests/                    # XCTest suites and run-checks.sh
├── Package.swift             # SwiftPM package for the core logic and tests
└── docs/
    ├── ACCELEROMETER-DETECTION.md   # How detection, filtering and recovery work
    ├── MICROPHONE-DETECTION.md      # Earlier microphone approach (superseded)
    └── development/                 # Developer notes, project plan and task board
```

More detail on behavior, defaults and testing is in [docs/development/DEVELOPMENT.md](docs/development/DEVELOPMENT.md).

## Privacy

Everything runs locally. Input-suppression checks use only how long ago the keyboard or pointing device was used; they never record which keys were pressed.

## Status

A personal development build: buggy, unfinished and still evolving. It is shared as-is for testing and experimentation, with no promise of stability, support or compatibility.

## License

No license has been chosen yet, so all rights are reserved by default. To let others use, modify or share the code, add a `LICENSE` file (for example MIT).

Knock and Apple are trademarks of their respective owners. This project is not affiliated with either.
