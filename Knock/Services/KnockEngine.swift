import SwiftUI
/// Each fast-changing readout has its own observation scope. A changing meter
/// must not invalidate the dashboard, action picker, menu bar, or other panels.
@MainActor
final class KnockReadout<Value: Equatable>: ObservableObject {
    @Published private(set) var value: Value
    init(_ value: Value) { self.value = value }
    func update(_ value: Value) {
        guard value != self.value else { return }
        self.value = value
    }
}

struct AccelerometerMetrics: Equatable {
    var seconds = 0
    var impulses = 0
    var ignoredTyping = 0
    var ignoredPointer = 0
    var threshold = 0.025
    var sampleRate = 0
}

@MainActor
final class KnockDiagnostics {
    let level = KnockReadout(0.0)
    let calibration = KnockReadout(AccelerometerCalibration.idle)
    let metrics = KnockReadout(AccelerometerMetrics())
    private(set) var snapshot = AccelerometerSnapshot()

    func update(_ value: AccelerometerSnapshot) {
        snapshot = value
        calibration.update(value.calibration)
        metrics.update(AccelerometerMetrics(seconds: Int(value.seconds), impulses: value.impulses,
                                             ignoredTyping: value.ignoredTyping,
                                             ignoredPointer: value.ignoredPointer,
                                             threshold: value.threshold, sampleRate: Int(value.sampleRate)))
    }
}

