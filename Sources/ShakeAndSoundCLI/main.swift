import Foundation
import ShakeAndSoundCore

struct MotionCommandOutput: Codable, Sendable {
    let version: String
    let requestedPattern: String
    let summary: MotionTraceSummary
}

struct SynthCommandOutput: Codable, Sendable {
    let version: String
    let waveform: String
    let frequencyHz: Double
    let durationSeconds: Double
    let sampleRate: Int
    let sampleCount: Int
    let wavByteCount: Int
    let outputPath: String?
    let analysis: AcousticSignalAnalysis
}

struct TempoCurveCommandOutput: Codable, Sendable {
    let version: String
    let targetBPM: Double
    let curveIdentifier: String
    let tempoEstimate: TempoEstimateResult
    let curvePoints: [Double]
    let hapticFrameCount: Int
    let accentFrameCount: Int
    let peakHapticIntensity: Double
}

enum CLIError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let msg):
            return msg
        }
    }
}

func printUsage() {
    let text = """
    shakeandsound-cli \(ShakeAndSoundVersion.current)
    Headless DSP kinematics, procedural audio synthesis, WAV codec, and tempo/haptic verification CLI.

    USAGE:
      shakeandsound-cli --version
      shakeandsound-cli --help
      shakeandsound-cli analyze-motion [--pattern <idle|tremor|tap|double-tap|shake|shear>] [--samples <N>] [--dt <sec>] [--json]
      shakeandsound-cli synth [--waveform <sine|triangle|sawtooth|square|noise|seismic-fm>] [--freq <Hz>] [--duration <sec>] [--sample-rate <Hz>] [--output <file.wav>] [--json]
      shakeandsound-cli tempo-curve [--bpm <BPM>] [--duration <sec>] [--curve <linear|exponential|logarithmic|sigmoid|loudness>] [--json]
      shakeandsound-cli benchmark [--iterations <N>] [--json]
    """
    print(text)
}

func emitJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    if let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

func parsePattern(_ raw: String) throws -> ShakePatternKind {
    switch raw.lowercased() {
    case "idle":
        return .idle
    case "tremor", "micro_tremor", "micro-tremor":
        return .microTremor
    case "tap", "single-tap", "single_tap_impact":
        return .singleTapImpact
    case "double-tap", "double_tap", "double_tap_impulse":
        return .doubleTapImpulse
    case "shake", "lateral-shake", "rhythmic_lateral_shake":
        return .rhythmicLateralShake
    case "shear", "seismic", "seismic_shear_wave":
        return .seismicShearWave
    default:
        throw CLIError.message("Unknown motion pattern '\(raw)'. Expected idle, tremor, tap, double-tap, shake, or shear.")
    }
}

func parseWaveform(_ raw: String) throws -> SynthWaveform {
    switch raw.lowercased() {
    case "sine":
        return .sine
    case "triangle":
        return .triangle
    case "sawtooth", "saw":
        return .sawtooth
    case "square":
        return .square
    case "noise", "white_noise", "white-noise":
        return .whiteNoise
    case "seismic-fm", "seismic_fm", "fm":
        return .seismicFM
    default:
        throw CLIError.message("Unknown waveform '\(raw)'. Expected sine, triangle, sawtooth, square, noise, or seismic-fm.")
    }
}

func parseCurve(_ raw: String) throws -> ResponseCurveKind {
    switch raw.lowercased() {
    case "linear":
        return .linear
    case "exponential", "exp":
        return .exponential(gamma: 2.2)
    case "logarithmic", "log":
        return .logarithmic(curvature: 9.0)
    case "sigmoid", "s-curve", "scurve":
        return .sCurveSigmoid(steepness: 8.0, midpoint: 0.5)
    case "loudness", "equal-loudness":
        return .equalLoudnessContour(frequencyHz: 1_000.0)
    default:
        throw CLIError.message("Unknown curve '\(raw)'. Expected linear, exponential, logarithmic, sigmoid, or loudness.")
    }
}

