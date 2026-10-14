import XCTest
import AppKit
import Combine
@testable import KnockCore

final class AccelerometerTests: XCTestCase {
    private func report(_ axes: [Int32]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 22)
        for (axis, offset) in zip(axes, [6, 10, 14]) {
            let bits = UInt32(bitPattern: axis)
            for index in 0..<4 { bytes[offset + index] = UInt8(truncatingIfNeeded: bits >> (index * 8)) }
        }
        return bytes
    }

    func testSignedQ16ReportAndInvalidFormats() {
        let decoded = report([65536, -32768, 16384]).withUnsafeBufferPointer(AccelerationSample.decode)
        XCTAssertEqual(decoded?.x, 1)
        XCTAssertEqual(decoded?.y, -0.5)
        XCTAssertEqual(decoded?.z, 0.25)
        XCTAssertNil([UInt8](repeating: 0, count: 21).withUnsafeBufferPointer(AccelerationSample.decode))
        XCTAssertNil([UInt8](repeating: 0, count: 23).withUnsafeBufferPointer(AccelerationSample.decode))
        XCTAssertNil(report([Int32.max, 0, 65536]).withUnsafeBufferPointer(AccelerationSample.decode))
    }

    // Independently generated physical-signal fixtures, not recordings from a Mac.
    private func detect(rate: Double = 800, threshold: Double = 0.025, cooldown: Double = 0.12,
                        duration: Double = 2, sample: (Double) -> AccelerationSample) -> [Double] {
        var filter = AccelerometerSignal(threshold: threshold, cooldown: cooldown)
        return (0...Int(duration * rate)).compactMap { index in
            let time = Double(index) / rate
            return filter.process(sample(time), at: time).tap ? time : nil
        }
    }

    private func impulses(_ times: [Double], at time: Double, amplitude: Double = 0.08) -> AccelerationSample {
        let x = times.reduce(0.0) { value, onset in
            value + ((onset..<(onset + 0.008)).contains(time) ? amplitude : 0)
        }
        return AccelerationSample(x: x, y: 0, z: 1)
    }

    func testSingleDoubleTripleAtBothSampleRates() {
        for rate in [125.0, 800.0] {
            for count in 1...3 {
                let times = (0..<count).map { 0.5 + Double($0) * 0.22 }
                let taps = detect(rate: rate) { self.impulses(times, at: $0) }
                XCTAssertEqual(taps.count, count, "rate=\(rate), count=\(count)")
            }
        }
    }

    func testCooldownRejectsImpactBounceButAllowsNextTap() {
        let taps = detect { self.impulses([0.5, 0.54, 0.58, 0.75], at: $0) }
        XCTAssertEqual(taps.count, 2)
        let slower = detect(cooldown: 0.4) { self.impulses([0.5, 0.75, 1.1], at: $0) }
        XCTAssertEqual(slower.count, 2)
    }

    /// A single damped vibration crosses zero many times; those crossings are
    /// not independent fingertip impacts. This fixture is synthetic, not a
    /// recording of the user's Mac.
    func testOneRingingImpactProducesOneTap() {
        // Match the measured ~795 Hz hardware and nominal 800 Hz stream. At
        // 125 Hz some short zero crossings are missed by the pre-existing decay
        // check; those low-rate omissions are separate from this overcount fix.
        for rate in [795.0, 800.0] {
            for frequency in [25.0, 40.0, 65.0] {
                let taps = detect(rate: rate, threshold: 0.0126) { time in
                    let t = time - 0.5
                    let x = t < 0 ? 0 : 0.12 * exp(-t / 0.16) * cos(2 * .pi * frequency * t)
                    return AccelerationSample(x: x, y: 0, z: 1)
                }
                XCTAssertEqual(taps.count, 1, "One impact at \(frequency) Hz, sampled at \(rate) Hz: \(taps)")
            }
        }
    }

    func testSeparateRingingImpactsRetainDoubleAndTripleCounts() {
        for rate in [125.0, 800.0] {
            for count in 1...3 {
                let times = (0..<count).map { 0.5 + Double($0) * 0.22 }
                let taps = detect(rate: rate, threshold: 0.0126) { time in
                    let x = times.reduce(0.0) { value, start in
                        let t = time - start
                        return value + (t < 0 ? 0 : 0.08 * exp(-t / 0.035) * cos(2 * .pi * 40 * t))
                    }
                    return AccelerationSample(x: x, y: 0, z: 1)
                }
                XCTAssertEqual(taps.count, count, "\(count) distinct impacts at \(rate) samples/s")
            }
        }
    }

    func testNewImpactsAreRecognizedBeforeEarlierRingingFullySettles() {
        for count in 2...3 {
            let times = (0..<count).map { 0.5 + Double($0) * 0.22 }
            let taps = detect(rate: 795, threshold: 0.0126) { time in
                let x = times.reduce(0.0) { value, start in
                    let t = time - start
                    return value + (t < 0 ? 0 : 0.12 * exp(-t / 0.16) * cos(2 * .pi * 40 * t))
                }
                return AccelerationSample(x: x, y: 0, z: 1)
            }
            XCTAssertEqual(taps.count, count, "A fresh impact must be distinguishable from its predecessor's tail")
        }
    }

    /// Deterministic pseudo-noise so a desk's resting vibration is reproducible.
    private func deskNoise(seed: inout UInt64) -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let u1 = Double((seed >> 11) & 0xFFFFFFFF) / Double(0xFFFFFFFF)
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let u2 = Double((seed >> 11) & 0xFFFFFFFF) / Double(0xFFFFFFFF)
        return sqrt(-2 * log(max(u1, 1e-12))) * cos(2 * .pi * u2)
    }

    /// The quiet floor once scaled with the threshold, so raising sensitivity
    /// dragged it below the desk's own resting vibration. The level then never
    /// read as quiet, impacts never completed, and taps were dropped in silence.
    /// Sensitivity must stay monotonic: turning it up may not reduce detection.
    func testHighSensitivityStillDetectsTapsOnAVibratingDesk() {
        let base = 0.0655
        let p99 = base / 4
        for sensitivity in [0.5, 0.65, 0.8037, 1.0] {
            var seed: UInt64 = 0x9E3779B97F4A7C15
            var filter = AccelerometerSignal(threshold: base * pow(2, 1 - 2 * sensitivity))
            filter.noiseFloor = p99
            let times = [0.5, 0.72, 0.94]
            var taps = 0
            for index in 0...Int(3 * 795.0) {
                let time = Double(index) / 795
                var x = (p99 / 2.33) * deskNoise(seed: &seed)
                for start in times where time >= start {
                    x += 0.12 * exp(-(time - start) / 0.16) * cos(2 * .pi * 40 * (time - start))
                }
                if filter.process(AccelerationSample(x: x, y: 0, z: 1), at: time).tap { taps += 1 }
            }
            XCTAssertEqual(taps, 3, "sensitivity \(sensitivity) on a desk with p99 noise \(p99)")
        }
    }

    /// Two modes, so the fixture cannot cancel itself the way a single pure tone
    /// does at gaps near half a cycle. A real chassis rings on several modes.
    private func chassisRing(_ strikes: [(Double, Double)], decay: Double) -> (Double) -> Double {
        return { time in
            strikes.reduce(0.0) { value, strike in
                let t = time - strike.0
                guard t >= 0 else { return value }
                let modes = 0.7 * cos(2 * .pi * 40 * t) + 0.3 * cos(2 * .pi * 65 * t)
                return value + strike.1 * exp(-t / decay) * modes
            }
        }
    }

    private func tapsDetected(_ wave: (Double) -> Double, threshold: Double, noise: Double) -> Int {
        var filter = AccelerometerSignal(threshold: threshold)
        filter.noiseFloor = noise
        var taps = 0
        for index in 0...Int(3 * 795.0) {
            let time = Double(index) / 795
            if filter.process(AccelerationSample(x: wave(time), y: 0, z: 1), at: time).tap { taps += 1 }
        }
        return taps
    }

    private var tapGaps: [Double] { stride(from: 0.13, through: 0.30, by: 0.005).map { $0 } }

    /// A second tap lands while the first is still ringing, so the filter must
    /// recognize a renewed impact rather than wait for silence. Requiring the new
    /// peak to nearly match the first (1.8x a fast-decaying envelope) lost the
    /// fast doubles and triples this feature exists for.
    func testFastEvenTapsAreCountedAcrossTheUsableGapRange() {
        for decay in [0.035, 0.08, 0.16] {
            var missed: [Double] = []
            for gap in tapGaps {
                let strikes = [(0.5, 0.12), (0.5 + gap, 0.10), (0.5 + 2 * gap, 0.10)]
                if tapsDetected(chassisRing(strikes, decay: decay), threshold: 0.0126, noise: 0.0039) != 3 {
                    missed.append(gap)
                }
            }
            XCTAssertLessThanOrEqual(missed.count, 2, "decay \(decay) missed gaps \(missed)")
        }
    }

    /// A deliberately light second and third tap on a long-ringing chassis is the
    /// hardest case and is not fully solved: the new impact can land out of phase
    /// with the tail and partially cancel. Held as a floor so it cannot regress.
    func testLightTapsOnALongRingAreMostlyCounted() {
        var detected = 0
        for gap in tapGaps {
            let strikes = [(0.5, 0.12), (0.5 + gap, 0.055), (0.5 + 2 * gap, 0.05)]
            if tapsDetected(chassisRing(strikes, decay: 0.16), threshold: 0.0126, noise: 0.0039) == 3 {
                detected += 1
            }
        }
        XCTAssertGreaterThanOrEqual(detected, 22, "\(detected) of \(tapGaps.count) gaps counted all three")
    }

    func testRestingGravityNoiseAndSlowTiltDoNotTrigger() {
        let taps = detect(duration: 6) { time in
            let angle = time * 0.08
            return AccelerationSample(x: sin(angle) + 0.0005 * sin(time * 170), y: 0, z: cos(angle))
        }
        XCTAssertTrue(taps.isEmpty)
    }

    func testSustainedDisplacementDoesNotBecomeTapOnRelease() {
        let taps = detect { time in
            AccelerationSample(x: (0.5..<0.8).contains(time) ? 0.2 : 0, y: 0, z: 1)
        }
        XCTAssertTrue(taps.isEmpty)
    }

    func testSensitivityChangesDetectionThreshold() {
        let lowSensitivity = detect(threshold: 0.1) { self.impulses([0.5], at: $0) }
        let highSensitivity = detect(threshold: 0.02) { self.impulses([0.5], at: $0) }
        XCTAssertTrue(lowSensitivity.isEmpty)
        XCTAssertEqual(highSensitivity.count, 1)
    }

    /// Isolates rise time from amplitude: the same peak delivered as a slow ramp
    /// and as an impact must give opposite results. A gently lifted Mac produced
    /// false single knocks before this gate existed.
    func testGentleLiftIsRejectedWhileTheSameAmplitudeImpactIsAccepted() {
        let peak = 0.05
        let lift = detect(duration: 2) { time -> AccelerationSample in
            let elapsed = time - 0.5
            let value: Double
            switch elapsed {
            case ..<0: value = 0
            case 0..<0.06: value = peak * elapsed / 0.06
            case 0.06..<0.09: value = peak * (1 - (elapsed - 0.06) / 0.03)
            default: value = 0
            }
            return AccelerationSample(x: value, y: 0, z: 1)
        }
        XCTAssertTrue(lift.isEmpty, "A gentle lift ramps too slowly to be a tap")

        let impact = detect(duration: 2) { self.impulses([0.5], at: $0, amplitude: peak) }
        XCTAssertEqual(impact.count, 1, "The same amplitude as an impact is still a tap")
    }

    func testWarmupStreamGapAndInvalidSamplesDiscardPartialImpacts() {
        var filter = AccelerometerSignal()
        let resting = AccelerationSample(x: 0, y: 0, z: 1)
        XCTAssertFalse(filter.process(resting, at: 0).tap)
        XCTAssertFalse(filter.process(AccelerationSample(x: 0.08, y: 0, z: 1), at: 0.01).tap)
        XCTAssertFalse(filter.process(resting, at: 0.02).tap)
        for index in 3...400 { _ = filter.process(resting, at: Double(index) / 1000) }
        XCTAssertFalse(filter.process(AccelerationSample(x: 0.08, y: 0, z: 1), at: 0.401).tap)
        XCTAssertFalse(filter.process(resting, at: 1.1).tap)
        XCTAssertFalse(filter.process(resting, at: 1.09).tap)
        XCTAssertFalse(filter.process(AccelerationSample(x: .nan, y: 0, z: 1), at: 1.11).tap)
        XCTAssertFalse(filter.process(resting, at: .infinity).tap)
        XCTAssertFalse(filter.process(resting, at: 1.12).tap)
    }

    @MainActor func testAccelerometerPreferencesRestoreWithoutOldMicrophoneProfile() async {
        let suite = "dev.local.Knock.AccelerometerChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0.75, forKey: "knock.accelerometer.sensitivity")
        defaults.set(0.2, forKey: "knock.accelerometer.cooldown")
        defaults.set(0.04, forKey: "knock.accelerometer.threshold")
        let engine = KnockEngine(defaults: defaults)
        XCTAssertEqual(engine.sensitivity, 0.75)
        XCTAssertEqual(engine.cooldown, 0.2)
        XCTAssertEqual(engine.accelerometerSnapshot.threshold, 0.04 * pow(2, -0.5), accuracy: 0.000001)
        XCTAssertFalse(engine.isListening)
        engine.sensitivity = 0.25
        XCTAssertEqual(engine.accelerometerSnapshot.threshold, 0.04 * pow(2, 0.5), accuracy: 0.000001)
        engine.cooldown = 0.15
        let restored = KnockEngine(defaults: defaults)
        XCTAssertEqual(restored.sensitivity, 0.25)
        XCTAssertEqual(restored.cooldown, 0.15)
    }
}

