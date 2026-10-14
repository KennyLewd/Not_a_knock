# T04 — Detector protocol and simulation

## Objective

Separate detection from the UI and make knock grouping deterministic and testable.

## Acceptance criteria

- A detector protocol exposes level, status, raw impulses, errors, start, and stop.
- A sequence recognizer groups impulses into single/double/triple patterns using configurable timing.
- Simulation uses the same recognition path as hardware input.
- Unit tests cover debounce, sequence timeout, maximum count, start/stop, and rapid noise.
- The UI owns no audio or global event-monitor implementation details.