func runAnalyzeMotion(args: [String]) throws {
    var pattern: ShakePatternKind = .rhythmicLateralShake
    var samples = 64
    var dt = 0.04
    var jsonOutput = false

    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--json":
            jsonOutput = true
        case "--pattern":
            guard i + 1 < args.count else { throw CLIError.message("Missing value for --pattern") }
            i += 1
            pattern = try parsePattern(args[i])
        case "--samples":
            guard i + 1 < args.count, let val = Int(args[i + 1]), val >= 8 && val <= 4096 else {
                throw CLIError.message("--samples requires an integer between 8 and 4096")
            }
            i += 1
            samples = val
        case "--dt":
            guard i + 1 < args.count, let val = Double(args[i + 1]), val.isFinite && val >= 0.001 && val <= 1.0 else {
                throw CLIError.message("--dt requires a finite interval between 0.001 and 1.0 seconds")
            }
            i += 1
            dt = val
        default:
            throw CLIError.message("Unknown option '\(arg)' for analyze-motion")
        }
        i += 1
    }

    let gravity = Vector3D(x: 110.0, y: -75.0, z: 980.0)
    let trace = ShakeAndSoundBenchmarkSuite.generateSyntheticMotionTrace(
        pattern: pattern,
        sampleCount: samples,
        dt: dt,
        gravityVectorMg: gravity
    )
    var engine = MotionKinematicsEngine(
        config: MotionKinematicConfig(initialGravityMg: gravity)
    )
    let summary = engine.analyzeTrace(samples: trace, dt: dt)

    if jsonOutput {
        let payload = MotionCommandOutput(
            version: ShakeAndSoundVersion.current,
            requestedPattern: pattern.rawValue,
            summary: summary
        )
        try emitJSON(payload)
    } else {
        print("ShakeAndSound Motion Kinematics Report (v\(ShakeAndSoundVersion.current))")
        print("  Requested Pattern      : \(pattern.rawValue)")
        print("  Classified Pattern     : \(summary.dominantPattern.rawValue) (\(summary.dominantPattern.displayLabel))")
        print("  Samples / Duration     : \(summary.sampleCount) samples (\(String(format: "%.2f", summary.totalDurationSeconds)) s)")
        print("  Isolated Gravity (mg)  : (\(String(format: "%.1f", summary.finalIsolatedGravityMg.x)), \(String(format: "%.1f", summary.finalIsolatedGravityMg.y)), \(String(format: "%.1f", summary.finalIsolatedGravityMg.z)))")
        print("  Peak Dynamic PGA       : \(String(format: "%.2f", summary.peakDynamicPGA)) mg")
        print("  RMS Dynamic Accel      : \(String(format: "%.2f", summary.rmsDynamicAccelerationMg)) mg")
        print("  Peak Jerk              : \(String(format: "%.1f", summary.peakJerkMgPerSec)) mg/s")
        print("  Peak STA/LTA Ratio     : \(String(format: "%.2f", summary.peakStaLtaRatio))")
        print("  Arias Intensity        : \(String(format: "%.4f", summary.cumulativeAriasIntensityMmPerSec)) mm/s")
        print("  Dominant Frequency     : \(String(format: "%.2f", summary.dominantFrequencyHz)) Hz")
        print("  Zero-Crossing Rate     : \(String(format: "%.2f", summary.zeroCrossingRateHz)) Hz")
        print("  Crest Factor           : \(String(format: "%.2f", summary.crestFactor))")
    }
}

