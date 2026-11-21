import Foundation

nonisolated public enum ResponseCurveKind: Codable, Equatable, Sendable {
    case linear
    case exponential(gamma: Double)
    case logarithmic(curvature: Double)
    case sCurveSigmoid(steepness: Double, midpoint: Double)
    case equalLoudnessContour(frequencyHz: Double)

    public var identifier: String {
        switch self {
        case .linear:
            return "linear"
        case .exponential(let gamma):
            return String(format: "exponential(gamma=%.2f)", gamma)
        case .logarithmic(let k):
            return String(format: "logarithmic(k=%.2f)", k)
        case .sCurveSigmoid(let s, let m):
            return String(format: "sigmoid(s=%.2f,m=%.2f)", s, m)
        case .equalLoudnessContour(let f):
            return String(format: "equal_loudness(f=%.0fHz)", f)
        }
    }
}

nonisolated public struct DynamicCompressorConfig: Codable, Equatable, Sendable {
    public var thresholdDb: Double
    public var ratio: Double
    public var attackMs: Double
    public var releaseMs: Double
    public var makeupGainDb: Double

    public init(
        thresholdDb: Double = -18.0,
        ratio: Double = 4.0,
        attackMs: Double = 8.0,
        releaseMs: Double = 80.0,
        makeupGainDb: Double = 3.0
    ) {
        self.thresholdDb = thresholdDb.isFinite ? min(0.0, max(-80.0, thresholdDb)) : -18.0
        self.ratio = (ratio.isFinite && ratio >= 1.0) ? min(20.0, ratio) : 4.0
        self.attackMs = (attackMs.isFinite && attackMs >= 0.1) ? min(500.0, attackMs) : 8.0
        self.releaseMs = (releaseMs.isFinite && releaseMs >= 1.0) ? min(2000.0, releaseMs) : 80.0
        self.makeupGainDb = makeupGainDb.isFinite ? min(24.0, max(-24.0, makeupGainDb)) : 3.0
    }
}

nonisolated public struct HapticTransientFrame: Codable, Equatable, Sendable {
    public let timestampSeconds: Double
    public let intensity: Double
    public let sharpness: Double
    public let beatPhase: Double
    public let isBeatAccent: Bool
}

nonisolated public struct TempoEstimateResult: Codable, Equatable, Sendable {
    public let estimatedBPM: Double
    public let confidence: Double
    public let onsetTimestamps: [Double]
    public let meanInterOnsetIntervalSeconds: Double
    public let beatPhaseAtEnd: Double
}

