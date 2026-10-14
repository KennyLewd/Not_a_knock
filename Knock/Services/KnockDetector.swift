import Foundation

enum KnockDetectorStatus: Equatable {
    case stopped, starting, running, failed
}

struct KnockDetectorFailure: Error, Equatable {
    let message: String
}

enum KnockDetectorEvent {
    case level(Double)
    case status(KnockDetectorStatus)
    case impulse
    case error(KnockDetectorFailure)
}

/// Events are ordered on the main actor. Impulses are raw: grouping and debounce
/// belong exclusively to KnockSequenceRecognizer. Level is normalized to 0...1.
@MainActor
protocol KnockDetector: AnyObject {
    var level: Double { get }
    var status: KnockDetectorStatus { get }
    var lastError: KnockDetectorFailure? { get }
    var onEvent: ((KnockDetectorEvent) -> Void)? { get set }
    func start()
    func stop()
}

@MainActor
class KnockDetectorSource: KnockDetector {
    private(set) var level: Double = 0
    private(set) var status: KnockDetectorStatus = .stopped
    private(set) var lastError: KnockDetectorFailure?
    var onEvent: ((KnockDetectorEvent) -> Void)?
    private(set) var generation = 0

    func start() {
        generation += 1
        lastError = nil
        setStatus(.starting)
    }

    func stop() {
        generation += 1
        setLevel(0)
        setStatus(.stopped)
    }

    func setLevel(_ value: Double) {
        level = value.isFinite ? min(1, max(0, value)) : 0
        onEvent?(.level(level))
    }

    func setStatus(_ value: KnockDetectorStatus) {
        status = value
        onEvent?(.status(value))
    }

    func emitImpulse() {
        guard status == .running else { return }
        onEvent?(.impulse)
    }

    func fail(_ message: String) {
        let failure = KnockDetectorFailure(message: message)
        lastError = failure
        setLevel(0)
        setStatus(.failed)
        onEvent?(.error(failure))
    }
}

@MainActor
final class SimulatedKnockDetector: KnockDetectorSource {
    private let scheduler: any KnockScheduler
    private var scheduled: [KnockScheduledTask] = []
    let impulseSpacing: TimeInterval

    init(scheduler: any KnockScheduler, impulseSpacing: TimeInterval = 0.12) {
        precondition(impulseSpacing.isFinite && impulseSpacing > 0)
        self.scheduler = scheduler
        self.impulseSpacing = impulseSpacing
    }

    override func start() {
        guard status != .running else { return }
        super.start()
        setStatus(.running)
    }

    override func stop() {
        scheduled.forEach { $0.cancel() }
        scheduled.removeAll()
        super.stop()
    }

    /// A new test replaces unfinished simulated input. It never bypasses debounce.
    func play(knocks: Int) {
        stop()
        start()
        let expected = generation
        let count = min(3, max(1, knocks))
        setLevel(1)
        emitImpulse()
        for index in 1..<count {
            scheduled.append(scheduler.schedule(after: Double(index) * impulseSpacing) { [weak self] in
                guard let self, self.generation == expected, self.status == .running else { return }
                self.setLevel(1)
                self.emitImpulse()
            })
        }
        scheduled.append(scheduler.schedule(after: Double(count - 1) * impulseSpacing + 0.18) { [weak self] in
            guard let self, self.generation == expected else { return }
            self.setLevel(0)
        })
    }
}
