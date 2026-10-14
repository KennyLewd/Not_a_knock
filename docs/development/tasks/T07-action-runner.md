# T07 — Reliable action execution

## Objective

Make every advertised action execute predictably and report failures clearly.

## Acceptance criteria

- Clipboard, screenshot, lock, media, Mission Control, app launch, and Apple Shortcut actions are implemented with appropriate public APIs.
- Permission-dependent actions explain the exact required permission.
- Action results are reported as success, failure, or user action required.
- Dangerous arbitrary shell-command execution is excluded from the default MVP.
- Unit-testable command construction is separated from system side effects.

