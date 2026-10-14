import Foundation
import AppKit
import IOKit
import IOKit.hid

/// The input boundary lets recovery tests exercise the real detector lifecycle
/// without opening hardware or granting permissions.
protocol AccelerometerInputConnection: AnyObject {
    @MainActor func activate(sample: @escaping @MainActor (AccelerationSample) -> Void,
                             failure: @escaping @MainActor (String) -> Void)
    @MainActor func close()
    @MainActor func recoverIdleSensor() throws -> Bool
}

extension AccelerometerInputConnection {
    @MainActor func recoverIdleSensor() throws -> Bool { false }
}

/// Owns an exclusive callback buffer, not an exclusive sensor connection.
/// Created, scheduled, and torn down on the main run loop by the detector.
private final class AccelerometerHIDSession: AccelerometerInputConnection {
    let device: IOHIDDevice
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    var sample: (@MainActor (AccelerationSample) -> Void)?
    var failure: (@MainActor (String) -> Void)?
    private var scheduled = false
    private var closed = false
    private var activationDriver: io_service_t = 0
    private var originalProperties: [(String, CFTypeRef?)] = []

    init(device: IOHIDDevice) { self.device = device }

    @MainActor static func open() throws -> AccelerometerHIDSession {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDevice"), &iterator)
        guard result == kIOReturnSuccess else { throw KnockDetectorFailure(message: "macOS couldn't list the accelerometer. Try reopening Knock.") }
        defer { IOObjectRelease(iterator) }
        var selected: IOHIDDevice?
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            func number(_ key: String) -> Int {
                (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue ?? 0
            }
            if number("PrimaryUsagePage") == 0xff00 && number("PrimaryUsage") == 3 {
                selected = IOHIDDeviceCreate(kCFAllocatorDefault, service)
                break
            }
        }
        guard let device = selected else { throw KnockDetectorFailure(message: "No supported built-in accelerometer was found. Use Trackpad mode on this Mac.") }
        let opened = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard opened == kIOReturnSuccess else {
            throw KnockDetectorFailure(message: String(format: "macOS denied accelerometer access (0x%08x). Check Input Monitoring for Knock, then quit and reopen it. If access remains denied, use Trackpad mode.", opened))
        }
        // 800 Hz is advertised by this driver. Correcting the previous 125 Hz
        // request did not fix cold-start silence; recovery below handles that.
        _ = IOHIDDeviceSetProperty(device, "ReportInterval" as CFString, NSNumber(value: 1250))
        return AccelerometerHIDSession(device: device)
    }

    @MainActor func activate(sample: @escaping @MainActor (AccelerationSample) -> Void,
                             failure: @escaping @MainActor (String) -> Void) {
        self.sample = sample
        self.failure = failure
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, _, _, report, length in
            guard let context else { return }
            let session = Unmanaged<AccelerometerHIDSession>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                guard result == kIOReturnSuccess else { session.failure?("Accelerometer report failed."); return }
                guard let value = AccelerationSample.decode(UnsafeBufferPointer(start: report, count: max(0, length))) else {
                    session.failure?("The accelerometer report format is unsupported on this Mac."); return
                }
                session.sample?(value)
            }
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        scheduled = true
    }

    @MainActor func close() { tearDown() }

    /// User-authorized experimental activation, limited to the accelerometer.
    /// Invoked once, only if the opened connection has delivered no samples.
    @MainActor func recoverIdleSensor() throws -> Bool {
        guard !closed, activationDriver == 0 else { return false }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &iterator) == kIOReturnSuccess else {
            throw KnockDetectorFailure(message: "The accelerometer activation service is unavailable.")
        }
        defer { IOObjectRelease(iterator) }
        var matches: [io_service_t] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            func value(_ key: String) -> CFTypeRef? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            if (value("PrimaryUsagePage") as? NSNumber)?.intValue == 0xff00,
               (value("PrimaryUsage") as? NSNumber)?.intValue == 3,
               (value("Product") as? String) == "accel" {
                matches.append(service)
            } else { IOObjectRelease(service) }
        }
        guard matches.count == 1 else {
            matches.forEach { IOObjectRelease($0) }
            throw KnockDetectorFailure(message: "Knock couldn't identify a unique accelerometer to activate.")
        }
        activationDriver = matches[0]
        let changes = [("SensorPropertyReportingState", 1), ("SensorPropertyPowerState", 1), ("ReportInterval", 1250)]
        let originals = changes.map { key, _ in
            IORegistryEntryCreateCFProperty(activationDriver, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        for (index, change) in changes.enumerated() {
            let (key, value) = change
            originalProperties.append((key, originals[index]))
            let result = IORegistryEntrySetCFProperty(activationDriver, key as CFString, NSNumber(value: value))
            guard result == kIOReturnSuccess else {
                throw KnockDetectorFailure(message: String(format: "macOS couldn't activate the accelerometer (0x%08x).", result))
            }
        }
        return true
    }

    private func tearDown() {
        guard !closed else { return }
        closed = true
        if scheduled {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
        }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if activationDriver != 0 {
            // Never guess a prior power state or turn off a shared sensor blindly.
            // Absent properties cannot be restored; a reboot may be required.
            for (key, original) in originalProperties.reversed() {
                if let original {
                    let result = IORegistryEntrySetCFProperty(activationDriver, key as CFString, original)
                    if result != kIOReturnSuccess { NSLog("Knock sensor restoration failed for %@: 0x%08x", key, result) }
                }
            }
            originalProperties.removeAll()
            IOObjectRelease(activationDriver)
            activationDriver = 0
        }
    }

    deinit { tearDown(); buffer.deallocate() }
}

