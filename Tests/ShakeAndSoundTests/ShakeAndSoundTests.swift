import Foundation
import Testing
@testable import ShakeAndSoundCore

@Suite("ShakeAndSound v0.2.0 Core DSP & Kinematics Suite")
struct ShakeAndSoundTests {
    @Test("Version constant matches 0.2.0")
    func versionConstantIs0_2_0() {
        #expect(ShakeAndSoundVersion.current == "0.2.0")
    }

    @Test("Gravity isolation converges on static tilt vector and rejects DC offset")
    func gravityIsolationConvergesOnStaticTiltVector() {
        let staticGravity = Vector3D(x: 145.0, y: -210.0, z: 965.0)
        var engine = MotionKinematicsEngine(
            config: MotionKinematicConfig(
                gravityCutoffHz: 1.2,
                highPassCutoffHz: 0.4,
                initialGravityMg: .zero
            )
        )

        var lastFrame: MotionKinematicFrame?
        for _ in 0..<160 {
            lastFrame = engine.ingest(rawAccelerationMg: staticGravity, dt: 0.04)
        }

        guard let frame = lastFrame else {
            Issue.record("Expected frame output")
            return
        }

        let gravityError = (frame.isolatedGravityMg - staticGravity).magnitude
        #expect(gravityError < 1.5)
        #expect(frame.dynamicMagnitudeMg < 0.5)
        #expect(frame.pattern == .idle)
    }

    @Test("Single-tap impact classification and crest factor verification")
    func singleTapImpactClassificationAndCrestFactor() {
        let gravity = Vector3D(x: 110.0, y: -75.0, z: 980.0)
        let trace = ShakeAndSoundBenchmarkSuite.generateSyntheticMotionTrace(
            pattern: .singleTapImpact,
            sampleCount: 64,
            dt: 0.04,
            gravityVectorMg: gravity
        )
        var engine = MotionKinematicsEngine(
            config: MotionKinematicConfig(initialGravityMg: gravity)
        )
        let summary = engine.analyzeTrace(samples: trace, dt: 0.04)

        #expect(summary.dominantPattern == .singleTapImpact)
        #expect(summary.peakDynamicPGA > 40.0)
        #expect(summary.crestFactor > 2.2)
        #expect(summary.peakJerkMgPerSec > 500.0)
    }

    @Test("Double-tap impulse classification with inter-tap valley separation")
    func doubleTapImpulseClassification() {
        let gravity = Vector3D(x: 110.0, y: -75.0, z: 980.0)
        let trace = ShakeAndSoundBenchmarkSuite.generateSyntheticMotionTrace(
            pattern: .doubleTapImpulse,
            sampleCount: 64,
            dt: 0.04,
            gravityVectorMg: gravity
        )
        var engine = MotionKinematicsEngine(
            config: MotionKinematicConfig(initialGravityMg: gravity)
        )
        let summary = engine.analyzeTrace(samples: trace, dt: 0.04)

        #expect(summary.dominantPattern == .doubleTapImpulse)
        #expect(summary.peakDynamicPGA > 45.0)
    }

    @Test("Rhythmic lateral shake classification and dominant frequency recovery")
    func rhythmicLateralShakeClassificationAndFrequencyRecovery() {
        let gravity = Vector3D(x: 110.0, y: -75.0, z: 980.0)
        let trace = ShakeAndSoundBenchmarkSuite.generateSyntheticMotionTrace(
            pattern: .rhythmicLateralShake,
            sampleCount: 64,
            dt: 0.04,
            gravityVectorMg: gravity
        )
        var engine = MotionKinematicsEngine(
            config: MotionKinematicConfig(initialGravityMg: gravity)
        )
        let summary = engine.analyzeTrace(samples: trace, dt: 0.04)

        #expect(summary.dominantPattern == .rhythmicLateralShake)
        #expect(abs(summary.dominantFrequencyHz - 4.0) <= 0.55)
        #expect(summary.zeroCrossingRateHz > 5.0)
    }

