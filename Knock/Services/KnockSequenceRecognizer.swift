import Foundation

final class KnockScheduledTask {
    private let cancelWork: () -> Void
    init(cancel: @escaping () -> Void) { cancelWork = cancel }
    func cancel() { cancelWork() }
    deinit { cancelWork() }
}

@MainActor
protocol KnockScheduler {
    var now: TimeInterval { get }
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> KnockScheduledTask
}

@MainActor
final class MainKnockScheduler: KnockScheduler {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> KnockScheduledTask {
        let work = DispatchWorkItem { action() }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return KnockScheduledTask { work.cancel() }
    }
}

@MainActor
final class KnockSequenceRecognizer {
    struct Configuration {
        var debounce: TimeInterval = 0.075
        var sequenceTimeout: TimeInterval = 0.46
        var maximumCount: Int = 3
    }

    private(set) var configuration: Configuration
    private let scheduler: any KnockScheduler
    private var timeout: KnockScheduledTask?
    private var lastAccepted: TimeInterval?
    private var deadline: TimeInterval?
    private var revision = 0
    private(set) var isRunning = false
    private(set) var pendingCount = 0
    var onCountChange: ((Int) -> Void)?
    var onPattern: ((KnockPattern) -> Void)?

    init(configuration: Configuration = .init(), scheduler: any KnockScheduler) {
        precondition(configuration.debounce.isFinite && configuration.debounce >= 0)
        precondition(configuration.sequenceTimeout.isFinite && configuration.sequenceTimeout > configuration.debounce)
        precondition((1...3).contains(configuration.maximumCount))
        self.configuration = configuration
        self.scheduler = scheduler
    }

    func start() {
        stop()
        isRunning = true
    }

    func setSequenceTimeout(_ value: TimeInterval) {
        guard value.isFinite, value > configuration.debounce, value != configuration.sequenceTimeout else { return }
        let resume = isRunning
        stop()
        configuration.sequenceTimeout = value
        if resume { start() }
    }

    func stop() {
        isRunning = false
        resetSequence()
    }

    func receiveImpulse() {
        guard isRunning else { return }
        let now = scheduler.now
        // Resolve an expired sequence even if the main queue delivered its timer late.
        if let deadline, now >= deadline { finish() }
        guard isRunning else { return }
        if let lastAccepted, now - lastAccepted < configuration.debounce { return }
        // Saturation never postpones completion indefinitely under continuous noise.
        guard pendingCount < configuration.maximumCount else { return }
        lastAccepted = now
        pendingCount += 1
        deadline = now + configuration.sequenceTimeout
        revision += 1
        let expected = revision
        timeout?.cancel()
        timeout = scheduler.schedule(after: configuration.sequenceTimeout) { [weak self] in
            guard let self, self.isRunning, self.revision == expected else { return }
            self.finish()
        }
        onCountChange?(pendingCount)
    }

    private func finish() {
        guard let pattern = KnockPattern(rawValue: pendingCount) else { return }
        resetSequence()
        onPattern?(pattern)
    }

    private func resetSequence() {
        revision += 1
        timeout?.cancel()
        timeout = nil
        lastAccepted = nil
        deadline = nil
        pendingCount = 0
        onCountChange?(0)
    }
}