@MainActor
final class AccelerometerKnockDetector: KnockDetectorSource {
    /// A keystroke or trackpad click shakes the chassis exactly like a fingertip
    /// tap, so the two are not separable by waveform. Knock instead drops impulses
    /// that land while the user is demonstrably still typing or clicking.
    static let inputSettleWindow = 0.3
    /// Tap-to-click posts its click only after the trackpad driver has recognized
    /// the gesture, which is later than the fingertip's impact on the glass. A
    /// backward-looking check cannot see an event that does not exist yet, so every
    /// impulse is held this long and re-checked before it counts as a knock. The
    /// hold is uniform, so it delays knocks without disturbing pattern grouping.
    static let inputVetoWindow = 0.15
    var sensitivity = 0.5 { didSet { configure() } }
    var cooldown = 0.12 { didSet { configure() } }
    var baseThreshold = 0.025 { didSet { configure() } }
    var ignoreWhileTyping = true
    var ignoreWhileUsingTrackpad = true
    var onUpdate: ((AccelerometerSnapshot) -> Void)?
    var onThreshold: ((Double) -> Void)?
    private(set) var snapshot = AccelerometerSnapshot()
    private var session: (any AccelerometerInputConnection)?
    private var signal = AccelerometerSignal()
    private var watchdog: KnockScheduledTask?
    private let scheduler: any KnockScheduler
    private let openInput: @MainActor () throws -> any AccelerometerInputConnection
    private let inputActivity: any InputActivityMonitor
    private let workspaceNotifications: NotificationCenter
    private var sleepObserver: NSObjectProtocol?
    private var started = 0.0
    private var lastSample = 0.0
    private var lastUI = 0.0
    private var attemptedActivation = false
    private var calibrationStart: Double?
    private var noise: [Double] = []
    private var heldImpulses: [Int: KnockScheduledTask] = [:]
    private var heldImpulseID = 0

    init(scheduler: (any KnockScheduler)? = nil,
         inputFactory: (@MainActor () throws -> any AccelerometerInputConnection)? = nil,
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
         inputActivity: (any InputActivityMonitor)? = nil) {
        self.scheduler = scheduler ?? MainKnockScheduler()
        self.openInput = inputFactory ?? { try AccelerometerHIDSession.open() }
        self.workspaceNotifications = workspaceNotifications
        self.inputActivity = inputActivity ?? SystemInputActivityMonitor()
        super.init()
    }

    private enum IgnoredInput { case typing, pointer }

    private func holdImpulse() {
        let expected = generation
        heldImpulseID += 1
        let id = heldImpulseID
        heldImpulses[id] = scheduler.schedule(after: Self.inputVetoWindow) { [weak self] in
            guard let self else { return }
            defer { self.heldImpulses[id] = nil }
            guard self.generation == expected, self.status == .running,
                  self.heldImpulses[id] != nil else { return }
            switch self.ignoredInput() {
            case .typing: self.snapshot.ignoredTyping += 1
            case .pointer: self.snapshot.ignoredPointer += 1
            case nil:
                self.snapshot.impulses += 1
                self.emitImpulse()
            }
        }
    }

    /// Queried once per detected impulse, never per sample.
    private func ignoredInput() -> IgnoredInput? {
        if ignoreWhileTyping, inputActivity.secondsSinceKeyboard() < Self.inputSettleWindow { return .typing }
        if ignoreWhileUsingTrackpad, inputActivity.secondsSincePointer() < Self.inputSettleWindow { return .pointer }
        return nil
    }

    private func configure() {
        signal.threshold = baseThreshold * pow(2, 1 - 2 * min(1, max(0, sensitivity)))
        signal.cooldown = min(0.4, max(0.08, cooldown))
        // Calibration proposes p99 resting noise * 4, so the measured noise is
        // recoverable from the saved threshold without storing it separately.
        signal.noiseFloor = baseThreshold / 4
        snapshot.threshold = signal.threshold
        onUpdate?(snapshot)
    }