    @Test("Seismic shear wave detection and monotonic Arias intensity growth")
    func seismicShearWaveDetectionAndAriasIntensityGrowth() {
        let gravity = Vector3D(x: 110.0, y: -75.0, z: 980.0)
        let trace = ShakeAndSoundBenchmarkSuite.generateSyntheticMotionTrace(
            pattern: .seismicShearWave,
            sampleCount: 64,
            dt: 0.04,
            gravityVectorMg: gravity
        )
        var engine = MotionKinematicsEngine(
            config: MotionKinematicConfig(initialGravityMg: gravity)
        )

        var previousArias = 0.0
        for sample in trace {
            let frame = engine.ingest(rawAccelerationMg: sample, dt: 0.04)
            #expect(frame.ariasIntensityMmPerSec >= previousArias)
            previousArias = frame.ariasIntensityMmPerSec
        }

        engine.reset(initialGravityMg: gravity)
        let summary = engine.analyzeTrace(samples: trace, dt: 0.04)
        #expect(summary.dominantPattern == .seismicShearWave)
        #expect(summary.peakStaLtaRatio >= 3.0)
        #expect(summary.triggeredSampleCount > 0)
        #expect(summary.cumulativeAriasIntensityMmPerSec > 0.001)
    }

    @Test("Motion kinematics hostile input hardening against NaN, Inf, and extreme outliers")
    func motionKinematicsHostileInputHardening() {
        var engine = MotionKinematicsEngine(
            config: MotionKinematicConfig(
                gravityCutoffHz: .nan,
                highPassCutoffHz: -.infinity,
                staAlpha: 999.0,
                ltaAlpha: -5.0,
                triggerRatioThreshold: .nan,
                pgaTriggerThresholdMg: -10.0,
                maxAccelerationClampMg: .infinity,
                windowCapacity: -100,
                initialGravityMg: Vector3D(x: .nan, y: .infinity, z: -.infinity)
            )
        )

        let emptySummary = engine.analyzeTrace(samples: [], dt: -1.0)
        #expect(emptySummary.sampleCount == 0)
        #expect(emptySummary.dominantPattern == .idle)

        let hostileInputs: [(Vector3D, Double)] = [
            (Vector3D(x: .nan, y: .infinity, z: -.infinity), .nan),
            (Vector3D(x: 1e18, y: -1e18, z: 1e18), 0.0),
            (Vector3D(x: -0.0, y: .leastNonzeroMagnitude, z: .greatestFiniteMagnitude), -0.5),
            (Vector3D(x: 15.0, y: -25.0, z: 40.0), .infinity)
        ]

        for (vec, badDt) in hostileInputs {
            let frame = engine.ingest(rawAccelerationMg: vec, dt: badDt)
            #expect(frame.dynamicMagnitudeMg.isFinite)
            #expect(frame.jerkMagnitudeMgPerSec.isFinite)
            #expect(frame.staLtaRatio.isFinite)
            #expect(frame.ariasIntensityMmPerSec.isFinite)
            #expect(frame.zeroCrossingRateHz.isFinite)
            #expect(frame.dominantFrequencyHz.isFinite)
            #expect(frame.crestFactor.isFinite)
            #expect(frame.rawAccelerationMg.magnitude <= 50_000.0 * sqrt(3.0) + 1.0)
        }
    }

    @Test("Procedural sine synthesis and vDSP autocorrelation F0 pitch recovery property")
    func proceduralSineSynthesisAndFundamentalPitchRecoveryProperty() {
        let testFrequencies: [Double] = [110.0, 165.0, 220.0, 293.66, 330.0, 440.0]
        let sampleRate = 48_000.0

        for targetHz in testFrequencies {
            let voice = SynthVoiceSpec(
                waveform: .sine,
                frequencyHz: targetHz,
                amplitude: 0.80,
                envelope: .organFlat
            )
            let pcm = ProceduralAudioSynthesizer.synthesize(
                voices: [voice],
                durationSeconds: 0.15,
                sampleRate: sampleRate
            )
            #expect(pcm.count == Int(round(0.15 * sampleRate)))

            let analysis = ProceduralAudioSynthesizer.analyzePCM(samples: pcm, sampleRate: sampleRate)
            #expect(analysis.rmsPower > 0.4)
            #expect(analysis.isVoiceActive)
            let relativeError = abs(Double(analysis.fundamentalPitchHz) - targetHz) / targetHz
            #expect(relativeError < 0.025)
        }
    }

