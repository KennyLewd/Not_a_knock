import XCTest
import Combine
@testable import KnockCore

@MainActor
final class VirtualKnockScheduler: KnockScheduler {
    final class Entry {
        let deadline: TimeInterval
        let order: Int
        let action: @MainActor () -> Void
        var cancelled = false
        init(deadline: TimeInterval, order: Int, action: @escaping @MainActor () -> Void) {
            self.deadline = deadline
            self.order = order
            self.action = action
        }
    }
    var now: TimeInterval = 0
    var deliverCancelled = false
    private var order = 0
    private var entries: [Entry] = []

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> KnockScheduledTask {
        order += 1
        let entry = Entry(deadline: now + delay, order: order, action: action)
        entries.append(entry)
        return KnockScheduledTask { entry.cancelled = true }
    }

    func advance(to target: TimeInterval) {
        precondition(target >= now)
        while let next = entries.filter({ $0.deadline <= target }).min(by: {
            ($0.deadline, $0.order) < ($1.deadline, $1.order)
        }) {
            entries.removeAll { $0 === next }
            now = max(now, next.deadline)
            if !next.cancelled || deliverCancelled { next.action() }
        }
        now = target
    }

    // Model a busy main queue: time passes before any scheduled closure runs.
    func elapseWithoutDelivery(to target: TimeInterval) { now = target }
}

@MainActor
private final class FakeDetector: KnockDetectorSource {
    var starts = 0
    var stops = 0
    var remainsStarting = false
    override func start() {
        starts += 1
        super.start()
        if !remainsStarting { setStatus(.running) }
    }
    override func stop() { stops += 1; super.stop() }
}

final class DetectorCoreTests: XCTestCase {
    @MainActor
    private func recognizer(_ clock: VirtualKnockScheduler, maximum: Int = 3) -> KnockSequenceRecognizer {
        KnockSequenceRecognizer(configuration: .init(debounce: 1, sequenceTimeout: 10, maximumCount: maximum),
                                scheduler: clock)
    }

    @MainActor func testSingleDoubleTripleAndTimeoutBoundary() async {
        for count in 1...3 {
            let clock = VirtualKnockScheduler()
            let subject = recognizer(clock)
            var patterns: [KnockPattern] = []
            subject.onPattern = { patterns.append($0) }
            subject.start()
            for index in 0..<count {
                clock.advance(to: Double(index * 2))
                subject.receiveImpulse()
            }
            let deadline = Double((count - 1) * 2) + 10
            clock.advance(to: deadline - 0.01)
            XCTAssertTrue(patterns.isEmpty)
            XCTAssertEqual(subject.pendingCount, count)
            clock.advance(to: deadline)
            XCTAssertEqual(patterns.map(\.rawValue), [count])
            XCTAssertEqual(subject.pendingCount, 0)
            clock.advance(to: deadline + 100)
            XCTAssertEqual(patterns.count, 1)
        }
    }

    @MainActor func testDebounceIgnoresNoiseWithoutExtendingTimeout() async {
        let clock = VirtualKnockScheduler()
        let subject = recognizer(clock)
        var patterns: [KnockPattern] = []
        subject.onPattern = { patterns.append($0) }
        subject.start()
        subject.receiveImpulse()
        for index in 1...99 {
            clock.advance(to: Double(index) / 100)
            subject.receiveImpulse()
        }
        XCTAssertEqual(subject.pendingCount, 1)
        clock.advance(to: 10)
        XCTAssertEqual(patterns, [.single])
    }

    @MainActor func testExactDebounceBoundaryIsAccepted() async {
        let clock = VirtualKnockScheduler()
        let subject = recognizer(clock)
        subject.start()
        subject.receiveImpulse()
        clock.advance(to: 1)
        subject.receiveImpulse()
        XCTAssertEqual(subject.pendingCount, 2)
    }