@MainActor
private final class FakeAccelerometerConnection: AccelerometerInputConnection {
    var sample: (@MainActor (AccelerationSample) -> Void)?
    var failure: (@MainActor (String) -> Void)?
    var starts = 0
    var closes = 0
    var recoveries = 0
    var recoveryAvailable = false
    var recoveryError: KnockDetectorFailure?
    func recoverIdleSensor() throws -> Bool {
        recoveries += 1
        if let recoveryError { throw recoveryError }
        return recoveryAvailable
    }
    func activate(sample: @escaping @MainActor (AccelerationSample) -> Void,
                  failure: @escaping @MainActor (String) -> Void) {
        self.sample = sample; self.failure = failure; starts += 1
    }
    func close() { closes += 1 }
}

@MainActor
private final class FakeInputActivity: InputActivityMonitor {
    var keyboard = Double.infinity
    var pointer = Double.infinity
    func secondsSinceKeyboard() -> Double { keyboard }
    func secondsSincePointer() -> Double { pointer }
}

/// Feeds the real detector a warmed-up resting stream plus synthetic chassis
/// impacts, so suppression is exercised through the same path hardware uses.
@MainActor
private final class TapHarness {
    let clock: VirtualKnockScheduler
    let input: FakeAccelerometerConnection
    let activity: FakeInputActivity
    let detector: AccelerometerKnockDetector
    private(set) var impulses = 0