    @Test("Polyphonic multi-waveform synthesis and soft-clipping bounds")
    func polyphonicMultiWaveformSynthesisAndClippingBounds() {
        let voices: [SynthVoiceSpec] = [
            SynthVoiceSpec(waveform: .sine, frequencyHz: 220.0, endFrequencyHz: 330.0, amplitude: 0.7),
            SynthVoiceSpec(waveform: .triangle, frequencyHz: 440.0, amplitude: 0.6),
            SynthVoiceSpec(waveform: .sawtooth, frequencyHz: 110.0, amplitude: 0.5),
            SynthVoiceSpec(waveform: .square, frequencyHz: 55.0, amplitude: 0.4),
            SynthVoiceSpec(waveform: .whiteNoise, frequencyHz: 100.0, amplitude: 0.25),
            SynthVoiceSpec(waveform: .seismicFM, frequencyHz: 300.0, amplitude: 0.6, fmModulationIndex: 3.0, fmModulatorFrequencyHz: 12.0)
        ]

        let pcm = ProceduralAudioSynthesizer.synthesize(
            voices: voices,
            durationSeconds: 0.2,
            sampleRate: 24_000.0,
            masterGain: 1.8
        )
        #expect(pcm.count == 4_800)
        for s in pcm {
            #expect(s.isFinite)
            #expect(s >= -1.0 && s <= 1.0)
        }

        #expect(ProceduralAudioSynthesizer.synthesize(voices: [], durationSeconds: 1.0).isEmpty)
        #expect(ProceduralAudioSynthesizer.synthesize(voices: voices, durationSeconds: -1.0).isEmpty)
        #expect(ProceduralAudioSynthesizer.synthesize(voices: voices, durationSeconds: 1.0, sampleRate: .nan).isEmpty)
    }

    @Test("ADSR envelope boundary and hostile duration invariants")
    func adsrEnvelopeBoundaryAndHostileDurationInvariants() {
        let env = ADSREnvelope(attackSeconds: 0.1, decaySeconds: 0.2, sustainLevel: 0.6, releaseSeconds: 0.1)
        let total = 1.0

        #expect(abs(env.amplitude(at: 0.0, totalDurationSeconds: total) - 0.0) < 1e-6)
        #expect(abs(env.amplitude(at: 0.05, totalDurationSeconds: total) - 0.5) < 1e-6)
        #expect(abs(env.amplitude(at: 0.1, totalDurationSeconds: total) - 1.0) < 1e-6)
        #expect(abs(env.amplitude(at: 0.2, totalDurationSeconds: total) - 0.8) < 1e-6)
        #expect(abs(env.amplitude(at: 0.5, totalDurationSeconds: total) - 0.6) < 1e-6)
        #expect(abs(env.amplitude(at: 0.95, totalDurationSeconds: total) - 0.3) < 1e-6)
        #expect(abs(env.amplitude(at: 1.0, totalDurationSeconds: total) - 0.0) < 1e-6)

        #expect(env.amplitude(at: -0.1, totalDurationSeconds: total) == 0.0)
        #expect(env.amplitude(at: 1.5, totalDurationSeconds: total) == 0.0)
        #expect(env.amplitude(at: .nan, totalDurationSeconds: total) == 0.0)
        #expect(env.amplitude(at: 0.2, totalDurationSeconds: 0.0) == 0.0)
    }

    @Test("Seismic trace sonification scales acoustic energy with PGA and STA/LTA")
    func seismicTraceSonificationProducesModulatedAudio() {
        let quietTrace = Array(repeating: 0.5, count: 20)
        let burstTrace = Array(repeating: 95.0, count: 20)
        let ratiosQuiet = Array(repeating: 1.0, count: 20)
        let ratiosBurst = Array(repeating: 5.5, count: 20)

        let quietAudio = ProceduralAudioSynthesizer.sonifySeismicTrace(
            magnitudesMg: quietTrace,
            staLtaRatios: ratiosQuiet,
            sampleIntervalSeconds: 0.02,
            audioSampleRate: 24_000.0
        )
        let burstAudio = ProceduralAudioSynthesizer.sonifySeismicTrace(
            magnitudesMg: burstTrace,
            staLtaRatios: ratiosBurst,
            sampleIntervalSeconds: 0.02,
            audioSampleRate: 24_000.0
        )

        let quietAnalysis = ProceduralAudioSynthesizer.analyzePCM(samples: quietAudio, sampleRate: 24_000.0)
        let burstAnalysis = ProceduralAudioSynthesizer.analyzePCM(samples: burstAudio, sampleRate: 24_000.0)

        #expect(burstAnalysis.rmsPower > quietAnalysis.rmsPower * 3.0)
    }