    @MainActor func testMaximumCountAndContinuousNoiseCannotPostponeCompletion() async {
        let clock = VirtualKnockScheduler()
        let subject = recognizer(clock)
        var patterns: [KnockPattern] = []
        subject.onPattern = { patterns.append($0) }
        subject.start()
        for index in 0..<1200 {
            clock.advance(to: Double(index) / 100)
            subject.receiveImpulse()
            XCTAssertLessThanOrEqual(subject.pendingCount, 3)
        }
        clock.advance(to: 12)
        XCTAssertEqual(patterns, [.triple])
        XCTAssertEqual(subject.pendingCount, 0)
    }

    @MainActor func testConfigurableMaximumCount() async {
        let clock = VirtualKnockScheduler()
        let subject = recognizer(clock, maximum: 2)
        var patterns: [KnockPattern] = []
        subject.onPattern = { patterns.append($0) }
        subject.start()
        subject.receiveImpulse()
        clock.advance(to: 2)
        subject.receiveImpulse()
        clock.advance(to: 4)
        subject.receiveImpulse()
        clock.advance(to: 12)
        XCTAssertEqual(patterns, [.double])
    }

    @MainActor func testStopAndRestartDiscardPendingAndAlreadyQueuedCallbacks() async {
        let clock = VirtualKnockScheduler()
        clock.deliverCancelled = true
        let subject = recognizer(clock)
        var patterns: [KnockPattern] = []
        subject.onPattern = { patterns.append($0) }
        subject.receiveImpulse()
        XCTAssertEqual(subject.pendingCount, 0)
        subject.start()
        subject.receiveImpulse()
        subject.stop()
        subject.receiveImpulse()
        clock.advance(to: 5)
        subject.start()
        subject.receiveImpulse()
        clock.advance(to: 10)
        XCTAssertTrue(patterns.isEmpty)
        XCTAssertEqual(subject.pendingCount, 1)
        clock.advance(to: 15)
        XCTAssertEqual(patterns, [.single])
    }

    @MainActor func testLiveTimingAllowsSlowerPatternsAndCancelsOldDeadline() async {
        let clock = VirtualKnockScheduler()
        clock.deliverCancelled = true
        let subject = KnockSequenceRecognizer(scheduler: clock)
        var patterns: [KnockPattern] = []
        subject.onPattern = { patterns.append($0) }
        subject.start()
        subject.receiveImpulse()
        subject.setSequenceTimeout(0.65)
        clock.advance(to: 0.1)
        subject.receiveImpulse()
        clock.advance(to: 0.65)
        subject.receiveImpulse()
        clock.advance(to: 1.2)
        subject.receiveImpulse()
        clock.advance(to: 1.86)
        XCTAssertEqual(patterns, [.triple])
    }

    @MainActor func testLateTimerSeparatesSequences() async {
        let clock = VirtualKnockScheduler()
        let subject = recognizer(clock)
        var patterns: [KnockPattern] = []
        subject.onPattern = { patterns.append($0) }
        subject.start()
        subject.receiveImpulse()
        clock.elapseWithoutDelivery(to: 10)
        subject.receiveImpulse()
        XCTAssertEqual(patterns, [.single])
        XCTAssertEqual(subject.pendingCount, 1)
        clock.advance(to: 20)
        XCTAssertEqual(patterns, [.single, .single])
    }

    @MainActor func testSimulationHasRawEventsAndDoesNotBypassDebounce() async {
        let clock = VirtualKnockScheduler()
        let subject = recognizer(clock) // 1 second debounce rejects 0.12 second simulated spacing.
        let source = SimulatedKnockDetector(scheduler: clock)
        var rawCount = 0
        var patterns: [KnockPattern] = []
        var statuses: [KnockDetectorStatus] = []
        source.onEvent = { event in
            switch event {
            case .impulse: rawCount += 1; subject.receiveImpulse()
            case .status(let status): statuses.append(status)
            default: break
            }
        }
        subject.onPattern = { patterns.append($0) }
        subject.start()
        source.play(knocks: 3)
        clock.advance(to: 10)
        XCTAssertEqual(rawCount, 3)
        XCTAssertEqual(patterns, [.single])
        XCTAssertEqual(source.level, 0)
        XCTAssertEqual(statuses, [.stopped, .starting, .running])
        source.stop()
        XCTAssertEqual(source.status, .stopped)
    }