    init() {
        let clock = VirtualKnockScheduler()
        let input = FakeAccelerometerConnection()
        let activity = FakeInputActivity()
        self.clock = clock
        self.input = input
        self.activity = activity
        detector = AccelerometerKnockDetector(scheduler: clock, inputFactory: { input },
                                              workspaceNotifications: NotificationCenter(),
                                              inputActivity: activity)
        detector.onEvent = { [weak self] event in
            if case .impulse = event { self?.impulses += 1 }
        }
        detector.start()
        rest(0.4)
    }

    /// Advances the clock so held impulses reach their veto deadline.
    func rest(_ duration: Double) {
        for _ in 0..<Int((duration / 0.01).rounded()) {
            clock.advance(to: clock.now + 0.01)
            input.sample?(AccelerationSample(x: 0, y: 0, z: 1))
        }
    }

    /// One brief impact, then enough quiet to clear the veto hold and the cooldown.
    func strike() {
        clock.advance(to: clock.now + 0.01)
        input.sample?(AccelerationSample(x: 0.08, y: 0, z: 1))
        rest(0.25)
    }
}

final class InputSuppressionTests: XCTestCase {
    @MainActor func testResetDiscardsBothUnconfirmedAndHeldTapsWithoutRestartingSensor() async {
        for confirmed in [false, true] {
            let harness = TapHarness()
            harness.clock.deliverCancelled = true
            harness.clock.advance(to: harness.clock.now + 0.01)
            harness.input.sample?(AccelerationSample(x: 0.08, y: 0, z: 1))
            if confirmed { harness.rest(0.05) }
            let threshold = harness.detector.snapshot.threshold
            harness.detector.resetMetrics()
            XCTAssertEqual(harness.detector.snapshot.sampleRate, 0)
            XCTAssertEqual(harness.detector.snapshot.samples, 0)
            XCTAssertEqual(harness.detector.snapshot.seconds, 0)
            harness.rest(0.3)
            XCTAssertEqual(harness.impulses, 0, "A pre-reset tap must not enter the fresh trial")
            XCTAssertEqual(harness.detector.snapshot.impulses, 0)
            XCTAssertEqual(harness.detector.snapshot.threshold, threshold)
            XCTAssertEqual(harness.input.starts, 1)
            XCTAssertEqual(harness.input.closes, 0)
            harness.strike()
            XCTAssertEqual(harness.impulses, 1, "New taps should still count after reset")
        }
    }