    @Test("RIFF/WAVE 16-bit PCM encode and decode roundtrip fidelity")
    func wavCodecPCM16RoundtripFidelity() throws {
        let voice = SynthVoiceSpec(waveform: .sine, frequencyHz: 261.63, amplitude: 0.75, envelope: .organFlat)
        let original = ProceduralAudioSynthesizer.synthesize(
            voices: [voice],
            durationSeconds: 0.05,
            sampleRate: 48_000.0
        )

        let wavData = try WAVCodec.encodePCM16WAV(samples: original, sampleRate: 48_000, channels: 1)
        #expect(wavData.count == 44 + original.count * 2)

        let decoded = try WAVCodec.decodeWAV(data: wavData)
        #expect(decoded.sampleRate == 48_000)
        #expect(decoded.channels == 1)
        #expect(decoded.bitsPerSample == 16)
        #expect(decoded.frameCount == original.count)

        for i in 0..<original.count {
            #expect(abs(decoded.monoSamples[i] - original[i]) <= 0.0001)
        }
    }

    @Test("WAVCodec stereo file disk write and downmix roundtrip")
    func wavCodecStereoAndFileDiskRoundtrip() throws {
        let interleaved: [Float] = [0.25, -0.25, 0.5, -0.5, 0.75, -0.75, 0.0, 0.0]
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shakeandsound_test_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try WAVCodec.writePCM16WAV(samples: interleaved, sampleRate: 44_100, channels: 2, to: tempURL)
        let fileData = try Data(contentsOf: tempURL)
        let decoded = try WAVCodec.decodeWAV(data: fileData)

        #expect(decoded.sampleRate == 44_100)
        #expect(decoded.channels == 2)
        #expect(decoded.frameCount == 4)
        for m in decoded.monoSamples {
            #expect(abs(m) <= 0.0001)
        }
    }

