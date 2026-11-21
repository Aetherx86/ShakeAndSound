import Foundation

nonisolated public struct Vector3D: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public static let zero = Vector3D(x: 0.0, y: 0.0, z: 0.0)

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var magnitude: Double {
        hypot(hypot(x, y), z)
    }

    public var horizontalMagnitude: Double {
        hypot(x, y)
    }

    public func sanitized(limit: Double = 50_000.0) -> Vector3D {
        let bound = limit.isFinite && limit > 0 ? limit : 50_000.0
        func clean(_ v: Double) -> Double {
            guard v.isFinite else { return 0.0 }
            return min(bound, max(-bound, v))
        }
        return Vector3D(x: clean(x), y: clean(y), z: clean(z))
    }

    public static func + (lhs: Vector3D, rhs: Vector3D) -> Vector3D {
        Vector3D(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    public static func - (lhs: Vector3D, rhs: Vector3D) -> Vector3D {
        Vector3D(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    public static func * (lhs: Vector3D, scalar: Double) -> Vector3D {
        Vector3D(x: lhs.x * scalar, y: lhs.y * scalar, z: lhs.z * scalar)
    }

    public static func / (lhs: Vector3D, scalar: Double) -> Vector3D {
        guard scalar.isFinite && abs(scalar) > 1e-12 else { return .zero }
        return Vector3D(x: lhs.x / scalar, y: lhs.y / scalar, z: lhs.z / scalar)
    }
}

nonisolated public enum ShakePatternKind: String, Codable, CaseIterable, Sendable {
    case idle = "idle"
    case microTremor = "micro_tremor"
    case singleTapImpact = "single_tap_impact"
    case doubleTapImpulse = "double_tap_impulse"
    case rhythmicLateralShake = "rhythmic_lateral_shake"
    case seismicShearWave = "seismic_shear_wave"

    public var displayLabel: String {
        switch self {
        case .idle:
            return "Idle Baseline"
        case .microTremor:
            return "Ambient Micro-Tremor"
        case .singleTapImpact:
            return "Single Tap Impact"
        case .doubleTapImpulse:
            return "Double-Tap Impulse"
        case .rhythmicLateralShake:
            return "Rhythmic Lateral Shake"
        case .seismicShearWave:
            return "Seismic Shear Wave"
        }
    }
}

nonisolated public struct MotionKinematicConfig: Codable, Equatable, Sendable {
    public var gravityCutoffHz: Double
    public var highPassCutoffHz: Double
    public var staAlpha: Double
    public var ltaAlpha: Double
    public var triggerRatioThreshold: Double
    public var pgaTriggerThresholdMg: Double
    public var maxAccelerationClampMg: Double
    public var windowCapacity: Int
    public var initialGravityMg: Vector3D

    public init(
        gravityCutoffHz: Double = 0.8,
        highPassCutoffHz: Double = 0.35,
        staAlpha: Double = 0.22,
        ltaAlpha: Double = 0.015,
        triggerRatioThreshold: Double = 3.0,
        pgaTriggerThresholdMg: Double = 14.0,
        maxAccelerationClampMg: Double = 50_000.0,
        windowCapacity: Int = 64,
        initialGravityMg: Vector3D = .zero
    ) {
        self.gravityCutoffHz = gravityCutoffHz.isFinite && gravityCutoffHz > 0.01 ? min(gravityCutoffHz, 20.0) : 0.8
        self.highPassCutoffHz = highPassCutoffHz.isFinite && highPassCutoffHz >= 0.0 ? min(highPassCutoffHz, 20.0) : 0.35
        self.staAlpha = staAlpha.isFinite ? min(0.95, max(0.01, staAlpha)) : 0.22
        self.ltaAlpha = ltaAlpha.isFinite ? min(0.5, max(0.001, ltaAlpha)) : 0.015
        self.triggerRatioThreshold = triggerRatioThreshold.isFinite && triggerRatioThreshold > 1.0 ? triggerRatioThreshold : 3.0
        self.pgaTriggerThresholdMg = pgaTriggerThresholdMg.isFinite && pgaTriggerThresholdMg > 0.5 ? pgaTriggerThresholdMg : 14.0
        self.maxAccelerationClampMg = maxAccelerationClampMg.isFinite && maxAccelerationClampMg > 10.0 ? maxAccelerationClampMg : 50_000.0
        self.windowCapacity = max(8, min(512, windowCapacity))
        self.initialGravityMg = initialGravityMg.sanitized(limit: self.maxAccelerationClampMg)
    }
}

nonisolated public struct MotionKinematicFrame: Codable, Equatable, Sendable {
    public let sampleIndex: Int
    public let dt: Double
    public let rawAccelerationMg: Vector3D
    public let isolatedGravityMg: Vector3D
    public let linearAccelerationMg: Vector3D
    public let dynamicMagnitudeMg: Double
    public let jerkMgPerSec: Vector3D
    public let jerkMagnitudeMgPerSec: Double
    public let velocityEstimateMmPerSec: Vector3D
    public let staLtaRatio: Double
    public let ariasIntensityMmPerSec: Double
    public let zeroCrossingRateHz: Double
    public let dominantFrequencyHz: Double
    public let crestFactor: Double
    public let pattern: ShakePatternKind
    public let isTriggered: Bool
}

nonisolated public struct MotionTraceSummary: Codable, Equatable, Sendable {
    public let sampleCount: Int
    public let totalDurationSeconds: Double
    public let finalIsolatedGravityMg: Vector3D
    public let peakDynamicPGA: Double
    public let rmsDynamicAccelerationMg: Double
    public let peakJerkMgPerSec: Double
    public let peakStaLtaRatio: Double
    public let cumulativeAriasIntensityMmPerSec: Double
    public let dominantFrequencyHz: Double
    public let zeroCrossingRateHz: Double
    public let crestFactor: Double
    public let dominantPattern: ShakePatternKind
    public let triggeredSampleCount: Int
}

nonisolated public struct MotionKinematicsEngine: Sendable {
    public private(set) var config: MotionKinematicConfig
    public private(set) var sampleIndex: Int = 0
    public private(set) var gravityEstimateMg: Vector3D
    public private(set) var previousLinearMg: Vector3D = .zero
    public private(set) var previousDynamicMg: Vector3D = .zero
    public private(set) var velocityEstimateMmPerSec: Vector3D = .zero
    public private(set) var staEnergy: Double = 0.01
    public private(set) var ltaEnergy: Double = 0.01
    public private(set) var cumulativeAriasIntensity: Double = 0.0

    private struct WindowEntry: Sendable {
        let dt: Double
        let dynamicVector: Vector3D
        let dynamicMagnitude: Double
        let jerkMagnitude: Double
        let staLtaRatio: Double
    }

    private var window: [WindowEntry] = []

    public init(config: MotionKinematicConfig = MotionKinematicConfig()) {
        self.config = config
        self.gravityEstimateMg = config.initialGravityMg
    }

    public mutating func reset(initialGravityMg: Vector3D? = nil) {
        sampleIndex = 0
        if let g = initialGravityMg {
            config.initialGravityMg = g.sanitized(limit: config.maxAccelerationClampMg)
        }
        gravityEstimateMg = config.initialGravityMg
        previousLinearMg = .zero
        previousDynamicMg = .zero
        velocityEstimateMmPerSec = .zero
        staEnergy = 0.01
        ltaEnergy = 0.01
        cumulativeAriasIntensity = 0.0
        window.removeAll(keepingCapacity: true)
    }

    public mutating func calibrateGravity(_ gravityVectorMg: Vector3D) {
        let clean = gravityVectorMg.sanitized(limit: config.maxAccelerationClampMg)
        gravityEstimateMg = clean
        config.initialGravityMg = clean
    }

    public mutating func ingest(rawX: Double, rawY: Double, rawZ: Double, dt: Double = 0.04) -> MotionKinematicFrame {
        return ingest(rawAccelerationMg: Vector3D(x: rawX, y: rawY, z: rawZ), dt: dt)
    }

    public mutating func ingest(rawAccelerationMg: Vector3D, dt: Double = 0.04) -> MotionKinematicFrame {
        let safeDt = (dt.isFinite && dt >= 0.0005 && dt <= 2.0) ? dt : 0.04
        let raw = rawAccelerationMg.sanitized(limit: config.maxAccelerationClampMg)

        // 1. Low-pass IIR filter to isolate static/slow-varying gravity vector
        let twoPiFcDt = 2.0 * Double.pi * config.gravityCutoffHz * safeDt
        let lpAlpha = twoPiFcDt / (1.0 + twoPiFcDt)
        gravityEstimateMg = (gravityEstimateMg * (1.0 - lpAlpha)) + (raw * lpAlpha)

        // 2. Subtract gravity and apply DC-blocking high-pass filter for pure dynamic acceleration
        let linear = raw - gravityEstimateMg
        let dynamic: Vector3D
        if config.highPassCutoffHz > 0.0001 {
            let twoPiHpDt = 2.0 * Double.pi * config.highPassCutoffHz * safeDt
            let hpAlpha = 1.0 / (1.0 + twoPiHpDt)
            dynamic = (previousDynamicMg + (linear - previousLinearMg)) * hpAlpha
        } else {
            dynamic = linear
        }

        // 3. Jerk derivative (mg/s)
        let jerk = (sampleIndex == 0) ? .zero : ((dynamic - previousDynamicMg) / safeDt)
        let jerkMag = jerk.magnitude
        let dynMag = dynamic.magnitude

        // 4. Leaky velocity integral (1 mg = 9.80665 mm/s^2)
        let leak = exp(-safeDt / 0.5)
        let accelMmPerSec2 = dynamic * 9.80665
        velocityEstimateMmPerSec = (velocityEstimateMmPerSec * leak) + (accelMmPerSec2 * safeDt)

        // 5. Arias Intensity accumulation: I_A = (pi / (2 * g0)) * integral(a^2 dt)
        let g0MmPerSec2 = 9806.65
        let accelMagMmPerSec2 = dynMag * 9.80665
        let deltaArias = (Double.pi / (2.0 * g0MmPerSec2)) * (accelMagMmPerSec2 * accelMagMmPerSec2) * safeDt
        if deltaArias.isFinite {
            cumulativeAriasIntensity += deltaArias
        }

        // 6. STA/LTA ratio update
        let instantEnergy = dynMag * dynMag
        staEnergy = config.staAlpha * instantEnergy + (1.0 - config.staAlpha) * staEnergy
        ltaEnergy = config.ltaAlpha * instantEnergy + (1.0 - config.ltaAlpha) * ltaEnergy
        let ratio = max(0.5, staEnergy / max(0.001, ltaEnergy))
        let triggered = ratio >= config.triggerRatioThreshold || dynMag >= config.pgaTriggerThresholdMg

        previousLinearMg = linear
        previousDynamicMg = dynamic
        sampleIndex += 1

        window.append(
            WindowEntry(
                dt: safeDt,
                dynamicVector: dynamic,
                dynamicMagnitude: dynMag,
                jerkMagnitude: jerkMag,
                staLtaRatio: ratio
            )
        )
        if window.count > config.windowCapacity {
            window.removeFirst(window.count - config.windowCapacity)
        }

        let metrics = evaluateWindowMetrics()
        return MotionKinematicFrame(
            sampleIndex: sampleIndex,
            dt: safeDt,
            rawAccelerationMg: raw,
            isolatedGravityMg: gravityEstimateMg,
            linearAccelerationMg: dynamic,
            dynamicMagnitudeMg: dynMag,
            jerkMgPerSec: jerk,
            jerkMagnitudeMgPerSec: jerkMag,
            velocityEstimateMmPerSec: velocityEstimateMmPerSec,
            staLtaRatio: ratio,
            ariasIntensityMmPerSec: cumulativeAriasIntensity,
            zeroCrossingRateHz: metrics.zcrHz,
            dominantFrequencyHz: metrics.dominantFreqHz,
            crestFactor: metrics.crestFactor,
            pattern: metrics.pattern,
            isTriggered: triggered
        )
    }

    public mutating func analyzeTrace(samples: [Vector3D], dt: Double = 0.04) -> MotionTraceSummary {
        let safeDt = (dt.isFinite && dt >= 0.0005 && dt <= 2.0) ? dt : 0.04
        guard !samples.isEmpty else {
            return MotionTraceSummary(
                sampleCount: 0,
                totalDurationSeconds: 0.0,
                finalIsolatedGravityMg: gravityEstimateMg,
                peakDynamicPGA: 0.0,
                rmsDynamicAccelerationMg: 0.0,
                peakJerkMgPerSec: 0.0,
                peakStaLtaRatio: 1.0,
                cumulativeAriasIntensityMmPerSec: cumulativeAriasIntensity,
                dominantFrequencyHz: 0.0,
                zeroCrossingRateHz: 0.0,
                crestFactor: 1.0,
                dominantPattern: .idle,
                triggeredSampleCount: 0
            )
        }

        var peakPGA = 0.0
        var sumSq = 0.0
        var peakJerk = 0.0
        var peakRatio = 0.5
        var triggeredCount = 0
        var lastFrame: MotionKinematicFrame?

        for sample in samples {
            let frame = ingest(rawAccelerationMg: sample, dt: safeDt)
            peakPGA = max(peakPGA, frame.dynamicMagnitudeMg)
            sumSq += frame.dynamicMagnitudeMg * frame.dynamicMagnitudeMg
            peakJerk = max(peakJerk, frame.jerkMagnitudeMgPerSec)
            peakRatio = max(peakRatio, frame.staLtaRatio)
            if frame.isTriggered {
                triggeredCount += 1
            }
            lastFrame = frame
        }

        let rms = sqrt(sumSq / Double(samples.count))
        let crest = peakPGA / max(0.05, rms)

        return MotionTraceSummary(
            sampleCount: samples.count,
            totalDurationSeconds: Double(samples.count) * safeDt,
            finalIsolatedGravityMg: lastFrame?.isolatedGravityMg ?? gravityEstimateMg,
            peakDynamicPGA: peakPGA,
            rmsDynamicAccelerationMg: rms,
            peakJerkMgPerSec: peakJerk,
            peakStaLtaRatio: peakRatio,
            cumulativeAriasIntensityMmPerSec: cumulativeAriasIntensity,
            dominantFrequencyHz: lastFrame?.dominantFrequencyHz ?? 0.0,
            zeroCrossingRateHz: lastFrame?.zeroCrossingRateHz ?? 0.0,
            crestFactor: crest,
            dominantPattern: lastFrame?.pattern ?? .idle,
            triggeredSampleCount: triggeredCount
        )
    }

    // MARK: - Window Feature & Pattern Recognition
    private func evaluateWindowMetrics() -> (
        zcrHz: Double,
        dominantFreqHz: Double,
        crestFactor: Double,
        pattern: ShakePatternKind
    ) {
        guard !window.isEmpty else {
            return (0.0, 0.0, 1.0, .idle)
        }

        var totalDuration = 0.0
        var peakMag = 0.0
        var sumSqMag = 0.0
        var sumSqLateral = 0.0
        var sumSqVertical = 0.0
        var peakStaLta = 0.5
        var activeSampleCount = 0

        for entry in window {
            totalDuration += entry.dt
            peakMag = max(peakMag, entry.dynamicMagnitude)
            let magSq = entry.dynamicMagnitude * entry.dynamicMagnitude
            sumSqMag += magSq
            let latSq = entry.dynamicVector.x * entry.dynamicVector.x + entry.dynamicVector.y * entry.dynamicVector.y
            sumSqLateral += latSq
            sumSqVertical += entry.dynamicVector.z * entry.dynamicVector.z
            peakStaLta = max(peakStaLta, entry.staLtaRatio)
            if entry.dynamicMagnitude >= 6.0 {
                activeSampleCount += 1
            }
        }

        let count = Double(window.count)
        let rmsMag = sqrt(sumSqMag / count)
        let crestFactor = peakMag / max(0.05, rmsMag)
        let safeDuration = max(0.001, totalDuration)

        // Extract dominant axis signal for zero-crossing and frequency analysis
        let useLateralAxis = sumSqLateral >= sumSqVertical
        let axisSignal: [Double] = window.map { entry in
            if useLateralAxis {
                return abs(entry.dynamicVector.x) >= abs(entry.dynamicVector.y) ? entry.dynamicVector.x : entry.dynamicVector.y
            } else {
                return entry.dynamicVector.z
            }
        }

        // Zero-crossing count with deadband hysteresis
        let deadband = 1.5
        var zeroCrossings = 0
        var lastSign = 0
        for value in axisSignal {
            if value > deadband {
                if lastSign < 0 { zeroCrossings += 1 }
                lastSign = 1
            } else if value < -deadband {
                if lastSign > 0 { zeroCrossings += 1 }
                lastSign = -1
            }
        }
        let zcrHz = Double(zeroCrossings) / safeDuration

        // Dominant frequency estimation via autocorrelation on dominant axis
        let meanDt = safeDuration / count
        let dominantFreqHz = Self.estimateDominantFrequency(
            signal: axisSignal,
            dt: meanDt,
            fallbackZcrHz: zcrHz
        )

        // Detect distinct impulse peaks in dynamicMagnitude for single-tap vs double-tap
        let impulsePeaks = Self.detectImpulsePeaks(
            magnitudes: window.map(\.dynamicMagnitude),
            dt: meanDt,
            peakThresholdMg: max(12.0, peakMag * 0.42)
        )

        // Pattern classification decision tree
        let activeFraction = Double(activeSampleCount) / count
        let lateralRatio = sumSqMag > 1e-6 ? sqrt(sumSqLateral / sumSqMag) : 0.0

        let pattern: ShakePatternKind
        if peakMag < 1.5 {
            pattern = .idle
        } else if peakMag < 8.0 {
            pattern = .microTremor
        } else if impulsePeaks.count == 2,
                  let interval = impulsePeaks.interPeakIntervalSeconds,
                  interval >= 0.06 && interval <= 0.60,
                  activeFraction <= 0.55 {
            pattern = .doubleTapImpulse
        } else if (impulsePeaks.count == 1 && activeFraction <= 0.35 && crestFactor >= 2.1 && zeroCrossings <= 4) {
            pattern = .singleTapImpact
        } else if lateralRatio >= 0.62 && zeroCrossings >= 4 && dominantFreqHz >= 1.5 && dominantFreqHz <= 14.0 {
            pattern = .rhythmicLateralShake
        } else if peakStaLta >= config.triggerRatioThreshold || rmsMag >= 10.0 || peakMag >= config.pgaTriggerThresholdMg {
            pattern = .seismicShearWave
        } else {
            pattern = .microTremor
        }

        return (zcrHz, dominantFreqHz, crestFactor, pattern)
    }

    private static func estimateDominantFrequency(
        signal: [Double],
        dt: Double,
        fallbackZcrHz: Double
    ) -> Double {
        let n = signal.count
        guard n >= 8, dt > 0 else { return 0.0 }

        let mean = signal.reduce(0.0, +) / Double(n)
        let centered = signal.map { $0 - mean }
        var energy0 = 0.0
        for v in centered { energy0 += v * v }
        guard energy0 > 1.0 else { return 0.0 }

        let minFreq = 1.2
        let maxFreq = min(12.0, 0.45 / dt)
        guard minFreq < maxFreq else { return fallbackZcrHz * 0.5 }

        let minLag = max(2, Int(round(1.0 / (maxFreq * dt))))
        let maxLag = min(n / 2, Int(round(1.0 / (minFreq * dt))))
        guard minLag <= maxLag else { return fallbackZcrHz * 0.5 }

        var bestLag = 0
        var bestCorr = -1.0
        for lag in minLag...maxLag {
            var corr = 0.0
            let limit = n - lag
            for i in 0..<limit {
                corr += centered[i] * centered[i + lag]
            }
            let normCorr = corr / energy0
            if normCorr > bestCorr {
                bestCorr = normCorr
                bestLag = lag
            }
        }

        if bestCorr >= 0.20 && bestLag > 0 {
            return 1.0 / (Double(bestLag) * dt)
        }
        return fallbackZcrHz * 0.5
    }

    private static func detectImpulsePeaks(
        magnitudes: [Double],
        dt: Double,
        peakThresholdMg: Double
    ) -> (count: Int, interPeakIntervalSeconds: Double?) {
        let n = magnitudes.count
        guard n >= 3 else { return (0, nil) }

        var peakIndices: [Int] = []
        let minSeparationSamples = max(2, Int(round(0.08 / max(0.001, dt))))

        for i in 1..<(n - 1) {
            let current = magnitudes[i]
            guard current >= peakThresholdMg else { continue }
            if current >= magnitudes[i - 1] && current >= magnitudes[i + 1] {
                if let lastIdx = peakIndices.last {
                    if i - lastIdx < minSeparationSamples {
                        if current > magnitudes[lastIdx] {
                            peakIndices[peakIndices.count - 1] = i
                        }
                        continue
                    }
                    // Verify there is a clear valley between the previous peak and this peak
                    let valleyMin = magnitudes[lastIdx...i].min() ?? current
                    let referencePeak = min(magnitudes[lastIdx], current)
                    if valleyMin <= referencePeak * 0.55 {
                        peakIndices.append(i)
                    }
                } else {
                    peakIndices.append(i)
                }
            }
        }

        if peakIndices.count == 2 {
            let interval = Double(peakIndices[1] - peakIndices[0]) * dt
            return (2, interval)
        }
        return (peakIndices.count, nil)
    }
}