    @MainActor func testCalibrationBoundaryDiscardsTapsWaitingForInputVeto() async {
        let harness = TapHarness()
        harness.clock.deliverCancelled = true
        harness.clock.advance(to: harness.clock.now + 0.01)
        harness.input.sample?(AccelerationSample(x: 0.08, y: 0, z: 1))
        harness.rest(0.05)
        harness.detector.beginCalibration()
        harness.rest(0.2)
        XCTAssertEqual(harness.impulses, 0, "A pending tap must not fire during calibration")
        harness.detector.cancelCalibration()
        harness.rest(0.4)
        harness.strike()
        XCTAssertEqual(harness.impulses, 1)
    }

    @MainActor func testTypingAndTrackpadContactAreIgnoredUntilInputSettles() async {
        let harness = TapHarness()

        harness.activity.keyboard = 0.05
        harness.strike()
        XCTAssertEqual(harness.impulses, 0, "A tap during typing must never reach recognition")
        XCTAssertEqual(harness.detector.snapshot.ignoredTyping, 1)

        harness.activity.keyboard = .infinity
        harness.activity.pointer = 0.05
        harness.strike()
        XCTAssertEqual(harness.impulses, 0)
        XCTAssertEqual(harness.detector.snapshot.ignoredPointer, 1)

        // The window boundary itself counts as settled.
        harness.activity.keyboard = AccelerometerKnockDetector.inputSettleWindow
        harness.activity.pointer = AccelerometerKnockDetector.inputSettleWindow
        harness.strike()
        XCTAssertEqual(harness.impulses, 1)
        XCTAssertEqual(harness.detector.snapshot.impulses, 1)
        XCTAssertEqual(harness.detector.snapshot.ignoredTyping, 1)
        XCTAssertEqual(harness.detector.snapshot.ignoredPointer, 1)

        harness.detector.resetMetrics()
        XCTAssertEqual(harness.detector.snapshot.ignoredTyping, 0)
        XCTAssertEqual(harness.detector.snapshot.ignoredPointer, 0)
        XCTAssertEqual(harness.detector.snapshot.impulses, 0)
    }

