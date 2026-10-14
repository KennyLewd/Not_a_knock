# T01 — Project foundation and clean build

## Objective

Turn the current source draft into a real, reproducible Xcode macOS app that builds and launches.

## Scope

- Create the `.xcodeproj`, app target, Info.plist configuration, shared scheme, and sensible build settings.
- Include every source file in the target.
- Add minimal placeholder implementations for unfinished screens only when required to compile; feature work belongs to later tasks.
- Fix compile errors in the existing draft without redesigning it.
- Add a short README with open, build, and run instructions.

## Acceptance criteria

- `xcodebuild` succeeds from a clean derived-data directory.
- The app launches to its main window without crashing.
- Single, double, and triple test controls are reachable.
- The repository has no required third-party dependencies.
- `HANDOFF.md` records the exact build command and any warnings.

## Out of scope

- Pixel polish, reliable hardware detection, permission onboarding, comprehensive actions, distribution, or notarization.