    @MainActor func testSimulationStopCancelsQueuedImpulses() async {
        let clock = VirtualKnockScheduler()
        clock.deliverCancelled = true
        let source = SimulatedKnockDetector(scheduler: clock)
        var count = 0
        source.onEvent = { if case .impulse = $0 { count += 1 } }
        source.play(knocks: 3)
        source.stop()
        clock.advance(to: 1)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(source.level, 0)
    }

    @MainActor
    private func withEngine(_ body: (KnockEngine, VirtualKnockScheduler, FakeDetector, FakeDetector) -> Void) {
        let suite = "dev.local.Knock.DetectorChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = VirtualKnockScheduler()
        let first = FakeDetector()
        let second = FakeDetector()
        let engine = KnockEngine(defaults: defaults, scheduler: clock,
                                 detectorFactory: { $0 == .macBook ? first : second })
        KnockPattern.allCases.forEach { engine.setAction(.none, for: $0) }
        body(engine, clock, first, second)
        engine.stopListening()
    }

    @MainActor func testHardwareAndSimulationUseIdenticalRecognitionPath() async {
        withEngine { engine, clock, hardware, _ in
            engine.startListening()
            hardware.setLevel(0.4)
            XCTAssertEqual(engine.liveLevel, 0.4)
            for count in 1...3 {
                let start = clock.now
                for index in 0..<count {
                    clock.advance(to: start + Double(index) * 0.12)
                    hardware.emitImpulse()
                }
                clock.advance(to: start + 1)
                XCTAssertEqual(engine.lastPattern?.rawValue, count)
                XCTAssertEqual(engine.pendingKnocks, 0)
                engine.simulate(knocks: count)
                clock.advance(to: start + 2)
                XCTAssertEqual(engine.lastPattern?.rawValue, count)
                XCTAssertEqual(engine.activity.count, count * 2)
                XCTAssertFalse(engine.isSimulating)
                XCTAssertTrue(engine.isListening)
            }
        }
    }

    @MainActor func testRapidTestsReplaceAndHardwareDoesNotContaminateSimulation() async {
        withEngine { engine, clock, hardware, _ in
            clock.deliverCancelled = true
            engine.startListening()
            hardware.emitImpulse()
            engine.simulate(knocks: 3)
            clock.advance(to: 0.1)
            engine.simulate(knocks: 1)
            hardware.emitImpulse()
            clock.advance(to: 1)
            XCTAssertEqual(engine.activity.map(\.pattern), [.single])
            XCTAssertFalse(engine.isSimulating)
            hardware.emitImpulse()
            clock.advance(to: 2)
            XCTAssertEqual(engine.activity.map(\.pattern), [.single, .single])
        }
    }

    @MainActor func testEngineStopAndModeSwitchRejectStaleEvents() async {
        withEngine { engine, clock, first, second in
            clock.deliverCancelled = true
            engine.startListening()
            engine.startListening()
            XCTAssertEqual(first.starts, 1)
            let stale = first.onEvent
            first.emitImpulse()
            engine.mode = .trackpad
            XCTAssertEqual(first.stops, 1)
            XCTAssertEqual(second.starts, 1)
            stale?(.impulse)
            stale?(.error(.init(message: "Old error")))
            clock.advance(to: 1)
            XCTAssertTrue(engine.activity.isEmpty)
            XCTAssertNil(engine.permissionMessage)
            engine.simulate(knocks: 3)
            engine.stopListening()
            clock.advance(to: 2)
            XCTAssertTrue(engine.activity.isEmpty)
            XCTAssertFalse(engine.isListening)
            XCTAssertFalse(engine.isSimulating)
            XCTAssertEqual(engine.pendingKnocks, 0)
            XCTAssertEqual(engine.liveLevel, 0)
            XCTAssertEqual(engine.detectorStatus, .stopped)
        }
    }

