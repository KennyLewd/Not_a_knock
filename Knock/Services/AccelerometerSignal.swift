import Foundation

struct AccelerationSample {
    let x: Double
    let y: Double
    let z: Double

    /// Experimental Apple SPU format, independently implemented from documented
    /// observations in olvvier/apple-silicon-accelerometer. No private symbols.
    static func decode(_ bytes: UnsafeBufferPointer<UInt8>) -> Self? {
        guard bytes.count == 22 else { return nil }
        func axis(_ offset: Int) -> Double {
            let bits = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
            return Double(Int32(bitPattern: bits)) / 65536
        }
        let result = Self(x: axis(6), y: axis(10), z: axis(14))
        guard abs(result.x) <= 16, abs(result.y) <= 16, abs(result.z) <= 16 else { return nil }
        return result
    }
}

struct AccelerometerSignal {
    /// An impact reaches full amplitude within a sample or two; an arm lifting the
    /// Mac cannot ramp faster than tens of milliseconds. Requiring the level to come
    /// almost straight out of quiet is what separates a light tap from a gentle
    /// lift, which are otherwise identical once both are brief and small.
    static let riseWindow = 0.012
    /// A zero crossing during ringing lasts only a few samples. Require an
    /// actual quiet interval before another impact may start, independently of
    /// the user's minimum tap spacing (cooldown).
    static let settlingWindow = 0.03
    var threshold = 0.025
    var cooldown = 0.12
    /// Resting vibration of the surface, as the 99th percentile measured by
    /// calibration. The quiet floor is derived from this rather than from the
    /// threshold alone: scaling the floor with sensitivity used to push it below
    /// the desk's own noise at high sensitivity, so the level never read as quiet,
    /// impacts never completed, and taps were silently dropped — worst for the
    /// lighter second and third taps of a sequence.
    var noiseFloor = 0.0

    /// Never below a fixed fraction of the threshold, never above the headroom an
    /// impact needs to clear the threshold itself.
    var quietFloor: Double {
        min(max(threshold * 0.35, noiseFloor * 1.5), threshold * 0.8)
    }
    private var gravity: AccelerationSample?
    private var lastTime: Double?
    private var startTime: Double?
    private var onset: Double?
    private var lastQuiet: Double?
    private var quietSince: Double?
    private var vibrationEnvelope = 0.0
    private var lastTap = -Double.infinity
    private var armed = true

    /// Start a fresh trial without relearning gravity or changing sensitivity.
    /// Require a return to quiet before an impact crossing the reset can arm again.
    mutating func discardPendingImpact() {
        onset = nil
        lastQuiet = nil
        quietSince = nil
        armed = false
    }

    mutating func process(_ sample: AccelerationSample, at time: Double) -> (level: Double, tap: Bool) {
        guard time.isFinite, sample.x.isFinite, sample.y.isFinite, sample.z.isFinite else { return (0, false) }
        guard let previousTime = lastTime, let baseline = gravity else {
            gravity = sample; lastTime = time; startTime = time
            return (0, false)
        }
        guard time > previousTime else { return (0, false) }
        let dt = time - previousTime
        if dt > 0.5 {
            let measuredNoise = noiseFloor
            self = Self(threshold: threshold, cooldown: cooldown)
            noiseFloor = measuredNoise
            return process(sample, at: time)
        }
        lastTime = time
        let dx = sample.x - baseline.x, dy = sample.y - baseline.y, dz = sample.z - baseline.z
        let level = sqrt(dx * dx + dy * dy + dz * dz)
        // Preserve recent peak strength across zero crossings. A new impact can
        // arrive before a long tail is quiet, but must distinctly exceed that
        // tail rather than merely cross the fixed sensitivity threshold again.
        // The envelope is a peak tracker, so a decaying vibration can never exceed
        // it — only a genuinely new impact can. The margin therefore only has to
        // clear sample-to-sample decay and noise, not the ringing itself. 1.8x
        // demanded a second tap roughly as hard as the first, which lost the
        // light, fast doubles and triples this is meant to recognize.
        let previousEnvelope = vibrationEnvelope * exp(-dt / 0.12)
        let renewedImpact = previousEnvelope >= quietFloor
            && level >= previousEnvelope * 1.20
            && time - lastTap <= 0.5
        vibrationEnvelope = max(level, previousEnvelope)
        let alpha = 1 - exp(-dt / 0.20)
        gravity = AccelerationSample(x: baseline.x + alpha * dx, y: baseline.y + alpha * dy, z: baseline.z + alpha * dz)
        guard time - (startTime ?? time) >= 0.3 else { return (level, false) }
        if level < quietFloor {
            lastQuiet = time
            if quietSince == nil { quietSince = time }
            let tap = onset.map { time - $0 <= 0.08 } ?? false
            if tap { lastTap = onset! }
            onset = nil
            armed = time - (quietSince ?? time) >= Self.settlingWindow
            return (level, tap)
        }
        quietSince = nil
        if let onset, time - onset > 0.08 { self.onset = nil }
        let roseFromQuiet = armed && lastQuiet.map { time - $0 <= Self.riseWindow } == true
        if onset == nil, level >= threshold, time - lastTap >= cooldown,
           roseFromQuiet || renewedImpact {
            onset = time; armed = false
        }
        return (level, false)
    }

    init(threshold: Double = 0.025, cooldown: Double = 0.12) {
        self.threshold = threshold; self.cooldown = cooldown
    }
}

enum AccelerometerCalibration: Equatable {
    case idle, measuring(Double), proposed(Double), failed(String)
}

struct AccelerometerSnapshot {
    var calibration: AccelerometerCalibration = .idle
    var threshold = 0.025
    var dynamicG = 0.0
    var sampleRate = 0.0
    var samples = 0
    var impulses = 0
    var ignoredTyping = 0
    var ignoredPointer = 0
    var seconds = 0.0
}
