import Foundation

nonisolated public enum ShakeAndSoundVersion {
    public static let current = "0.2.0"
}

nonisolated public struct SubsystemBenchmarkMetric: Codable, Equatable, Sendable {
    public let subsystem: String
    public let iterations: Int
    public let totalItemsProcessed: Int
    public let elapsedMilliseconds: Double
    public let throughputPerSecond: Double
    public let verificationPassed: Bool
}

nonisolated public struct ShakeAndSoundBenchmarkReport: Codable, Equatable, Sendable {
    public let version: String
    public let iterations: Int
    public let allVerificationsPassed: Bool
    public let metrics: [SubsystemBenchmarkMetric]
}

nonisolated public enum ShakeAndSoundBenchmarkSuite {
    /// Generates a deterministic 3-axis accelerometer trace (in mg) with a static gravity vector
    /// superposed with the specified physical kinetic disturbance pattern.
    public static func generateSyntheticMotionTrace(
        pattern: ShakePatternKind,
        sampleCount: Int = 64,
        dt: Double = 0.04,
        gravityVectorMg: Vector3D = Vector3D(x: 110.0, y: -75.0, z: 980.0)
    ) -> [Vector3D] {
        let count = max(16, min(2048, sampleCount))
        let safeDt = (dt.isFinite && dt >= 0.001) ? dt : 0.04
        var trace = [Vector3D]()
        trace.reserveCapacity(count)

        for i in 0..<count {
            let t = Double(i) * safeDt
            var dx = 0.0
            var dy = 0.0
            var dz = 0.0

            switch pattern {
            case .idle:
                dx = 0.15 * sin(2.0 * Double.pi * 0.5 * t)
                dy = 0.10 * cos(2.0 * Double.pi * 0.4 * t)
                dz = 0.12 * sin(2.0 * Double.pi * 0.6 * t)

            case .microTremor:
                dx = 2.2 * sin(2.0 * Double.pi * 1.1 * t)
                dy = 1.8 * cos(2.0 * Double.pi * 0.9 * t)
                dz = 2.8 * sin(2.0 * Double.pi * 1.3 * t)

            case .singleTapImpact:
                let tapIdx = count / 2
                let dist = i - tapIdx
                if dist >= 0 && dist <= 4 {
                    let decay = exp(-Double(dist) * 0.95)
                    dz = 68.0 * decay * (dist % 2 == 0 ? 1.0 : -0.35)
                    dx = 12.0 * decay
                }

            case .doubleTapImpulse:
                let tap1 = count / 2 - 4
                let tap2 = tap1 + 6 // 6 * 0.04s = 0.24s inter-tap interval
                for tap in [tap1, tap2] {
                    let dist = i - tap
                    if dist >= 0 && dist <= 2 {
                        let decay = exp(-Double(dist) * 1.2)
                        dz += 72.0 * decay
                        dx += 10.0 * decay
                    }
                }

            case .rhythmicLateralShake:
                // 4.0 Hz lateral oscillation predominantly along X-Y plane
                let freq = 4.0
                dx = 42.0 * sin(2.0 * Double.pi * freq * t)
                dy = 24.0 * cos(2.0 * Double.pi * freq * t)
                dz = 3.5 * sin(2.0 * Double.pi * (freq * 0.5) * t)

            case .seismicShearWave:
                // High-energy multi-axis P/S wave burst in the second half of the trace
                if i >= count / 3 {
                    let burstT = Double(i - count / 3) * safeDt
                    let env = min(1.0, burstT * 3.0) * exp(-max(0.0, burstT - 0.5) * 0.8)
                    dx = 18.0 * env * sin(2.0 * Double.pi * 2.3 * t)
                    dy = 22.0 * env * cos(2.0 * Double.pi * 3.1 * t)
                    dz = 85.0 * env * sin(2.0 * Double.pi * 6.5 * t)
                }
            }

            trace.append(gravityVectorMg + Vector3D(x: dx, y: dy, z: dz))
        }
        return trace
    }

    public static func run(iterations: Int = 25) -> ShakeAndSoundBenchmarkReport {
        let safeIterations = max(1, min(500, iterations))
        var metrics: [SubsystemBenchmarkMetric] = []

        // 1. Motion Kinematics & Pattern Classification Benchmark
        do {
            let trace = generateSyntheticMotionTrace(pattern: .rhythmicLateralShake, sampleCount: 64, dt: 0.04)
            let start = DispatchTime.now().uptimeNanoseconds
            var lastSummary: MotionTraceSummary?
            for _ in 0..<safeIterations {
                var engine = MotionKinematicsEngine(
                    config: MotionKinematicConfig(
                        initialGravityMg: Vector3D(x: 110.0, y: -75.0, z: 980.0)
                    )
                )
                lastSummary = engine.analyzeTrace(samples: trace, dt: 0.04)
            }
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
            let totalSamples = safeIterations * trace.count
            let throughput = elapsedMs > 0 ? (Double(totalSamples) / (elapsedMs / 1000.0)) : 0.0
            let verified = (lastSummary?.dominantPattern == .rhythmicLateralShake) && ((lastSummary?.peakDynamicPGA ?? 0) > 25.0)

            metrics.append(
                SubsystemBenchmarkMetric(
                    subsystem: "motion_kinematics_dsp",
                    iterations: safeIterations,
                    totalItemsProcessed: totalSamples,
                    elapsedMilliseconds: elapsedMs,
                    throughputPerSecond: throughput,
                    verificationPassed: verified
                )
            )
        }

        // 2. Procedural Polyphonic Audio Synthesis & vDSP Pitch Detection Benchmark
        do {
            let voices = [
                SynthVoiceSpec(waveform: .sine, frequencyHz: 220.0, amplitude: 0.75, envelope: .organFlat),
                SynthVoiceSpec(waveform: .sine, frequencyHz: 440.0, amplitude: 0.18, envelope: .organFlat)
            ]
            let start = DispatchTime.now().uptimeNanoseconds
            var lastPitch: Float = 0.0
            var totalFrames = 0
            for _ in 0..<safeIterations {
                let pcm = ProceduralAudioSynthesizer.synthesize(
                    voices: voices,
                    durationSeconds: 0.1,
                    sampleRate: 48_000.0
                )
                let analysis = ProceduralAudioSynthesizer.analyzePCM(samples: pcm, sampleRate: 48_000.0)
                lastPitch = analysis.fundamentalPitchHz
                totalFrames += pcm.count
            }
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
            let throughput = elapsedMs > 0 ? (Double(totalFrames) / (elapsedMs / 1000.0)) : 0.0
            let verified = abs(lastPitch - 220.0) < 6.0

            metrics.append(
                SubsystemBenchmarkMetric(
                    subsystem: "polyphonic_synth_and_vdsp_pitch",
                    iterations: safeIterations,
                    totalItemsProcessed: totalFrames,
                    elapsedMilliseconds: elapsedMs,
                    throughputPerSecond: throughput,
                    verificationPassed: verified
                )
            )
        }

        // 3. RIFF/WAVE PCM16 Encode & Decode Roundtrip Benchmark
        do {
            let sampleBuffer = ProceduralAudioSynthesizer.synthesize(
                voices: [SynthVoiceSpec(waveform: .triangle, frequencyHz: 330.0, amplitude: 0.8)],
                durationSeconds: 0.1,
                sampleRate: 48_000.0
            )
            let start = DispatchTime.now().uptimeNanoseconds
            var roundtripOk = true
            var totalSamples = 0
            for _ in 0..<safeIterations {
                if let encoded = try? WAVCodec.encodePCM16WAV(samples: sampleBuffer, sampleRate: 48_000, channels: 1),
                   let decoded = try? WAVCodec.decodeWAV(data: encoded) {
                    totalSamples += decoded.frameCount
                    if decoded.frameCount != sampleBuffer.count || decoded.sampleRate != 48_000 {
                        roundtripOk = false
                    }
                } else {
                    roundtripOk = false
                }
            }
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
            let throughput = elapsedMs > 0 ? (Double(totalSamples) / (elapsedMs / 1000.0)) : 0.0

            metrics.append(
                SubsystemBenchmarkMetric(
                    subsystem: "riff_wav_pcm16_codec",
                    iterations: safeIterations,
                    totalItemsProcessed: totalSamples,
                    elapsedMilliseconds: elapsedMs,
                    throughputPerSecond: throughput,
                    verificationPassed: roundtripOk && totalSamples > 0
                )
            )
        }

        // 4. Tempo BPM Estimation & Adaptive Haptic Curve Synthesis Benchmark
        do {
            let env = TempoHapticCurveEngine.generateRhythmicEnvelope(
                bpm: 120.0,
                durationSeconds: 4.0,
                frameRateHz: 100.0
            )
            let start = DispatchTime.now().uptimeNanoseconds
            var lastBPM = 0.0
            var totalFrames = 0
            for _ in 0..<safeIterations {
                let (tempo, frames) = TempoHapticCurveEngine.generateSynchronizedHapticFrames(
                    energyEnvelope: env,
                    frameRateHz: 100.0,
                    curve: .sCurveSigmoid(steepness: 8.0, midpoint: 0.5)
                )
                lastBPM = tempo.estimatedBPM
                totalFrames += frames.count
            }
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
            let throughput = elapsedMs > 0 ? (Double(totalFrames) / (elapsedMs / 1000.0)) : 0.0
            let verified = abs(lastBPM - 120.0) < 4.0

            metrics.append(
                SubsystemBenchmarkMetric(
                    subsystem: "tempo_sync_and_haptic_curves",
                    iterations: safeIterations,
                    totalItemsProcessed: totalFrames,
                    elapsedMilliseconds: elapsedMs,
                    throughputPerSecond: throughput,
                    verificationPassed: verified
                )
            )
        }

        let allPassed = metrics.allSatisfy(\.verificationPassed)
        return ShakeAndSoundBenchmarkReport(
            version: ShakeAndSoundVersion.current,
            iterations: safeIterations,
            allVerificationsPassed: allPassed,
            metrics: metrics
        )
    }
}
