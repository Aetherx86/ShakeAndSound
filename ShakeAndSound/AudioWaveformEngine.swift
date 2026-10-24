import Foundation
import AVFoundation
import Accelerate
import Combine

public struct AcousticVoiceFeatures: Sendable {
    public let level: Float
    public let bands: [Float]
    public let pitchHz: Float
    public let spectralCentroid: Float
    public let isVoiceActive: Bool
}

/// Real-time audio engine that captures microphone input and calculates
/// dynamic audio levels, RMS power, pitch tracking (F0), and frequency spectrum bands.
@MainActor
public final class AudioWaveformEngine: ObservableObject {
    public static let shared = AudioWaveformEngine()

    // MARK: - Published Properties for UI / Visualizer
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var audioLevel: Float = 0.0          // Normalized 0.0 ... 1.0 (smooth)
    @Published public private(set) var rawLevel: Float = 0.0            // Instantaneous peak
    @Published public private(set) var frequencyBands: [Float] = Array(repeating: 0.05, count: 16)
    @Published public private(set) var currentPitchHz: Float = 0.0      // Real-time voice pitch
    @Published public private(set) var isVoiceActive: Bool = false      // Voice activity detection
    @Published public private(set) var recordingDuration: TimeInterval = 0.0
    @Published public var errorMessage: String? = nil

    // MARK: - Internal Audio Components
    private var audioEngine: AVAudioEngine?
    private var timer: Timer?
    private var startTime: Date?

    // Audio buffer tap handler callbacks
    public var onBufferReceived: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    public var onAcousticFeatures: ((AcousticVoiceFeatures) -> Void)?

    private let smoothingFactor: Float = 0.35
    private let targetBandCount = 16

    public init() {}

    // MARK: - Start / Stop
    public func start() throws {
        guard !isRunning else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "AudioWaveformEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio hardware format"])
        }

        // Initialize sound classification analyzer (cough & noise filter)
        AudioClassifierService.shared.prepareAnalyzer(format: inputFormat)

        let bufferSize: AVAudioFrameCount = 1024
        let sampleRate = inputFormat.sampleRate

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            // 1. Analyze level, frequency spectrum, pitch and voice activity
            Self.analyzeBuffer(buffer: buffer, sampleRate: sampleRate) { [weak self] features in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.updateLevels(features: features)
                    self.onAcousticFeatures?(features)
                }
            }

            // 2. Stream buffer to sound classifier (cough/noise)
            Task { @MainActor in
                AudioClassifierService.shared.analyzeBuffer(buffer)
            }

            // 3. Forward to speech recognizer immediately (thread-safe for AVAudioPCMBuffer)
            self.onBufferReceived?(buffer, time)
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.isRunning = true
        self.errorMessage = nil
        self.startTime = Date()
        self.recordingDuration = 0

        self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.startTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    public func stop() {
        guard isRunning else { return }

        timer?.invalidate()
        timer = nil
        startTime = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        AudioClassifierService.shared.reset()

        isRunning = false
        audioLevel = 0.0
        rawLevel = 0.0
        currentPitchHz = 0.0
        isVoiceActive = false
        frequencyBands = Array(repeating: 0.05, count: targetBandCount)
    }

    private func updateLevels(features: AcousticVoiceFeatures) {
        self.rawLevel = features.level
        self.audioLevel = self.audioLevel * (1.0 - self.smoothingFactor) + features.level * self.smoothingFactor

        if features.pitchHz > 60.0 {
            self.currentPitchHz = self.currentPitchHz == 0.0 ? features.pitchHz : (self.currentPitchHz * 0.7 + features.pitchHz * 0.3)
        } else if !features.isVoiceActive {
            self.currentPitchHz = 0.0
        }
        self.isVoiceActive = features.isVoiceActive

        var smoothedBands = self.frequencyBands
        for i in 0..<min(features.bands.count, smoothedBands.count) {
            smoothedBands[i] = smoothedBands[i] * 0.4 + features.bands[i] * 0.6
        }
        self.frequencyBands = smoothedBands
    }

    // MARK: - Buffer Analysis (Nonisolated)
    private nonisolated static func analyzeBuffer(
        buffer: AVAudioPCMBuffer,
        sampleRate: Double,
        completion: @escaping @Sendable (AcousticVoiceFeatures) -> Void
    ) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // 1. Calculate RMS power
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))

        let minDb: Float = -60.0
        let db = 20.0 * log10(max(rms, 0.00001))
        var normalizedLevel = (db - minDb) / (0.0 - minDb)
        normalizedLevel = max(0.0, min(1.0, normalizedLevel))

        // 2. Frequency bands
        let bandCount = 16
        var bands = [Float](repeating: 0.02, count: bandCount)
        let chunkSize = max(1, frameLength / bandCount)

        var weightedSum: Float = 0.0
        var totalEnergy: Float = 0.0

        for b in 0..<bandCount {
            let start = b * chunkSize
            let end = min(frameLength, start + chunkSize)
            if start < end {
                var bandRms: Float = 0.0
                vDSP_rmsqv(channelData.advanced(by: start), 1, &bandRms, vDSP_Length(end - start))
                let bandDb = 20.0 * log10(max(bandRms, 0.0001))
                let bandNorm = max(0.02, min(1.0, (bandDb + 55.0) / 55.0))
                bands[b] = bandNorm

                weightedSum += Float(b + 1) * bandNorm
                totalEnergy += bandNorm
            }
        }

        let centroid = totalEnergy > 0 ? (weightedSum / totalEnergy) : 1.0

        // 3. Fundamental Pitch F0 estimation via Autocorrelation
        let pitch = estimateFundamentalPitch(channelData: channelData, frameLength: frameLength, sampleRate: sampleRate)
        let isVoice = normalizedLevel > 0.07 && (pitch > 65.0 || normalizedLevel > 0.25)

        let features = AcousticVoiceFeatures(
            level: normalizedLevel,
            bands: bands,
            pitchHz: pitch,
            spectralCentroid: centroid,
            isVoiceActive: isVoice
        )
        completion(features)
    }

    private nonisolated static func estimateFundamentalPitch(
        channelData: UnsafePointer<Float>,
        frameLength: Int,
        sampleRate: Double
    ) -> Float {
        guard frameLength >= 512, sampleRate > 0 else { return 0.0 }

        let minFreq: Double = 75.0   // Male voice lower bound
        let maxFreq: Double = 350.0  // High voice upper bound
        let minLag = max(1, Int(sampleRate / maxFreq))
        let maxLag = min(frameLength / 2, Int(sampleRate / minFreq))
        guard minLag < maxLag else { return 0.0 }

        var maxCorr: Float = 0.0
        var bestLag = 0

        var energy0: Float = 0.0
        vDSP_svesq(channelData, 1, &energy0, vDSP_Length(maxLag))
        guard energy0 > 0.0005 else { return 0.0 }

        for lag in stride(from: minLag, through: maxLag, by: 2) {
            var corr: Float = 0.0
            vDSP_dotpr(channelData, 1, channelData.advanced(by: lag), 1, &corr, vDSP_Length(maxLag))
            if corr > maxCorr {
                maxCorr = corr
                bestLag = lag
            }
        }

        let normalizedCorr = maxCorr / energy0
        if normalizedCorr > 0.28 && bestLag > 0 {
            return Float(sampleRate / Double(bestLag))
        }
        return 0.0
    }
}