    /// Tap-to-click strikes the glass before the driver posts the click, so the
    /// impulse is detected while no pointer event exists yet.
    @MainActor func testClickArrivingAfterTheImpactStillVetoesTheTap() async {
        let harness = TapHarness()
        harness.clock.advance(to: harness.clock.now + 0.01)
        harness.input.sample?(AccelerationSample(x: 0.08, y: 0, z: 1))

        // Nothing to see yet: the tap-to-click event has not been posted.
        harness.rest(0.05)
        XCTAssertEqual(harness.impulses, 0, "The impulse must be held, not delivered on sight")
        XCTAssertEqual(harness.detector.snapshot.ignoredPointer, 0)

        harness.activity.pointer = 0
        harness.rest(0.2)
        XCTAssertEqual(harness.impulses, 0, "A late click must still cancel the tap")
        XCTAssertEqual(harness.detector.snapshot.ignoredPointer, 1)
        XCTAssertEqual(harness.detector.snapshot.impulses, 0)
    }

    @MainActor func testStopCancelsHeldImpulsesSoNoneArriveLater() async {
        let harness = TapHarness()
        harness.clock.advance(to: harness.clock.now + 0.01)
        harness.input.sample?(AccelerationSample(x: 0.08, y: 0, z: 1))
        harness.rest(0.05)
        harness.detector.stop()
        harness.clock.advance(to: harness.clock.now + 1)
        XCTAssertEqual(harness.impulses, 0)
        XCTAssertEqual(harness.detector.snapshot.impulses, 0)
    }

    @MainActor func testEachSuppressionCanBeTurnedOffIndependently() async {
        let harness = TapHarness()
        harness.activity.keyboard = 0
        harness.activity.pointer = 0

        harness.detector.ignoreWhileTyping = false
        harness.detector.ignoreWhileUsingTrackpad = false
        harness.strike()
        XCTAssertEqual(harness.impulses, 1, "Taps must still work when the user opts out")
        XCTAssertEqual(harness.detector.snapshot.ignoredTyping, 0)
        XCTAssertEqual(harness.detector.snapshot.ignoredPointer, 0)

        harness.detector.ignoreWhileTyping = true
        harness.strike()
        XCTAssertEqual(harness.impulses, 1)
        XCTAssertEqual(harness.detector.snapshot.ignoredTyping, 1)

        harness.detector.ignoreWhileTyping = false
        harness.detector.ignoreWhileUsingTrackpad = true
        harness.strike()
        XCTAssertEqual(harness.impulses, 1)
        XCTAssertEqual(harness.detector.snapshot.ignoredPointer, 1)
    }

    @MainActor func testSuppressionPreferencesDefaultOnAndPersist() async {
        let suite = "dev.local.Knock.SuppressionChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = KnockEngine(defaults: defaults)
        XCTAssertTrue(engine.ignoreWhileTyping)
        XCTAssertTrue(engine.ignoreWhileUsingTrackpad)
        engine.ignoreWhileTyping = false
        let restored = KnockEngine(defaults: defaults)
        XCTAssertFalse(restored.ignoreWhileTyping)
        XCTAssertTrue(restored.ignoreWhileUsingTrackpad)
    }

