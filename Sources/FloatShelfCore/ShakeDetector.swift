import Foundation

/// Tunable parameters for shake recognition. All distances are in AppKit
/// points (resolution independent), all times in seconds.
public struct ShakeConfig: Sendable, Equatable, Codable {
    /// Minimum horizontal travel of one swing; smaller jitter is ignored.
    public var minSwingDistance: Double
    /// Number of horizontal direction reversals required to trigger.
    public var requiredReversals: Int
    /// All counted reversals must fall inside this sliding window.
    public var timeWindow: Double
    /// Reject the gesture if total |dy| exceeds this fraction of total |dx|
    /// within the window (filters diagonal strokes and circles).
    public var maxVerticalRatio: Double
    /// Minimum time between two triggers.
    public var cooldown: Double
    /// A pause longer than this between samples restarts motion tracking.
    public var maxSampleGap: Double

    public init(
        minSwingDistance: Double = 30,
        requiredReversals: Int = 3,
        timeWindow: Double = 0.6,
        maxVerticalRatio: Double = 0.6,
        cooldown: Double = 1.0,
        maxSampleGap: Double = 0.25
    ) {
        self.minSwingDistance = minSwingDistance
        self.requiredReversals = max(1, requiredReversals)
        self.timeWindow = timeWindow
        self.maxVerticalRatio = maxVerticalRatio
        self.cooldown = cooldown
        self.maxSampleGap = maxSampleGap
    }

    public static let `default` = ShakeConfig()

    public enum Sensitivity: String, Sendable, CaseIterable, Codable {
        case low, medium, high
    }

    /// Presets: higher sensitivity = shorter swings and fewer reversals.
    public static func preset(_ sensitivity: Sensitivity) -> ShakeConfig {
        switch sensitivity {
        case .low: ShakeConfig(minSwingDistance: 45, requiredReversals: 4, timeWindow: 0.7)
        case .medium: .default
        case .high: ShakeConfig(minSwingDistance: 20, requiredReversals: 2, timeWindow: 0.6)
        }
    }
}

/// Recognises a rapid left-right "shake" from a stream of pointer samples.
/// Pure value type: no AppKit, no clocks; the caller supplies timestamps.
public struct ShakeDetector: Sendable {
    public struct Sample: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var t: Double
    }

    public var config: ShakeConfig

    private var needsAnchor = true
    private var anchorX = 0.0
    private var direction = 0  // -1 left, +1 right, 0 unknown
    private var extremeX = 0.0
    private var extremeTime = 0.0
    private var reversalTimes: [Double] = []
    private var recent: [Sample] = []
    private var lastSampleTime: Double?
    private var lastTriggerTime: Double?

    public init(config: ShakeConfig = .default) {
        self.config = config
    }

    /// Reversals currently inside the window (diagnostics).
    public var currentReversalCount: Int { reversalTimes.count }

    /// Clears motion state but keeps the cooldown clock.
    public mutating func resetMotion() {
        needsAnchor = true
        direction = 0
        reversalTimes.removeAll()
        recent.removeAll()
        lastSampleTime = nil
    }

    /// Clears everything including the cooldown.
    public mutating func reset() {
        resetMotion()
        lastTriggerTime = nil
    }

    /// Feeds one sample. Returns `true` exactly when a shake is recognised.
    public mutating func addSample(x: Double, y: Double, time: Double) -> Bool {
        if let last = lastSampleTime, time - last > config.maxSampleGap || time < last {
            resetMotion()
        }
        lastSampleTime = time
        recent.append(Sample(x: x, y: y, t: time))
        recent.removeAll { time - $0.t > config.timeWindow }

        if needsAnchor {
            needsAnchor = false
            anchorX = x
            return false
        }

        if direction == 0 {
            let d = x - anchorX
            if abs(d) >= config.minSwingDistance {
                direction = d > 0 ? 1 : -1
                extremeX = x
                extremeTime = time
            }
            return false
        }

        if Double(direction) * (x - extremeX) > 0 {
            extremeX = x
            extremeTime = time
        } else if abs(x - extremeX) >= config.minSwingDistance {
            reversalTimes.append(extremeTime)
            direction = -direction
            extremeX = x
            extremeTime = time
        }

        reversalTimes.removeAll { time - $0 > config.timeWindow }
        guard reversalTimes.count >= config.requiredReversals else { return false }

        let (sumDX, sumDY) = pathLengths()
        guard sumDX > 0, sumDY <= config.maxVerticalRatio * sumDX else { return false }

        if let lt = lastTriggerTime, time - lt < config.cooldown {
            reversalTimes.removeAll()
            return false
        }
        lastTriggerTime = time
        reversalTimes.removeAll()
        return true
    }

    private func pathLengths() -> (Double, Double) {
        guard recent.count > 1 else { return (0, 0) }
        var dx = 0.0
        var dy = 0.0
        for i in 1..<recent.count {
            dx += abs(recent[i].x - recent[i - 1].x)
            dy += abs(recent[i].y - recent[i - 1].y)
        }
        return (dx, dy)
    }
}