    @Test("WAVCodec rejects hostile and malformed containers with typed errors")
    func wavCodecHostileAndMalformedContainerRejection() {
        #expect(throws: WAVCodecError.invalidSampleRate) {
            try WAVCodec.encodePCM16WAV(samples: [0.1], sampleRate: 0, channels: 1)
        }
        #expect(throws: WAVCodecError.invalidChannelCount) {
            try WAVCodec.encodePCM16WAV(samples: [0.1], sampleRate: 48_000, channels: 0)
        }
        #expect(throws: WAVCodecError.emptyAudioBuffer) {
            try WAVCodec.encodePCM16WAV(samples: [], sampleRate: 48_000, channels: 1)
        }
        #expect(throws: WAVCodecError.dataTooShort) {
            try WAVCodec.decodeWAV(data: Data([0x52, 0x49, 0x46, 0x46]))
        }

        let badMagic = Data(repeating: 0x41, count: 64)
        #expect(throws: WAVCodecError.invalidRIFFHeader) {
            try WAVCodec.decodeWAV(data: badMagic)
        }

        if var valid = try? WAVCodec.encodePCM16WAV(samples: [0.1, 0.2, 0.3, 0.4], sampleRate: 48_000, channels: 1) {
            valid[40] = 0x3F
            valid[41] = 0x42
            valid[42] = 0x0F
            valid[43] = 0x00
            #expect(throws: WAVCodecError.truncatedDataChunk) {
                try WAVCodec.decodeWAV(data: valid)
            }
        }
    }

    @Test("Adaptive response curves preserve monotonicity and [0, 1] bounds")
    func responseCurvesMonotonicityAndBoundsProperty() {
        let curves: [ResponseCurveKind] = [
            .linear,
            .exponential(gamma: 2.2),
            .logarithmic(curvature: 9.0),
            .sCurveSigmoid(steepness: 8.0, midpoint: 0.5),
            .equalLoudnessContour(frequencyHz: 1_000.0)
        ]

        for curve in curves {
            #expect(abs(TempoHapticCurveEngine.evaluateCurve(curve, input: 0.0) - 0.0) < 1e-6)
            #expect(abs(TempoHapticCurveEngine.evaluateCurve(curve, input: 1.0) - 1.0) < 1e-6)
            #expect(TempoHapticCurveEngine.evaluateCurve(curve, input: .nan) == 0.0)
            #expect(TempoHapticCurveEngine.evaluateCurve(curve, input: -5.0) == 0.0)
            #expect(TempoHapticCurveEngine.evaluateCurve(curve, input: 5.0) == 1.0)

            var prev = 0.0
            for step in 0...100 {
                let x = Double(step) / 100.0
                let y = TempoHapticCurveEngine.evaluateCurve(curve, input: x)
                #expect(y.isFinite)
                #expect(y >= 0.0 && y <= 1.0)
                #expect(y + 1e-9 >= prev)
                prev = y
            }
        }
    }

    @Test("Dynamic range compressor attenuates peaks above threshold and sanitizes non-finite values")
    func dynamicRangeCompressorAttenuatesPeaksAboveThreshold() {
        let config = DynamicCompressorConfig(
            thresholdDb: -18.0,
            ratio: 6.0,
            attackMs: 2.0,
            releaseMs: 50.0,
            makeupGainDb: 0.0
        )
        let input = Array(repeating: 0.05, count: 20) + Array(repeating: 0.90, count: 40) + [.nan, .infinity, -1.0]
        let compressed = TempoHapticCurveEngine.applyDynamicCompression(
            envelope: input,
            sampleRateHz: 100.0,
            config: config
        )

        #expect(compressed.count == input.count)
        for v in compressed {
            #expect(v.isFinite)
            #expect(v >= 0.0 && v <= 1.0)
        }
        #expect(compressed[55] < 0.60)
    }

    @Test("Tempo estimation recovers target BPM across 80..150 BPM range")
    func tempoEstimationAccuracyAcrossBPMRange() {
        let targetBPMs: [Double] = [80.0, 100.0, 120.0, 150.0]

        for target in targetBPMs {
            let envelope = TempoHapticCurveEngine.generateRhythmicEnvelope(
                bpm: target,
                durationSeconds: 5.0,
                frameRateHz: 100.0
            )
            let result = TempoHapticCurveEngine.estimateTempo(
                energyEnvelope: envelope,
                frameRateHz: 100.0
            )
            #expect(abs(result.estimatedBPM - target) <= 3.0)
            #expect(result.confidence > 0.70)
            #expect(result.onsetTimestamps.count >= 5)
        }
    }

    @Test("Synchronized haptic frame generation produces bounded intensity, sharpness, and beat accents")
    func synchronizedHapticFrameGenerationAndBeatAccents() {
        let envelope = TempoHapticCurveEngine.generateRhythmicEnvelope(
            bpm: 120.0,
            durationSeconds: 3.0,
            frameRateHz: 100.0
        )
        let (tempo, frames) = TempoHapticCurveEngine.generateSynchronizedHapticFrames(
            energyEnvelope: envelope,
            frameRateHz: 100.0,
            curve: .sCurveSigmoid(steepness: 8.0, midpoint: 0.45)
        )

        #expect(abs(tempo.estimatedBPM - 120.0) <= 3.0)
        #expect(frames.count == envelope.count)
        let accentFrames = frames.filter(\.isBeatAccent)
        #expect(accentFrames.count > 3)

        for frame in frames {
            #expect(frame.intensity >= 0.0 && frame.intensity <= 1.0)
            #expect(frame.sharpness >= 0.0 && frame.sharpness <= 1.0)
            #expect(frame.beatPhase >= 0.0 && frame.beatPhase < 1.0)
        }
    }

    @Test("End-to-end benchmark suite verification and JSON roundtrip")
    func endToEndBenchmarkSuiteVerification() throws {
        let report = ShakeAndSoundBenchmarkSuite.run(iterations: 6)
        #expect(report.version == "0.2.0")
        #expect(report.allVerificationsPassed)
        #expect(report.metrics.count == 4)

        for metric in report.metrics {
            #expect(metric.verificationPassed)
            #expect(metric.throughputPerSecond > 0.0)
        }

        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(ShakeAndSoundBenchmarkReport.self, from: encoded)
        #expect(decoded == report)
    }
}