    /// Mode was the one setting with no `defaults.set`, so every launch silently
    /// returned to MacBook regardless of what the user had chosen.
    @MainActor func testDetectionModeSurvivesRelaunch() async {
        let suite = "dev.local.Knock.ModePersistence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(KnockEngine(defaults: defaults).mode, .macBook)
        let engine = KnockEngine(defaults: defaults)
        engine.mode = .trackpad
        XCTAssertEqual(KnockEngine(defaults: defaults).mode, .trackpad)
    }

    /// Detection began paused on every launch, so it was off unless re-enabled by
    /// hand each time. The app should come back the way it was left.
    @MainActor func testDetectionResumesOnLaunchOnlyWhenItWasLeftOn() async {
        let suite = "dev.local.Knock.ResumeDetection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = SimulatedKnockDetector(scheduler: MainKnockScheduler())
        let factory: (DetectionMode) -> any KnockDetector = { _ in source }

        XCTAssertFalse(KnockEngine(defaults: defaults, detectorFactory: factory).isListening)

        let engine = KnockEngine(defaults: defaults, detectorFactory: factory)
        engine.toggleListening()
        XCTAssertTrue(defaults.bool(forKey: "knock.detectionEnabled"))
        engine.toggleListening()
        XCTAssertFalse(defaults.bool(forKey: "knock.detectionEnabled"))
    }

    /// Label, description and key code had drifted apart: the action read
    /// "Open the macOS screenshot tool" but sent Cmd+Shift+4, which only arms the
    /// crosshair and saves nothing unless a region is then dragged by hand.
    @MainActor func testScreenshotActionOpensTheCaptureTool() async {
        XCTAssertEqual(ActionRunner.screenshotKey, 23, "Cmd+Shift+5 opens the capture tool")
        XCTAssertEqual(KnockAction.screenshot.subtitle, "Open the macOS screenshot tool")
    }

    /// Lock Screen spawned a CGSession helper inside a Menu Extra that no longer
    /// ships; the path is absent on macOS 27 and `try?` hid the failure entirely.
    /// Ctrl+Cmd+Q is the system shortcut and needs only the Accessibility grant
    /// the other keystroke actions already require.
    @MainActor func testLockScreenUsesTheSystemShortcutNotAMissingHelper() async {
        XCTAssertEqual(ActionRunner.lockScreenKey, 12, "Ctrl+Cmd+Q is Lock Screen")
        let retired = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        XCTAssertFalse(FileManager.default.fileExists(atPath: retired),
                       "if this helper ever returns, revisit why it was dropped")
    }

    /// Closing the tuning sheet used to stop detection outright, so the one place
    /// it could be switched on was the one place its results did not count.
    @MainActor func testLeavingTheDetectionCheckRestoresRunningDetection() async {
        let suite = "dev.local.Knock.CheckExit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = SimulatedKnockDetector(scheduler: MainKnockScheduler())
        let engine = KnockEngine(defaults: defaults, detectorFactory: { _ in source })

        engine.toggleListening()
        XCTAssertTrue(defaults.bool(forKey: "knock.detectionEnabled"))
        engine.beginDetectionCheck()
        XCTAssertTrue(engine.isDetectionCheck)
        engine.endDetectionCheck()
        XCTAssertFalse(engine.isDetectionCheck)
        XCTAssertNotEqual(engine.detectorStatus, .stopped, "detection must resume after the check")
    }
}

final class AccelerometerRecoveryTests: XCTestCase {
    @MainActor func testOneRingingImpactCountsAsSingleThroughTheEngine() async {
        let clock = VirtualKnockScheduler()
        let input = FakeAccelerometerConnection()
        let source = AccelerometerKnockDetector(scheduler: clock, inputFactory: { input },
                                                workspaceNotifications: NotificationCenter(),
                                                inputActivity: FakeInputActivity())
        source.baseThreshold = 0.0126
        let suite = "dev.local.Knock.RingingCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = KnockEngine(defaults: defaults, scheduler: clock, detectorFactory: { _ in source })
        engine.beginDetectionCheck()
        engine.startListening()
        for index in 0...1590 {
            let time = Double(index) / 795
            clock.advance(to: time)
            let t = time - 0.5
            let x = t < 0 ? 0 : 0.12 * exp(-t / 0.16) * cos(2 * .pi * 40 * t)
            input.sample?(AccelerationSample(x: x, y: 0, z: 1))
        }
        XCTAssertEqual(source.snapshot.impulses, 1)
        XCTAssertEqual(engine.checkCounts[.single, default: 0], 1)
        XCTAssertEqual(engine.checkCounts[.double, default: 0], 0)
        XCTAssertEqual(engine.checkCounts[.triple, default: 0], 0)
        XCTAssertTrue(engine.activity.isEmpty, "A calibration test must not run assigned actions")
        engine.endDetectionCheck()
    }

