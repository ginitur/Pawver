import Foundation
import Testing
@testable import FloatShelfCore

/// Generates a triangle-wave horizontal motion: `legs` straight strokes of
/// `distance` points, each lasting `legDuration` seconds, sampled every `dt`.
/// `yFactor` adds vertical motion proportional to horizontal motion.
private func strokes(
    legs: Int, distance: Double = 80, legDuration: Double = 0.12,
    start: Double = 0, dt: Double = 0.008, yFactor: Double = 0,
    originX: Double = 500, originY: Double = 500
) -> [ShakeDetector.Sample] {
    var out: [ShakeDetector.Sample] = []
    let stepsPerLeg = max(1, Int((legDuration / dt).rounded()))
    var t = start
    var x = originX
    var y = originY
    out.append(.init(x: x, y: y, t: t))
    for leg in 0..<legs {
        let dir: Double = leg % 2 == 0 ? 1 : -1
        let stepX = dir * distance / Double(stepsPerLeg)
        for _ in 0..<stepsPerLeg {
            t += dt
            x += stepX
            y += stepX * yFactor
            out.append(.init(x: x, y: y, t: t))
        }
    }
    return out
}

private func run(_ samples: [ShakeDetector.Sample], _ detector: inout ShakeDetector) -> [Double] {
    var triggers: [Double] = []
    for s in samples where detector.addSample(x: s.x, y: s.y, time: s.t) {
        triggers.append(s.t)
    }
    return triggers
}

@Suite("ShakeDetector")
struct ShakeDetectorTests {
    @Test func fastShakeTriggersOnce() {
        var d = ShakeDetector()
        let triggers = run(strokes(legs: 4), &d)
        #expect(triggers.count == 1)
    }

    @Test func longShakeTriggersOnlyOnceBecauseOfCooldown() {
        var d = ShakeDetector()
        #expect(run(strokes(legs: 10), &d).count == 1)
    }

    @Test func slowBackAndForthDoesNotTrigger() {
        var d = ShakeDetector()
        #expect(run(strokes(legs: 6, legDuration: 0.5), &d).isEmpty)
    }

    @Test func singleSwingDoesNotTrigger() {
        var d = ShakeDetector()
        #expect(run(strokes(legs: 2), &d).isEmpty)
    }

    @Test func straightDragDoesNotTrigger() {
        var d = ShakeDetector()
        #expect(run(strokes(legs: 1, distance: 800, legDuration: 0.5), &d).isEmpty)
    }

    @Test func smallJitterDoesNotTrigger() {
        var d = ShakeDetector()
        #expect(run(strokes(legs: 12, distance: 10, legDuration: 0.05), &d).isEmpty)
    }

    @Test func diagonalBackAndForthIsRejected() {
        var d = ShakeDetector()
        #expect(run(strokes(legs: 6, yFactor: 1.0), &d).isEmpty)
    }

    @Test func slightVerticalWobbleStillTriggers() {
        var d = ShakeDetector()
        #expect(run(strokes(legs: 4, yFactor: 0.2), &d).count == 1)
    }

    @Test func fastCircleIsRejected() {
        var d = ShakeDetector()
        var samples: [ShakeDetector.Sample] = []
        let r = 50.0
        let period = 0.3
        var t = 0.0
        while t < 1.2 {
            let a = 2 * Double.pi * t / period
            samples.append(.init(x: 500 + r * cos(a), y: 500 + r * sin(a), t: t))
            t += 0.008
        }
        #expect(run(samples, &d).isEmpty)
    }

    @Test func cooldownBlocksSecondShakeThenAllowsLaterOne() {
        var d = ShakeDetector(config: ShakeConfig(cooldown: 1.0))
        var samples = strokes(legs: 4, start: 0)
        samples += strokes(legs: 4, start: 0.7)   // within cooldown
        samples += strokes(legs: 4, start: 2.5)   // after cooldown
        let triggers = run(samples, &d)
        #expect(triggers.count == 2)
        if triggers.count == 2 { #expect(triggers[1] > 2.5) }
    }

    @Test func pauseBetweenSwingsRestartsTracking() {
        var d = ShakeDetector()
        var samples = strokes(legs: 2, start: 0)
        samples += strokes(legs: 2, start: 0.6)  // gap > maxSampleGap
        #expect(run(samples, &d).isEmpty)
    }

    @Test func requiredReversalsParameterIsHonoured() {
        var strict = ShakeDetector(config: ShakeConfig(requiredReversals: 5, timeWindow: 0.8))
        #expect(run(strokes(legs: 4), &strict).isEmpty)
        var strict2 = ShakeDetector(config: ShakeConfig(requiredReversals: 5, timeWindow: 0.8))
        #expect(run(strokes(legs: 6), &strict2).count == 1)
    }

    @Test func minSwingDistanceParameterIsHonoured() {
        var d = ShakeDetector(config: ShakeConfig(minSwingDistance: 100))
        #expect(run(strokes(legs: 8, distance: 80), &d).isEmpty)
        var d2 = ShakeDetector(config: ShakeConfig(minSwingDistance: 100))
        #expect(run(strokes(legs: 4, distance: 160, legDuration: 0.12), &d2).count == 1)
    }

    @Test func timeWindowParameterIsHonoured() {
        var tight = ShakeDetector(config: ShakeConfig(timeWindow: 0.2))
        #expect(run(strokes(legs: 6, legDuration: 0.15), &tight).isEmpty)
        var loose = ShakeDetector(config: ShakeConfig(timeWindow: 0.6))
        #expect(run(strokes(legs: 6, legDuration: 0.15), &loose).count == 1)
    }

    @Test func presetsAreOrderedBySensitivity() {
        let low = ShakeConfig.preset(.low)
        let medium = ShakeConfig.preset(.medium)
        let high = ShakeConfig.preset(.high)
        #expect(low.minSwingDistance > medium.minSwingDistance)
        #expect(medium.minSwingDistance > high.minSwingDistance)
        #expect(low.requiredReversals >= medium.requiredReversals)
        #expect(medium.requiredReversals >= high.requiredReversals)
    }

    @Test func highSensitivityAcceptsShorterShake() {
        var high = ShakeDetector(config: .preset(.high))
        #expect(run(strokes(legs: 3, distance: 40), &high).count == 1)
        var low = ShakeDetector(config: .preset(.low))
        #expect(run(strokes(legs: 3, distance: 40), &low).isEmpty)
    }

    @Test func resetClearsCooldown() {
        var d = ShakeDetector()
        #expect(run(strokes(legs: 4, start: 0), &d).count == 1)
        d.reset()
        #expect(run(strokes(legs: 4, start: 0.6), &d).count == 1)
    }
}