nonisolated public enum TempoHapticCurveEngine {
    public static func evaluateCurve(_ kind: ResponseCurveKind, input: Double) -> Double {
        guard input.isFinite else { return 0.0 }
        let x = min(1.0, max(0.0, input))
        if x <= 0.0 { return 0.0 }
        if x >= 1.0 { return 1.0 }

        switch kind {
        case .linear:
            return x

        case .exponential(let gamma):
            let safeGamma = (gamma.isFinite && gamma > 0.05) ? min(10.0, gamma) : 2.2
            return min(1.0, max(0.0, pow(x, safeGamma)))

        case .logarithmic(let curvature):
            let k = (curvature.isFinite && curvature > 0.05) ? min(100.0, curvature) : 9.0
            let num = log1p(k * x)
            let den = log1p(k)
            guard den > 1e-9 else { return x }
            return min(1.0, max(0.0, num / den))

        case .sCurveSigmoid(let steepness, let midpoint):
            let s = (steepness.isFinite && steepness > 0.5) ? min(30.0, steepness) : 8.0
            let m = midpoint.isFinite ? min(0.9, max(0.1, midpoint)) : 0.5
            func rawSig(_ v: Double) -> Double {
                1.0 / (1.0 + exp(-s * (v - m)))
            }
            let y0 = rawSig(0.0)
            let y1 = rawSig(1.0)
            let span = y1 - y0
            guard abs(span) > 1e-9 else { return x }
            return min(1.0, max(0.0, (rawSig(x) - y0) / span))

        case .equalLoudnessContour(let frequencyHz):
            let f = (frequencyHz.isFinite && frequencyHz >= 20.0) ? min(20_000.0, frequencyHz) : 1_000.0
            let weight = aWeightingLinearGain(frequencyHz: f)
            // Blend perceptual frequency weighting into a gentle psychoacoustic power curve
            let exponent = max(0.45, min(2.4, 1.0 / max(0.25, weight)))
            return min(1.0, max(0.0, pow(x, exponent)))
        }
    }

    /// Standard IEC 61672 A-weighting normalized linear gain around 1 kHz.
    public static func aWeightingLinearGain(frequencyHz: Double) -> Double {
        guard frequencyHz.isFinite && frequencyHz > 10.0 else { return 0.25 }
        let f2 = frequencyHz * frequencyHz
        let c1 = 12194.0 * 12194.0
        let c2 = 20.6 * 20.6
        let c3 = 107.7 * 107.7
        let c4 = 737.9 * 737.9

        let num = c1 * f2 * f2
        let den = (f2 + c2) * sqrt((f2 + c3) * (f2 + c4)) * (f2 + c1)
        guard den > 1e-12 else { return 0.25 }
        let ra = num / den
        // Normalize at 1000 Hz (where 20*log10(R_A(1000)) + 2.00 = 0 dB)
        let db = 20.0 * log10(max(1e-6, ra)) + 2.00
        let linear = pow(10.0, db / 20.0)
        return min(1.5, max(0.1, linear))
    }

    public static func applyDynamicCompression(
        envelope: [Double],
        sampleRateHz: Double,
        config: DynamicCompressorConfig = DynamicCompressorConfig()
    ) -> [Double] {
        guard !envelope.isEmpty else { return [] }
        let safeRate = (sampleRateHz.isFinite && sampleRateHz >= 1.0) ? min(192_000.0, sampleRateHz) : 50.0
        let dt = 1.0 / safeRate

        let attackTau = max(0.0001, config.attackMs / 1000.0)
        let releaseTau = max(0.001, config.releaseMs / 1000.0)
        let attackCoeff = exp(-dt / attackTau)
        let releaseCoeff = exp(-dt / releaseTau)

        var smoothedGainReductionDb = 0.0
        var output = [Double](repeating: 0.0, count: envelope.count)

        for (idx, rawVal) in envelope.enumerated() {
            let amp = rawVal.isFinite ? min(10.0, max(0.0, abs(rawVal))) : 0.0
            let inputDb = 20.0 * log10(max(amp, 1e-5))

            let targetReductionDb: Double
            if inputDb > config.thresholdDb {
                let overshoot = inputDb - config.thresholdDb
                targetReductionDb = overshoot * (1.0 - (1.0 / config.ratio))
            } else {
                targetReductionDb = 0.0
            }

            if targetReductionDb > smoothedGainReductionDb {
                smoothedGainReductionDb = attackCoeff * smoothedGainReductionDb + (1.0 - attackCoeff) * targetReductionDb
            } else {
                smoothedGainReductionDb = releaseCoeff * smoothedGainReductionDb + (1.0 - releaseCoeff) * targetReductionDb
            }

            let outDb = inputDb - smoothedGainReductionDb + config.makeupGainDb
            let outLinear = amp <= 1e-5 ? 0.0 : pow(10.0, outDb / 20.0)
            output[idx] = min(1.0, max(0.0, outLinear))
        }

        return output
    }

    public static func estimateTempo(
        energyEnvelope: [Double],
        frameRateHz: Double,
        minBPM: Double = 40.0,
        maxBPM: Double = 220.0
    ) -> TempoEstimateResult {
        guard energyEnvelope.count >= 8,
              frameRateHz.isFinite, frameRateHz >= 4.0,
              minBPM.isFinite, maxBPM.isFinite,
              minBPM >= 20.0, maxBPM > minBPM else {
            return TempoEstimateResult(
                estimatedBPM: 0.0,
                confidence: 0.0,
                onsetTimestamps: [],
                meanInterOnsetIntervalSeconds: 0.0,
                beatPhaseAtEnd: 0.0
            )
        }

        let clean: [Double] = energyEnvelope.map { v in
            v.isFinite ? max(0.0, min(100.0, v)) : 0.0
        }
        let n = clean.count
        let dt = 1.0 / frameRateHz

        // 1. Half-wave rectified first-order spectral/energy onset flux
        var flux = [Double](repeating: 0.0, count: n)
        for i in 1..<n {
            let diff = clean[i] - clean[i - 1]
            flux[i] = max(0.0, diff)
        }

        let maxFlux = flux.max() ?? 0.0
        let maxLevel = clean.max() ?? 0.0
        guard maxFlux > 0.01 || maxLevel > 0.05 else {
            return TempoEstimateResult(
                estimatedBPM: 0.0,
                confidence: 0.0,
                onsetTimestamps: [],
                meanInterOnsetIntervalSeconds: 0.0,
                beatPhaseAtEnd: 0.0
            )
        }

        // Combine positive flux with envelope peaks for sharp pulse trains
        var novelty = [Double](repeating: 0.0, count: n)
        for i in 0..<n {
            novelty[i] = 0.65 * (maxFlux > 1e-6 ? flux[i] / maxFlux : 0.0)
                + 0.35 * (maxLevel > 1e-6 ? clean[i] / maxLevel : 0.0)
        }

        // 2. Adaptive local threshold peak picking with refractory debounce
        let refractoryFrames = max(2, Int(round((60.0 / maxBPM) * frameRateHz * 0.65)))
        let halfWin = max(3, Int(round(0.35 * frameRateHz)))
        var onsetIndices: [Int] = []

        for i in 1..<(n - 1) {
            let lo = max(0, i - halfWin)
            let hi = min(n - 1, i + halfWin)
            let localSlice = novelty[lo...hi]
            let localMean = localSlice.reduce(0.0, +) / Double(localSlice.count)
            let threshold = max(0.22, localMean + 0.14)

            if novelty[i] >= threshold && novelty[i] >= novelty[i - 1] && novelty[i] > novelty[i + 1] {
                if let lastIdx = onsetIndices.last {
                    if i - lastIdx < refractoryFrames {
                        if novelty[i] > novelty[lastIdx] {
                            onsetIndices[onsetIndices.count - 1] = i
                        }
                        continue
                    }
                }
                onsetIndices.append(i)
            }
        }

        let onsetTimestamps = onsetIndices.map { Double($0) * dt }
        guard onsetTimestamps.count >= 2 else {
            return TempoEstimateResult(
                estimatedBPM: 0.0,
                confidence: 0.0,
                onsetTimestamps: onsetTimestamps,
                meanInterOnsetIntervalSeconds: 0.0,
                beatPhaseAtEnd: 0.0
            )
        }

        // 3. Inter-onset intervals (IOIs) with octave-folding into [minBPM, maxBPM]
        var candidateBPMs: [Double] = []
        var rawIntervals: [Double] = []

        for i in 1..<onsetTimestamps.count {
            let ioi = onsetTimestamps[i] - onsetTimestamps[i - 1]
            guard ioi > 0.05 else { continue }
            rawIntervals.append(ioi)
            var bpm = 60.0 / ioi
            while bpm < minBPM && bpm > 5.0 { bpm *= 2.0 }
            while bpm > maxBPM && bpm < 2000.0 { bpm *= 0.5 }
            if bpm >= minBPM && bpm <= maxBPM {
                candidateBPMs.append(bpm)
            }
        }

        guard !candidateBPMs.isEmpty else {
            return TempoEstimateResult(
                estimatedBPM: 0.0,
                confidence: 0.0,
                onsetTimestamps: onsetTimestamps,
                meanInterOnsetIntervalSeconds: 0.0,
                beatPhaseAtEnd: 0.0
            )
        }

        // Cluster around the median BPM to reject outlier IOIs
        let sortedBPMs = candidateBPMs.sorted()
        let medianBPM = sortedBPMs[sortedBPMs.count / 2]
        let inliers = sortedBPMs.filter { abs($0 - medianBPM) <= max(4.0, medianBPM * 0.08) }
        let estimatedBPM = inliers.reduce(0.0, +) / Double(inliers.count)
        let meanIOI = 60.0 / estimatedBPM

        // Compute tempo stability confidence [0, 1]
        let inlierRatio = Double(inliers.count) / Double(candidateBPMs.count)
        let variance = inliers.reduce(0.0) { acc, b in
            let d = b - estimatedBPM
            return acc + d * d
        } / Double(max(1, inliers.count))
        let stdDev = sqrt(variance)
        let jitterPenalty = min(1.0, stdDev / max(1.0, estimatedBPM * 0.1))
        let confidence = min(1.0, max(0.0, inlierRatio * (1.0 - 0.6 * jitterPenalty)))

        // End phase relative to last onset
        let totalTime = Double(n - 1) * dt
        let lastOnset = onsetTimestamps.last ?? 0.0
        let beatPhase = ((totalTime - lastOnset) / meanIOI).truncatingRemainder(dividingBy: 1.0)
        let normalizedPhase = beatPhase < 0 ? beatPhase + 1.0 : beatPhase

        return TempoEstimateResult(
            estimatedBPM: estimatedBPM,
            confidence: confidence,
            onsetTimestamps: onsetTimestamps,
            meanInterOnsetIntervalSeconds: meanIOI,
            beatPhaseAtEnd: normalizedPhase
        )
    }

    public static func generateSynchronizedHapticFrames(
        energyEnvelope: [Double],
        frameRateHz: Double,
        curve: ResponseCurveKind = .sCurveSigmoid(steepness: 8.0, midpoint: 0.45),
        compressor: DynamicCompressorConfig = DynamicCompressorConfig()
    ) -> (tempo: TempoEstimateResult, frames: [HapticTransientFrame]) {
        guard !energyEnvelope.isEmpty, frameRateHz.isFinite, frameRateHz >= 1.0 else {
            let emptyTempo = TempoEstimateResult(
                estimatedBPM: 0.0,
                confidence: 0.0,
                onsetTimestamps: [],
                meanInterOnsetIntervalSeconds: 0.0,
                beatPhaseAtEnd: 0.0
            )
            return (emptyTempo, [])
        }

        let tempo = estimateTempo(energyEnvelope: energyEnvelope, frameRateHz: frameRateHz)
        let compressed = applyDynamicCompression(envelope: energyEnvelope, sampleRateHz: frameRateHz, config: compressor)
        let dt = 1.0 / frameRateHz
        let beatPeriod = tempo.estimatedBPM > 0.0 ? (60.0 / tempo.estimatedBPM) : 0.5
        let anchorTime = tempo.onsetTimestamps.first ?? 0.0

        var frames = [HapticTransientFrame]()
        frames.reserveCapacity(compressed.count)

        for i in 0..<compressed.count {
            let t = Double(i) * dt
            let mappedIntensity = evaluateCurve(curve, input: compressed[i])
            let prev = i > 0 ? compressed[i - 1] : compressed[i]
            let transientSlope = max(0.0, (compressed[i] - prev) * frameRateHz)
            let sharpness = min(1.0, max(0.1, 0.35 * mappedIntensity + 0.65 * tanh(transientSlope * 0.15)))

            let relTime = t - anchorTime
            let rawPhase = (relTime / beatPeriod).truncatingRemainder(dividingBy: 1.0)
            let phase = rawPhase < 0 ? rawPhase + 1.0 : rawPhase
            let isAccent = (phase < 0.08 || phase > 0.92) && mappedIntensity >= 0.25

            frames.append(
                HapticTransientFrame(
                    timestampSeconds: t,
                    intensity: mappedIntensity,
                    sharpness: sharpness,
                    beatPhase: phase,
                    isBeatAccent: isAccent
                )
            )
        }

        return (tempo, frames)
    }

    public static func generateRhythmicEnvelope(
        bpm: Double,
        durationSeconds: Double = 4.0,
        frameRateHz: Double = 100.0
    ) -> [Double] {
        guard bpm.isFinite, bpm >= 30.0, bpm <= 240.0,
              durationSeconds.isFinite, durationSeconds > 0.2,
              frameRateHz.isFinite, frameRateHz >= 10.0 else {
            return []
        }

        let totalFrames = max(8, Int(round(min(30.0, durationSeconds) * frameRateHz)))
        let dt = 1.0 / frameRateHz
        let beatInterval = 60.0 / bpm
        var envelope = [Double](repeating: 0.02, count: totalFrames)

        for i in 0..<totalFrames {
            let t = Double(i) * dt
            let phaseTime = t.truncatingRemainder(dividingBy: beatInterval)
            // Exponential pulse decay after each beat onset
            let pulse = 0.92 * exp(-phaseTime / 0.045)
            envelope[i] = min(1.0, 0.02 + pulse)
        }
        return envelope
    }
}