    @MainActor func testIdleActivationWaitsForRealSamplesAndDoesNotRepeat() async {
        let clock = VirtualKnockScheduler()
        let input = FakeAccelerometerConnection()
        input.recoveryAvailable = true
        let detector = AccelerometerKnockDetector(scheduler: clock, inputFactory: { input }, workspaceNotifications: NotificationCenter())
        detector.start()
        clock.advance(to: 2)
        XCTAssertEqual(input.recoveries, 1)
        XCTAssertEqual(detector.status, .starting, "A successful property write is not proof of delivery")
        clock.advance(to: 2.5)
        input.sample?(AccelerationSample(x: 0, y: 0, z: 1))
        XCTAssertEqual(detector.status, .running)
        clock.advance(to: 6)
        XCTAssertEqual(detector.status, .failed)
        XCTAssertEqual(input.recoveries, 1, "Do not repeatedly change sensor power when delivery stops")
        XCTAssertEqual(input.closes, 1)
    }

    @MainActor func testIdleActivationTimeoutAndCancellationReleaseInput() async {
        for cancel in [false, true] {
            let clock = VirtualKnockScheduler()
            clock.deliverCancelled = true
            let input = FakeAccelerometerConnection()
            input.recoveryAvailable = true
            let detector = AccelerometerKnockDetector(scheduler: clock, inputFactory: { input }, workspaceNotifications: NotificationCenter())
            detector.start()
            clock.advance(to: 2)
            if cancel { detector.stop() }
            clock.advance(to: 10)
            XCTAssertEqual(detector.status, cancel ? .stopped : .failed)
            XCTAssertEqual(input.recoveries, 1)
            XCTAssertEqual(input.closes, 1)
        }
    }

    @MainActor func testActivationFailureClosesInputAndReportsTheCause() async {
        let clock = VirtualKnockScheduler()
        let input = FakeAccelerometerConnection()
        input.recoveryError = KnockDetectorFailure(message: "Activation rejected")
        let detector = AccelerometerKnockDetector(scheduler: clock, inputFactory: { input }, workspaceNotifications: NotificationCenter())
        detector.start()
        clock.advance(to: 2)
        XCTAssertEqual(detector.status, .failed)
        XCTAssertEqual(detector.lastError?.message, "Activation rejected")
        XCTAssertEqual(input.closes, 1)
    }

    @MainActor func testOpenFailureAndNoDeliveryDoNotClaimRunning() async {
        let clock = VirtualKnockScheduler()
        let denied = AccelerometerKnockDetector(scheduler: clock, inputFactory: {
            throw KnockDetectorFailure(message: "Test access denied")
        }, workspaceNotifications: NotificationCenter())
        denied.start()
        XCTAssertEqual(denied.status, .failed)
        XCTAssertEqual(denied.lastError?.message, "Test access denied")

        let input = FakeAccelerometerConnection()
        let detector = AccelerometerKnockDetector(scheduler: clock, inputFactory: { input },
                                                  workspaceNotifications: NotificationCenter())
        detector.start()
        XCTAssertEqual(detector.status, .starting)
        clock.advance(to: 2)
        XCTAssertEqual(detector.status, .failed)
        XCTAssertEqual(input.closes, 1)
        XCTAssertNotNil(detector.lastError)
        detector.stop()
        XCTAssertEqual(input.closes, 1)
    }

    @MainActor func testRestartAndLateCallbacksCannotReviveStoppedInput() async {
        let clock = VirtualKnockScheduler()
        clock.deliverCancelled = true
        let first = FakeAccelerometerConnection(), second = FakeAccelerometerConnection()
        var openings = 0
        let detector = AccelerometerKnockDetector(scheduler: clock, inputFactory: {
            openings += 1
            return openings == 1 ? first : second
        }, workspaceNotifications: NotificationCenter())
        detector.start()
        first.sample?(AccelerationSample(x: 0, y: 0, z: 1))
        XCTAssertEqual(detector.status, .running)
        detector.stop()
        first.sample?(AccelerationSample(x: 1, y: 0, z: 1))
        XCTAssertEqual(detector.status, .stopped)
        detector.start()
        clock.advance(to: 1)
        second.sample?(AccelerationSample(x: 0, y: 0, z: 1))
        first.sample?(AccelerationSample(x: 1, y: 0, z: 1))
        XCTAssertEqual(detector.snapshot.samples, 1)
        clock.advance(to: 2)
        XCTAssertEqual(detector.status, .running)
        clock.advance(to: 4)
        XCTAssertEqual(detector.status, .failed)
        XCTAssertEqual(first.closes, 1)
        XCTAssertEqual(second.closes, 1)
    }