    override func start() {
        guard status != .running && status != .starting else { return }
        super.start()
        let expected = generation
        let connection: any AccelerometerInputConnection
        do { connection = try openInput() }
        catch {
            fail((error as? KnockDetectorFailure)?.message ?? "The accelerometer couldn't start. Try reopening Knock.")
            return
        }
        session = connection
        attemptedActivation = false
        signal = AccelerometerSignal()
        snapshot = AccelerometerSnapshot()
        configure()
        started = scheduler.now; lastSample = started; lastUI = started
        sleepObserver = workspaceNotifications.addObserver(forName: NSWorkspace.willSleepNotification,
                                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == expected else { return }
                self.stop()
                self.fail("Tap detection paused when your Mac went to sleep. Start detection again when you're ready.")
            }
        }
        connection.activate(sample: { [weak self] value in
            guard let self, self.generation == expected else { return }
            self.consume(value)
        }, failure: { [weak self] message in
            // Leave the report callback before releasing its device and buffer.
            DispatchQueue.main.async {
                guard let self, self.generation == expected else { return }
                self.stop(); self.fail(message)
            }
        })
        checkDelivery(expected: expected)
    }

    private func checkDelivery(expected: Int) {
        watchdog = scheduler.schedule(after: 2) { [weak self] in
            guard let self, self.generation == expected else { return }
            if self.scheduler.now - self.lastSample >= 1.5 {
                if self.status == .starting && !self.attemptedActivation {
                    self.attemptedActivation = true
                    do {
                        if try self.session?.recoverIdleSensor() == true {
                            self.started = self.scheduler.now
                            self.lastSample = self.started
                            self.checkDelivery(expected: expected)
                            return
                        }
                    } catch {
                        self.stop()
                        self.fail((error as? KnockDetectorFailure)?.message ?? "The accelerometer couldn't be activated.")
                        return
                    }
                }
                self.stop()
                self.fail("The accelerometer stopped or couldn't begin sending readings. Start detection to retry. If this continues, restart your Mac or use Trackpad mode.")
            } else { self.checkDelivery(expected: expected) }
        }
    }

    override func stop() {
        watchdog?.cancel(); watchdog = nil
        discardPendingInput()
        if let sleepObserver { workspaceNotifications.removeObserver(sleepObserver) }
        sleepObserver = nil
        session?.close()
        session = nil
        calibrationStart = nil; noise.removeAll()
        snapshot.calibration = .idle; snapshot.dynamicG = 0; snapshot.sampleRate = 0
        onUpdate?(snapshot)
        super.stop()
    }

    func resetMetrics() {
        discardPendingInput()
        snapshot.impulses = 0; snapshot.samples = 0; snapshot.seconds = 0
        snapshot.sampleRate = 0
        snapshot.ignoredTyping = 0; snapshot.ignoredPointer = 0
        started = scheduler.now
        onUpdate?(snapshot)
    }

    func beginCalibration() {
        guard status == .running else { return }
        discardPendingInput()
        calibrationStart = scheduler.now
        noise.removeAll(keepingCapacity: true)
        snapshot.calibration = .measuring(0)
        onUpdate?(snapshot)
    }

    func cancelCalibration() {
        discardPendingInput()
        calibrationStart = nil; noise.removeAll()
        snapshot.calibration = .idle
        signal = AccelerometerSignal(); configure()
    }

    private func discardPendingInput() {
        heldImpulses.values.forEach { $0.cancel() }
        heldImpulses.removeAll()
        signal.discardPendingImpact()
    }

    func applyCalibration() {
        guard case .proposed(let value) = snapshot.calibration else { return }
        baseThreshold = value
        onThreshold?(value)
        cancelCalibration()
    }

    private func consume(_ sample: AccelerationSample) {
        let now = scheduler.now
        lastSample = now
        if status == .starting { setStatus(.running) }
        guard status == .running else { return }
        let result = signal.process(sample, at: now)
        snapshot.samples += 1
        snapshot.seconds = now - started
        snapshot.sampleRate = Double(snapshot.samples) / max(0.001, snapshot.seconds)
        snapshot.dynamicG = result.level
        if let begin = calibrationStart {
            // Bound storage even when firmware ignores the requested sample rate.
            if noise.count < 10_000 { noise.append(result.level) }
            let progress = min(1, (now - begin) / 3)
            snapshot.calibration = .measuring(progress)
            if progress >= 1 {
                calibrationStart = nil
                let sorted = noise.sorted()
                let proposed = max(0.008, sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))] * 4)
                snapshot.calibration = proposed <= 0.4 ? .proposed(proposed) : .failed("Too much movement. Keep the Mac still and measure again.")
                noise.removeAll()
            }
        } else if snapshot.calibration == .idle && result.tap {
            switch ignoredInput() {
            case .typing: snapshot.ignoredTyping += 1
            case .pointer: snapshot.ignoredPointer += 1
            case nil: holdImpulse()
            }
        }
        // Keep recognition at the full sensor rate, but avoid redrawing the entire
        // SwiftUI environment while this background utility is not active.
        if now - lastUI >= 0.25 {
            lastUI = now
            guard NSApplication.shared.isActive else { return }
            setLevel(result.level / max(snapshot.threshold, 0.001))
            onUpdate?(snapshot)
        }
    }
}