func runSynth(args: [String]) throws {
    var waveform: SynthWaveform = .sine
    var freq = 220.0
    var duration = 0.25
    var sampleRate = 48_000
    var outputPath: String?
    var jsonOutput = false

    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--json":
            jsonOutput = true
        case "--waveform":
            guard i + 1 < args.count else { throw CLIError.message("Missing value for --waveform") }
            i += 1
            waveform = try parseWaveform(args[i])
        case "--freq":
            guard i + 1 < args.count, let val = Double(args[i + 1]), val.isFinite && val >= 20.0 && val <= 20_000.0 else {
                throw CLIError.message("--freq requires a frequency between 20 and 20000 Hz")
            }
            i += 1
            freq = val
        case "--duration":
            guard i + 1 < args.count, let val = Double(args[i + 1]), val.isFinite && val >= 0.02 && val <= 30.0 else {
                throw CLIError.message("--duration requires a duration between 0.02 and 30.0 seconds")
            }
            i += 1
            duration = val
        case "--sample-rate":
            guard i + 1 < args.count, let val = Int(args[i + 1]), val >= 8_000 && val <= 192_000 else {
                throw CLIError.message("--sample-rate requires an integer between 8000 and 192000 Hz")
            }
            i += 1
            sampleRate = val
        case "--output":
            guard i + 1 < args.count, !args[i + 1].isEmpty else {
                throw CLIError.message("Missing file path for --output")
            }
            i += 1
            outputPath = args[i]
        default:
            throw CLIError.message("Unknown option '\(arg)' for synth")
        }
        i += 1
    }

    let voice = SynthVoiceSpec(
        waveform: waveform,
        frequencyHz: freq,
        amplitude: 0.80,
        envelope: .organFlat
    )
    let samples = ProceduralAudioSynthesizer.synthesize(
        voices: [voice],
        durationSeconds: duration,
        sampleRate: Double(sampleRate)
    )
    let analysis = ProceduralAudioSynthesizer.analyzePCM(
        samples: samples,
        sampleRate: Double(sampleRate)
    )
    let wavData = try WAVCodec.encodePCM16WAV(
        samples: samples,
        sampleRate: sampleRate,
        channels: 1
    )

    if let path = outputPath {
        let url = URL(fileURLWithPath: path)
        try wavData.write(to: url, options: .atomic)
    }

    if jsonOutput {
        let payload = SynthCommandOutput(
            version: ShakeAndSoundVersion.current,
            waveform: waveform.rawValue,
            frequencyHz: freq,
            durationSeconds: duration,
            sampleRate: sampleRate,
            sampleCount: samples.count,
            wavByteCount: wavData.count,
            outputPath: outputPath,
            analysis: analysis
        )
        try emitJSON(payload)
    } else {
        print("ShakeAndSound Procedural Synthesis & DSP Report (v\(ShakeAndSoundVersion.current))")
        print("  Waveform               : \(waveform.rawValue)")
        print("  Target Frequency       : \(String(format: "%.2f", freq)) Hz")
        print("  Detected Pitch (F0)    : \(String(format: "%.2f", analysis.fundamentalPitchHz)) Hz")
        print("  Sample Rate / Frames   : \(sampleRate) Hz / \(samples.count) frames")
        print("  RMS Power / dBFS       : \(String(format: "%.4f", analysis.rmsPower)) (\(String(format: "%.2f", analysis.decibelsFS)) dBFS)")
        print("  Spectral Centroid      : \(String(format: "%.2f", analysis.spectralCentroid))")
        print("  RIFF WAV Container     : \(wavData.count) bytes")
        if let path = outputPath {
            print("  Saved WAV File         : \(path)")
        }
    }
}