@MainActor
final class KnockEngine: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var detectorStatus: KnockDetectorStatus = .stopped
    @Published private(set) var isSimulating = false
    @Published var mode: DetectionMode = .macBook {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: "knock.mode")
            let resume = isListening || detectorStatus == .starting
            stopListening()
            if resume { startListening() }
        }
    }
    @Published var sensitivity: Double = 0.5 {
        didSet { accelerometer.sensitivity = sensitivity; defaults.set(sensitivity, forKey: "knock.accelerometer.sensitivity") }
    }
    @Published var cooldown: Double = 0.12 {
        didSet { accelerometer.cooldown = cooldown; defaults.set(cooldown, forKey: "knock.accelerometer.cooldown") }
    }
    @Published var ignoreWhileTyping = true {
        didSet {
            accelerometer.ignoreWhileTyping = ignoreWhileTyping
            defaults.set(ignoreWhileTyping, forKey: "knock.ignoreWhileTyping")
        }
    }
    @Published var ignoreWhileUsingTrackpad = true {
        didSet {
            accelerometer.ignoreWhileUsingTrackpad = ignoreWhileUsingTrackpad
            defaults.set(ignoreWhileUsingTrackpad, forKey: "knock.ignoreWhileUsingTrackpad")
        }
    }
    @Published var patternWindow: Double = 0.65 {
        didSet {
            recognizer.setSequenceTimeout(patternWindow)
            defaults.set(patternWindow, forKey: "knock.patternWindow")
        }
    }
    let diagnostics = KnockDiagnostics()
    var accelerometerSnapshot: AccelerometerSnapshot { diagnostics.snapshot }
    @Published private(set) var isDetectionCheck = false
    @Published private(set) var checkCounts: [KnockPattern: Int] = [:]
    var liveLevel: Double {
        get { diagnostics.level.value }
        set { diagnostics.level.update(newValue) }
    }
    @Published var pendingKnocks = 0
    @Published var lastPattern: KnockPattern?
    @Published var activity: [ActivityItem] = []
    @Published var reaction: ReactionKind?
    @Published var permissionMessage: String?
    @Published private(set) var actions: [KnockPattern: KnockAction] = [
        .single: .playPause,
        .double: .screenshot,
        .triple: .shockwave
    ] {
        didSet { saveActions() }
    }

    private let defaults: UserDefaults
    private let scheduler: any KnockScheduler
    private let recognizer: KnockSequenceRecognizer
    private let simulation: SimulatedKnockDetector
    private let accelerometer = AccelerometerKnockDetector()
    private let makeDetector: (DetectionMode) -> any KnockDetector
    private var detector: (any KnockDetector)?
    private var sourceRevision = 0
    private var decayWork: KnockScheduledTask?
    private var reactionWork: KnockScheduledTask?

    init(defaults: UserDefaults = .standard,
         scheduler: (any KnockScheduler)? = nil,
         configuration: KnockSequenceRecognizer.Configuration = .init(sequenceTimeout: 0.65),
         detectorFactory: ((DetectionMode) -> any KnockDetector)? = nil) {
        self.defaults = defaults
        let clock = scheduler ?? MainKnockScheduler()
        self.scheduler = clock
        recognizer = KnockSequenceRecognizer(configuration: configuration, scheduler: clock)
        simulation = SimulatedKnockDetector(scheduler: clock)
        let accelerometer = self.accelerometer
        makeDetector = detectorFactory ?? { mode in
            mode == .macBook ? accelerometer : TrackpadKnockDetector()
        }
        loadActions()
        let savedWindow = defaults.object(forKey: "knock.patternWindow") as? Double
        patternWindow = configuration.sequenceTimeout
        if let value = savedWindow, value.isFinite, (0.3...1).contains(value) { patternWindow = value }
        accelerometer.onUpdate = { [weak self] in self?.diagnostics.update($0) }
        accelerometer.onThreshold = { [weak self] value in
            self?.defaults.set(value, forKey: "knock.accelerometer.threshold")
        }
        if let value = defaults.object(forKey: "knock.accelerometer.sensitivity") as? Double, value.isFinite, (0...1).contains(value) { sensitivity = value }
        if let value = defaults.object(forKey: "knock.accelerometer.cooldown") as? Double, value.isFinite, (0.08...0.4).contains(value) { cooldown = value }
        if let value = defaults.object(forKey: "knock.accelerometer.threshold") as? Double, value.isFinite, (0.008...0.4).contains(value) {
            accelerometer.baseThreshold = value
        }
        if let value = defaults.object(forKey: "knock.ignoreWhileTyping") as? Bool { ignoreWhileTyping = value }
        if let value = defaults.object(forKey: "knock.ignoreWhileUsingTrackpad") as? Bool { ignoreWhileUsingTrackpad = value }
        if let raw = defaults.string(forKey: "knock.mode"), let saved = DetectionMode(rawValue: raw) {
            mode = saved
        }
        accelerometer.sensitivity = sensitivity
        accelerometer.cooldown = cooldown
        accelerometer.ignoreWhileTyping = ignoreWhileTyping
        accelerometer.ignoreWhileUsingTrackpad = ignoreWhileUsingTrackpad
        recognizer.setSequenceTimeout(patternWindow)
        recognizer.onCountChange = { [weak self] count in self?.pendingKnocks = count }
        recognizer.onPattern = { [weak self] pattern in self?.completeSequence(pattern) }
        simulation.onEvent = { [weak self] event in
            guard let self, self.isSimulating else { return }
            self.receiveInput(event)
        }
        if defaults.bool(forKey: "knock.detectionEnabled") { startListening() }
    }

    /// Whether detection should be running. Persisted so the app comes back the way
    /// it was left: a detector the user has to re-enable on every launch is off far
    /// more often than it is on. Only a deliberate toggle writes it — restarts,
    /// mode changes and entering a detection check must not record a preference.
    private func rememberDetectionEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: "knock.detectionEnabled")
    }

    func toggleListening() {
        if isListening || detectorStatus == .starting {
            rememberDetectionEnabled(false)
            stopListening()
        } else {
            rememberDetectionEnabled(true)
            startListening()
        }
    }

    func startListening() {
        guard !isListening && detectorStatus != .starting else { return }
        stopListening()
        permissionMessage = nil
        recognizer.start()
        let source = makeDetector(mode)
        detector = source
        let expected = sourceRevision
        source.onEvent = { [weak self] event in
            guard let self, self.sourceRevision == expected else { return }
            switch event {
            case .status(let status):
                self.detectorStatus = status
                self.isListening = status == .running
                if status == .running && !self.isSimulating && !self.recognizer.isRunning {
                    self.recognizer.start()
                }
                if status == .failed || status == .stopped {
                    if !self.isSimulating { self.resetRecognition() }
                }
            case .error(let failure):
                self.permissionMessage = failure.message
            default:
                guard !self.isSimulating, self.isListening else { return }
                self.receiveInput(event)
            }
        }
        source.start()
    }

    func stopListening() {
        sourceRevision += 1
        detector?.onEvent = nil
        detector?.stop()
        detector = nil
        simulation.stop()
        isSimulating = false
        resetRecognition()
        isListening = false
        detectorStatus = .stopped
    }

    func restartListening() {
        stopListening()
        startListening()
    }

    func simulate(knocks: Int) {
        guard !isDetectionCheck else { return }
        simulation.stop()
        resetRecognition()
        isSimulating = true
        recognizer.start()
        simulation.play(knocks: knocks)
    }

    private func resetRecognition() {
        recognizer.stop()
        decayWork?.cancel()
        decayWork = nil
        liveLevel = 0
    }

    /// Both real and simulated detectors enter the same recognizer here.
    private func receiveInput(_ event: KnockDetectorEvent) {
        switch event {
        case .level(let level): liveLevel = level
        case .impulse:
            recognizer.receiveImpulse()
            liveLevel = 1
            decayWork?.cancel()
            decayWork = scheduler.schedule(after: 0.18) { [weak self] in self?.liveLevel = 0 }
        case .status, .error: break
        }
    }

    func beginDetectionCheck() {
        stopListening()
        mode = .macBook
        isDetectionCheck = true
        checkCounts = [:]
    }

    func endDetectionCheck() {
        stopListening()
        isDetectionCheck = false
        // Leaving the tuning sheet used to stop detection outright, so the only
        // place it could be switched on was the place its results did not count.
        if defaults.bool(forKey: "knock.detectionEnabled") { startListening() }
    }

    func resetCheckCounts() {
        checkCounts = [:]
        accelerometer.resetMetrics()
        resetRecognition()
        if isListening { recognizer.start() }
    }

    func calibrateAccelerometer() {
        resetCheckCounts()
        accelerometer.beginCalibration()
    }

    func applyAccelerometerCalibration() { accelerometer.applyCalibration() }
    func cancelAccelerometerCalibration() { accelerometer.cancelCalibration() }

    func action(for pattern: KnockPattern) -> KnockAction {
        actions[pattern] ?? .none
    }

    func setAction(_ action: KnockAction, for pattern: KnockPattern) {
        actions[pattern] = action
    }

    private func completeSequence(_ pattern: KnockPattern) {
        if isSimulating {
            simulation.stop()
            isSimulating = false
            if isListening { recognizer.start() }
            else { recognizer.stop() }
        }
        lastPattern = pattern
        if isDetectionCheck {
            checkCounts[pattern, default: 0] += 1
            return
        }
        let selectedAction = action(for: pattern)
        activity.insert(ActivityItem(pattern: pattern, action: selectedAction, date: Date()), at: 0)
        activity = Array(activity.prefix(30))
        ActionRunner.shared.run(selectedAction) { [weak self] reaction in
            self?.showReaction(reaction)
        }
    }

    private func showReaction(_ kind: ReactionKind) {
        reaction = kind
        reactionWork?.cancel()
        reactionWork = scheduler.schedule(after: 1.25) { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.reaction = nil }
        }
    }

    private func saveActions() {
        let raw = Dictionary(uniqueKeysWithValues: actions.map { (String($0.key.rawValue), $0.value.rawValue) })
        defaults.set(raw, forKey: "knock.actions")
    }

    private func loadActions() {
        guard let raw = defaults.dictionary(forKey: "knock.actions") else { return }
        var restored = actions
        for (key, value) in raw {
            if let count = Int(key), let pattern = KnockPattern(rawValue: count),
               let value = value as? String, let action = KnockAction(rawValue: value) {
                restored[pattern] = action
            }
        }
        actions = restored
    }
}