    @MainActor func testSleepClosesInputAndCancelsItsWatchdog() async {
        let clock = VirtualKnockScheduler()
        clock.deliverCancelled = true
        let center = NotificationCenter()
        let input = FakeAccelerometerConnection()
        let detector = AccelerometerKnockDetector(scheduler: clock, inputFactory: { input },
                                                  workspaceNotifications: center)
        detector.start()
        input.sample?(AccelerationSample(x: 0, y: 0, z: 1))
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertEqual(detector.status, .failed)
        XCTAssertEqual(input.closes, 1)
        XCTAssertTrue(detector.lastError?.message.contains("sleep") == true)
        clock.advance(to: 10)
        XCTAssertTrue(detector.lastError?.message.contains("sleep") == true)
        detector.stop()
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertEqual(detector.status, .stopped)
        XCTAssertEqual(input.closes, 1)
    }

    @MainActor func testReportFailureReleasesConnectionAfterCallback() async {
        let clock = VirtualKnockScheduler()
        let input = FakeAccelerometerConnection()
        let detector = AccelerometerKnockDetector(scheduler: clock, inputFactory: { input },
                                                  workspaceNotifications: NotificationCenter())
        let failed = expectation(description: "Asynchronous failure delivered")
        detector.onEvent = { if case .error = $0 { failed.fulfill() } }
        detector.start()
        input.failure?("Test unsupported report")
        XCTAssertEqual(input.closes, 0, "Keep the callback buffer alive until callback returns")
        await fulfillment(of: [failed], timeout: 1)
        XCTAssertEqual(input.closes, 1)
        XCTAssertEqual(detector.status, .failed)
        XCTAssertEqual(detector.lastError?.message, "Test unsupported report")
    }

    @MainActor func testCalibrationRequiresApplyAndStopDiscardsProposal() async {
        let clock = VirtualKnockScheduler()
        let input = FakeAccelerometerConnection()
        let detector = AccelerometerKnockDetector(scheduler: clock, inputFactory: { input },
                                                  workspaceNotifications: NotificationCenter())
        var saved: [Double] = []
        detector.onThreshold = { saved.append($0) }
        detector.start()
        input.sample?(AccelerationSample(x: 0, y: 0, z: 1))
        detector.beginCalibration()
        for step in 1...30 {
            clock.advance(to: Double(step) / 10)
            input.sample?(AccelerationSample(x: 0, y: 0, z: 1))
        }
        XCTAssertEqual(detector.snapshot.calibration, .proposed(0.008))
        XCTAssertTrue(saved.isEmpty)
        detector.applyCalibration()
        XCTAssertEqual(saved, [0.008])
        XCTAssertEqual(detector.snapshot.calibration, .idle)
        detector.beginCalibration()
        detector.stop()
        XCTAssertEqual(detector.snapshot.calibration, .idle)
        detector.applyCalibration()
        XCTAssertEqual(saved, [0.008])
    }

    @MainActor func testDiagnosticsPublishOnlyChangedReadouts() async {
        let diagnostics = KnockDiagnostics()
        var calibrationUpdates = 0, metricUpdates = 0, levelUpdates = 0
        let a = diagnostics.calibration.objectWillChange.sink { calibrationUpdates += 1 }
        let b = diagnostics.metrics.objectWillChange.sink { metricUpdates += 1 }
        let c = diagnostics.level.objectWillChange.sink { levelUpdates += 1 }
        for index in 1...800 {
            var snapshot = AccelerometerSnapshot()
            snapshot.samples = index
            snapshot.seconds = Double(index) / 800
            snapshot.sampleRate = 800
            snapshot.dynamicG = Double(index) / 1000
            diagnostics.update(snapshot)
        }
        XCTAssertEqual(calibrationUpdates, 0)
        XCTAssertEqual(metricUpdates, 2, "Only initial rate and the displayed second changed")
        XCTAssertEqual(levelUpdates, 0)
        XCTAssertEqual(diagnostics.snapshot.samples, 800)
        var snapshot = diagnostics.snapshot
        snapshot.calibration = .proposed(0.02)
        diagnostics.update(snapshot)
        XCTAssertEqual(calibrationUpdates, 1)
        XCTAssertEqual(metricUpdates, 2)
        withExtendedLifetime((a, b, c)) {}
    }
}