    @MainActor func testPendingStartCanBeCancelledAndErrorsAreExposed() async {
        withEngine { engine, clock, first, _ in
            first.remainsStarting = true
            engine.startListening()
            XCTAssertEqual(engine.detectorStatus, .starting)
            let stale = first.onEvent
            engine.toggleListening()
            stale?(.status(.running))
            XCTAssertEqual(engine.detectorStatus, .stopped)
            XCTAssertFalse(engine.isListening)
            first.remainsStarting = false
            engine.startListening()
            first.emitImpulse()
            first.fail("Test permission failure")
            clock.advance(to: 1)
            XCTAssertEqual(engine.permissionMessage, "Test permission failure")
            XCTAssertEqual(first.lastError?.message, "Test permission failure")
            XCTAssertEqual(engine.detectorStatus, .failed)
            XCTAssertFalse(engine.isListening)
            XCTAssertTrue(engine.activity.isEmpty)
        }
    }

    @MainActor func testHardwareBecomesReadyAfterSimulationCompletesDuringStartup() async {
        withEngine { engine, clock, first, _ in
            first.remainsStarting = true
            engine.startListening()
            engine.simulate(knocks: 1)
            clock.advance(to: 1)
            XCTAssertFalse(engine.isListening)
            first.setStatus(.running)
            first.emitImpulse()
            clock.advance(to: 2)
            XCTAssertEqual(engine.activity.map(\.pattern), [.single, .single])
            XCTAssertTrue(engine.isListening)
        }
    }

    @MainActor func testDetectionCheckRecordsHardwareWithoutRunningActionsOrSimulation() async {
        withEngine { engine, clock, first, _ in
            engine.setAction(.showText, for: .single)
            engine.beginDetectionCheck()
            engine.startListening()
            engine.simulate(knocks: 3)
            XCTAssertFalse(engine.isSimulating)
            first.emitImpulse()
            clock.advance(to: 1)
            XCTAssertEqual(engine.checkCounts[.single], 1)
            XCTAssertNil(engine.reaction)
            XCTAssertTrue(engine.activity.isEmpty)
            engine.endDetectionCheck()
            XCTAssertFalse(engine.isListening)
            XCTAssertFalse(engine.isDetectionCheck)
        }
    }

    @MainActor func testPausedSimulationAndModeChangeCancellation() async {
        withEngine { engine, clock, first, second in
            engine.simulate(knocks: 2)
            clock.advance(to: 1)
            XCTAssertEqual(engine.activity.map(\.pattern), [.double])
            XCTAssertFalse(engine.isListening)
            XCTAssertEqual(first.starts + second.starts, 0)
            engine.simulate(knocks: 3)
            engine.mode = .trackpad
            clock.advance(to: 2)
            XCTAssertEqual(engine.activity.count, 1)
            XCTAssertFalse(engine.isSimulating)
            XCTAssertEqual(first.starts + second.starts, 0)
        }
    }
    @MainActor func testMeterUpdatesDoNotInvalidateWholeAppState() async {
        withEngine { engine, _, hardware, _ in
            engine.startListening()
            var appUpdates = 0
            var meterUpdates = 0
            let appToken = engine.objectWillChange.sink { appUpdates += 1 }
            let meterToken = engine.diagnostics.level.objectWillChange.sink { meterUpdates += 1 }
            for index in 1...1000 { hardware.setLevel(Double(index) / 1000) }
            XCTAssertEqual(appUpdates, 0, "Meter updates must not redraw the root, dashboard, or menu bar")
            XCTAssertEqual(meterUpdates, 1000)
            XCTAssertEqual(engine.liveLevel, 1)
            hardware.setLevel(1)
            XCTAssertEqual(meterUpdates, 1000, "An unchanged reading must not publish again")
            withExtendedLifetime((appToken, meterToken)) {}
        }
    }

}