func runTempoCurve(args: [String]) throws {
    var bpm = 120.0
    var duration = 4.0
    var curve: ResponseCurveKind = .sCurveSigmoid(steepness: 8.0, midpoint: 0.5)
    var jsonOutput = false

    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--json":
            jsonOutput = true
        case "--bpm":
            guard i + 1 < args.count, let val = Double(args[i + 1]), val.isFinite && val >= 40.0 && val <= 220.0 else {
                throw CLIError.message("--bpm requires a value between 40 and 220 BPM")
            }
            i += 1
            bpm = val
        case "--duration":
            guard i + 1 < args.count, let val = Double(args[i + 1]), val.isFinite && val >= 1.0 && val <= 30.0 else {
                throw CLIError.message("--duration requires a value between 1.0 and 30.0 seconds")
            }
            i += 1
            duration = val
        case "--curve":
            guard i + 1 < args.count else { throw CLIError.message("Missing value for --curve") }
            i += 1
            curve = try parseCurve(args[i])
        default:
            throw CLIError.message("Unknown option '\(arg)' for tempo-curve")
        }
        i += 1
    }

    let envelope = TempoHapticCurveEngine.generateRhythmicEnvelope(
        bpm: bpm,
        durationSeconds: duration,
        frameRateHz: 100.0
    )
    let (tempo, frames) = TempoHapticCurveEngine.generateSynchronizedHapticFrames(
        energyEnvelope: envelope,
        frameRateHz: 100.0,
        curve: curve
    )
    let gridInputs = [0.0, 0.25, 0.5, 0.75, 1.0]
    let curvePoints = gridInputs.map { TempoHapticCurveEngine.evaluateCurve(curve, input: $0) }
    let accentCount = frames.filter(\.isBeatAccent).count
    let peakIntensity = frames.map(\.intensity).max() ?? 0.0

    if jsonOutput {
        let payload = TempoCurveCommandOutput(
            version: ShakeAndSoundVersion.current,
            targetBPM: bpm,
            curveIdentifier: curve.identifier,
            tempoEstimate: tempo,
            curvePoints: curvePoints,
            hapticFrameCount: frames.count,
            accentFrameCount: accentCount,
            peakHapticIntensity: peakIntensity
        )
        try emitJSON(payload)
    } else {
        print("ShakeAndSound Tempo & Adaptive Haptic Curve Report (v\(ShakeAndSoundVersion.current))")
        print("  Target BPM             : \(String(format: "%.2f", bpm))")
        print("  Estimated BPM          : \(String(format: "%.2f", tempo.estimatedBPM)) (confidence: \(String(format: "%.2f", tempo.confidence)))")
        print("  Detected Beat Onsets   : \(tempo.onsetTimestamps.count)")
        print("  Response Curve         : \(curve.identifier)")
        print("  Curve Grid [0..1]      : \(curvePoints.map { String(format: "%.3f", $0) }.joined(separator: ", "))")
        print("  Haptic Frames / Accents: \(frames.count) frames / \(accentCount) beat accents")
    }
}

func runBenchmark(args: [String]) throws {
    var iterations = 25
    var jsonOutput = false

    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--json":
            jsonOutput = true
        case "--iterations":
            guard i + 1 < args.count, let val = Int(args[i + 1]), val >= 1 && val <= 500 else {
                throw CLIError.message("--iterations requires an integer between 1 and 500")
            }
            i += 1
            iterations = val
        default:
            throw CLIError.message("Unknown option '\(arg)' for benchmark")
        }
        i += 1
    }

    let report = ShakeAndSoundBenchmarkSuite.run(iterations: iterations)
    if jsonOutput {
        try emitJSON(report)
    } else {
        print("ShakeAndSound DSP Benchmark Suite (v\(report.version), iterations=\(report.iterations))")
        for m in report.metrics {
            let status = m.verificationPassed ? "PASS" : "FAIL"
            print("  [\(status)] \(m.subsystem): \(m.totalItemsProcessed) items in \(String(format: "%.2f", m.elapsedMilliseconds)) ms (\(String(format: "%.0f", m.throughputPerSecond)) items/s)")
        }
        print("Overall Verification: \(report.allVerificationsPassed ? "PASSED" : "FAILED")")
    }

    if !report.allVerificationsPassed {
        throw CLIError.message("One or more subsystem benchmark verifications failed")
    }
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let first = args.first else {
        printUsage()
        exit(0)
    }

    let rest = Array(args.dropFirst())
    switch first {
    case "--version", "-v", "version":
        print("shakeandsound-cli \(ShakeAndSoundVersion.current)")
    case "--help", "-h", "help":
        printUsage()
    case "analyze-motion":
        try runAnalyzeMotion(args: rest)
    case "synth":
        try runSynth(args: rest)
    case "tempo-curve":
        try runTempoCurve(args: rest)
    case "benchmark":
        try runBenchmark(args: rest)
    default:
        throw CLIError.message("Unknown command '\(first)'. Run 'shakeandsound-cli --help' for usage.")
    }
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
