import Foundation
import Accelerate

nonisolated public enum SynthWaveform: String, Codable, CaseIterable, Sendable {
    case sine = "sine"
    case triangle = "triangle"
    case sawtooth = "sawtooth"
    case square = "square"
    case whiteNoise = "white_noise"
    case seismicFM = "seismic_fm"
}

nonisolated public struct ADSREnvelope: Codable, Equatable, Sendable {
    public var attackSeconds: Double
    public var decaySeconds: Double
    public var sustainLevel: Double
    public var releaseSeconds: Double

    public static let defaultVoice = ADSREnvelope(
        attackSeconds: 0.015,
        decaySeconds: 0.06,
        sustainLevel: 0.82,
        releaseSeconds: 0.05
    )

    public static let organFlat = ADSREnvelope(
        attackSeconds: 0.005,
        decaySeconds: 0.0,
        sustainLevel: 1.0,
        releaseSeconds: 0.005
    )

    public init(
        attackSeconds: Double = 0.015,
        decaySeconds: Double = 0.06,
        sustainLevel: Double = 0.82,
        releaseSeconds: Double = 0.05
    ) {
        self.attackSeconds = (attackSeconds.isFinite && attackSeconds >= 0.0) ? attackSeconds : 0.015
        self.decaySeconds = (decaySeconds.isFinite && decaySeconds >= 0.0) ? decaySeconds : 0.06
        self.sustainLevel = sustainLevel.isFinite ? min(1.0, max(0.0, sustainLevel)) : 0.82
        self.releaseSeconds = (releaseSeconds.isFinite && releaseSeconds >= 0.0) ? releaseSeconds : 0.05
    }

    public func amplitude(at timeSeconds: Double, totalDurationSeconds: Double) -> Double {
        guard timeSeconds.isFinite, totalDurationSeconds.isFinite,
              timeSeconds >= 0.0, totalDurationSeconds > 0.0,
              timeSeconds <= totalDurationSeconds else {
            return 0.0
        }

        let releaseStart = max(0.0, totalDurationSeconds - releaseSeconds)
        let baseLevel: Double
        if attackSeconds > 1e-6 && timeSeconds < attackSeconds {
            baseLevel = timeSeconds / attackSeconds
        } else if decaySeconds > 1e-6 && timeSeconds < (attackSeconds + decaySeconds) {
            let decayProgress = (timeSeconds - attackSeconds) / decaySeconds
            baseLevel = 1.0 - (1.0 - sustainLevel) * min(1.0, max(0.0, decayProgress))
        } else {
            baseLevel = sustainLevel
        }

        if releaseSeconds > 1e-6 && timeSeconds >= releaseStart {
            let releaseRemaining = max(0.0, totalDurationSeconds - timeSeconds)
            let releaseFactor = min(1.0, releaseRemaining / releaseSeconds)
            return baseLevel * releaseFactor
        }
        return min(1.0, max(0.0, baseLevel))
    }
}

nonisolated public struct SynthVoiceSpec: Codable, Equatable, Sendable {
    public var waveform: SynthWaveform
    public var frequencyHz: Double
    public var endFrequencyHz: Double?
    public var amplitude: Double
    public var phaseOffsetRadians: Double
    public var fmModulationIndex: Double
    public var fmModulatorFrequencyHz: Double
    public var envelope: ADSREnvelope

    public init(
        waveform: SynthWaveform = .sine,
        frequencyHz: Double = 220.0,
        endFrequencyHz: Double? = nil,
        amplitude: Double = 0.7,
        phaseOffsetRadians: Double = 0.0,
        fmModulationIndex: Double = 1.5,
        fmModulatorFrequencyHz: Double = 6.0,
        envelope: ADSREnvelope = .defaultVoice
    ) {
        self.waveform = waveform
        self.frequencyHz = (frequencyHz.isFinite && frequencyHz > 0.0) ? min(24_000.0, frequencyHz) : 220.0
        if let endFreq = endFrequencyHz, endFreq.isFinite, endFreq > 0.0 {
            self.endFrequencyHz = min(24_000.0, endFreq)
        } else {
            self.endFrequencyHz = nil
        }
        self.amplitude = amplitude.isFinite ? min(1.0, max(0.0, amplitude)) : 0.7
        self.phaseOffsetRadians = phaseOffsetRadians.isFinite ? phaseOffsetRadians : 0.0
        self.fmModulationIndex = fmModulationIndex.isFinite ? max(0.0, min(20.0, fmModulationIndex)) : 1.5
        self.fmModulatorFrequencyHz = (fmModulatorFrequencyHz.isFinite && fmModulatorFrequencyHz >= 0.0)
            ? min(5_000.0, fmModulatorFrequencyHz) : 6.0
        self.envelope = envelope
    }
}

nonisolated public struct AcousticSignalAnalysis: Codable, Equatable, Sendable {
    public let frameLength: Int
    public let sampleRate: Double
    public let rmsPower: Float
    public let decibelsFS: Float
    public let normalizedLevel: Float
    public let frequencyBands: [Float]
    public let spectralCentroid: Float
    public let zeroCrossingRateHz: Float
    public let fundamentalPitchHz: Float
    public let isVoiceActive: Bool
}

nonisolated public enum WAVCodecError: Error, LocalizedError, Equatable, Sendable {
    case invalidSampleRate
    case invalidChannelCount
    case emptyAudioBuffer
    case dataTooShort
    case invalidRIFFHeader
    case missingFormatChunk
    case unsupportedAudioFormat(UInt16)
    case unsupportedBitsPerSample(UInt16)
    case missingDataChunk
    case truncatedDataChunk

    public var errorDescription: String? {
        switch self {
        case .invalidSampleRate:
            return "Sample rate must be finite and between 1,000 Hz and 384,000 Hz."
        case .invalidChannelCount:
            return "Channel count must be between 1 and 8."
        case .emptyAudioBuffer:
            return "Audio sample buffer cannot be empty."
        case .dataTooShort:
            return "WAV container is shorter than the minimum 44-byte RIFF header."
        case .invalidRIFFHeader:
            return "Invalid RIFF/WAVE magic header."
        case .missingFormatChunk:
            return "Missing or malformed WAV fmt chunk."
        case .unsupportedAudioFormat(let code):
            return "Unsupported WAV format code \(code) (only PCM=1 and IEEE Float=3 are supported)."
        case .unsupportedBitsPerSample(let bits):
            return "Unsupported WAV bits-per-sample \(bits) (only 16-bit PCM and 32-bit float are supported)."
        case .missingDataChunk:
            return "Missing WAV data chunk."
        case .truncatedDataChunk:
            return "WAV data chunk size exceeds available container bytes."
        }
    }
}

nonisolated public struct DecodedWAVBuffer: Codable, Equatable, Sendable {
    public let sampleRate: Int
    public let channels: Int
    public let bitsPerSample: Int
    public let frameCount: Int
    public let monoSamples: [Float]
    public let interleavedSamples: [Float]
}

nonisolated public enum ProceduralAudioSynthesizer {
    public static func synthesize(
        voices: [SynthVoiceSpec],
        durationSeconds: Double,
        sampleRate: Double = 48_000.0,
        masterGain: Double = 0.85
    ) -> [Float] {
        guard durationSeconds.isFinite, durationSeconds > 0.0,
              sampleRate.isFinite, sampleRate >= 1_000.0, sampleRate <= 384_000.0,
              !voices.isEmpty else {
            return []
        }

        let safeDuration = min(60.0, durationSeconds)
        let frameCount = max(1, Int(round(safeDuration * sampleRate)))
        let safeMasterGain = masterGain.isFinite ? min(2.0, max(0.0, masterGain)) : 0.85
        let dt = 1.0 / sampleRate

        var output = [Double](repeating: 0.0, count: frameCount)
        var prngState: UInt64 = 0x9E37_79B9_7F4A_7C15

        for voice in voices {
            guard voice.amplitude > 0.0 else { continue }
            var phase = voice.phaseOffsetRadians
            var modPhase = 0.0
            let startFreq = voice.frequencyHz
            let endFreq = voice.endFrequencyHz ?? startFreq

            for i in 0..<frameCount {
                let t = Double(i) * dt
                let progress = frameCount > 1 ? Double(i) / Double(frameCount - 1) : 0.0
                let instFreq = startFreq + (endFreq - startFreq) * progress
                let env = voice.envelope.amplitude(at: t, totalDurationSeconds: safeDuration)

                let rawSample: Double
                switch voice.waveform {
                case .sine:
                    rawSample = sin(phase)
                case .triangle:
                    let norm = (phase / (2.0 * Double.pi)).truncatingRemainder(dividingBy: 1.0)
                    let wrapped = norm < 0 ? norm + 1.0 : norm
                    rawSample = 4.0 * abs(wrapped - 0.5) - 1.0
                case .sawtooth:
                    let norm = (phase / (2.0 * Double.pi)).truncatingRemainder(dividingBy: 1.0)
                    let wrapped = norm < 0 ? norm + 1.0 : norm
                    rawSample = 2.0 * wrapped - 1.0
                case .square:
                    rawSample = sin(phase) >= 0.0 ? 1.0 : -1.0
                case .whiteNoise:
                    // Deterministic xorshift64* PRNG for reproducible synthesis
                    prngState ^= prngState >> 12
                    prngState ^= prngState << 25
                    prngState ^= prngState >> 27
                    let randUnit = Double(prngState &* 0x2545_F491_4F6C_DD1D) / Double(UInt64.max)
                    rawSample = 2.0 * randUnit - 1.0
                case .seismicFM:
                    let modSignal = sin(modPhase)
                    rawSample = sin(phase + voice.fmModulationIndex * modSignal)
                }

                output[i] += rawSample * voice.amplitude * env
                phase += 2.0 * Double.pi * instFreq * dt
                if phase > 2.0 * Double.pi * 1024.0 {
                    phase = phase.truncatingRemainder(dividingBy: 2.0 * Double.pi)
                }
                modPhase += 2.0 * Double.pi * voice.fmModulatorFrequencyHz * dt
            }
        }

        // Apply master gain and soft-clipping limiter into [-1.0, 1.0]
        return output.map { sample in
            let scaled = sample * safeMasterGain
            guard scaled.isFinite else { return 0.0 }
            if abs(scaled) > 0.95 {
                return Float(tanh(scaled))
            }
            return Float(min(1.0, max(-1.0, scaled)))
        }
    }

    public static func sonifySeismicTrace(
        magnitudesMg: [Double],
        staLtaRatios: [Double] = [],
        sampleIntervalSeconds: Double = 0.04,
        audioSampleRate: Double = 48_000.0
    ) -> [Float] {
        guard !magnitudesMg.isEmpty,
              sampleIntervalSeconds.isFinite, sampleIntervalSeconds >= 0.001,
              audioSampleRate.isFinite, audioSampleRate >= 8_000.0 else {
            return []
        }

        let safeDt = min(1.0, sampleIntervalSeconds)
        let totalDuration = min(30.0, Double(magnitudesMg.count) * safeDt)
        let totalFrames = max(1, Int(round(totalDuration * audioSampleRate)))
        let audioDt = 1.0 / audioSampleRate

        var result = [Float](repeating: 0.0, count: totalFrames)
        var carrierPhase = 0.0
        var subPhase = 0.0
        var modPhase = 0.0

        for frameIdx in 0..<totalFrames {
            let t = Double(frameIdx) * audioDt
            let tracePos = t / safeDt
            let idx0 = min(magnitudesMg.count - 1, max(0, Int(floor(tracePos))))
            let idx1 = min(magnitudesMg.count - 1, idx0 + 1)
            let frac = tracePos - Double(idx0)

            let m0 = magnitudesMg[idx0].isFinite ? max(0.0, magnitudesMg[idx0]) : 0.0
            let m1 = magnitudesMg[idx1].isFinite ? max(0.0, magnitudesMg[idx1]) : 0.0
            let mag = m0 + (m1 - m0) * frac

            let r0 = (idx0 < staLtaRatios.count && staLtaRatios[idx0].isFinite) ? max(0.5, staLtaRatios[idx0]) : 1.0
            let r1 = (idx1 < staLtaRatios.count && staLtaRatios[idx1].isFinite) ? max(0.5, staLtaRatios[idx1]) : 1.0
            let ratio = r0 + (r1 - r0) * frac

            // Map dynamic PGA (0..150 mg) to carrier frequency (110 Hz .. 440 Hz)
            let normMag = min(1.0, mag / 120.0)
            let carrierFreq = 110.0 + normMag * 330.0
            let modFreq = 4.0 + min(24.0, ratio * 2.5)
            let modIndex = min(5.0, max(0.1, (ratio - 0.8) * 1.1))
            let amp = min(0.92, 0.08 + pow(normMag, 0.75) * 0.84)

            let fmVoice = sin(carrierPhase + modIndex * sin(modPhase))
            let subVoice = 0.35 * sin(subPhase)
            let composite = (0.74 * fmVoice + 0.26 * subVoice) * amp

            result[frameIdx] = Float(min(1.0, max(-1.0, composite)))

            carrierPhase += 2.0 * Double.pi * carrierFreq * audioDt
            subPhase += 2.0 * Double.pi * (carrierFreq * 0.5) * audioDt
            modPhase += 2.0 * Double.pi * modFreq * audioDt
        }

        return result
    }

    public static func analyzePCM(
        samples: [Float],
        sampleRate: Double = 48_000.0
    ) -> AcousticSignalAnalysis {
        let bandCount = 16
        guard !samples.isEmpty, sampleRate.isFinite, sampleRate > 0.0 else {
            return AcousticSignalAnalysis(
                frameLength: 0,
                sampleRate: sampleRate.isFinite && sampleRate > 0 ? sampleRate : 0.0,
                rmsPower: 0.0,
                decibelsFS: -60.0,
                normalizedLevel: 0.0,
                frequencyBands: Array(repeating: 0.02, count: bandCount),
                spectralCentroid: 1.0,
                zeroCrossingRateHz: 0.0,
                fundamentalPitchHz: 0.0,
                isVoiceActive: false
            )
        }

        let sanitized: [Float] = samples.map { s in
            guard s.isFinite else { return 0.0 }
            return min(10.0, max(-10.0, s))
        }
        let frameLength = sanitized.count

        // 1. RMS power via Accelerate vDSP
        var rms: Float = 0.0
        sanitized.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            vDSP_rmsqv(base, 1, &rms, vDSP_Length(frameLength))
        }

        let minDb: Float = -60.0
        let db = 20.0 * log10(max(rms, 0.00001))
        let normalizedLevel = max(0.0, min(1.0, (db - minDb) / (0.0 - minDb)))

        // 2. 16-band energy profile & spectral centroid
        var bands = [Float](repeating: 0.02, count: bandCount)
        let chunkSize = max(1, frameLength / bandCount)
        var weightedSum: Float = 0.0
        var totalEnergy: Float = 0.0

        sanitized.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            for b in 0..<bandCount {
                let start = b * chunkSize
                let end = min(frameLength, start + chunkSize)
                if start < end {
                    var bandRms: Float = 0.0
                    vDSP_rmsqv(base.advanced(by: start), 1, &bandRms, vDSP_Length(end - start))
                    let bandDb = 20.0 * log10(max(bandRms, 0.0001))
                    let bandNorm = max(0.02, min(1.0, (bandDb + 55.0) / 55.0))
                    bands[b] = bandNorm
                    weightedSum += Float(b + 1) * bandNorm
                    totalEnergy += bandNorm
                }
            }
        }
        let centroid = totalEnergy > 0.0 ? (weightedSum / totalEnergy) : 1.0

        // 3. Zero-crossing rate (Hz)
        var zcCount = 0
        var prevSign: Int = 0
        for s in sanitized {
            if s > 0.002 {
                if prevSign < 0 { zcCount += 1 }
                prevSign = 1
            } else if s < -0.002 {
                if prevSign > 0 { zcCount += 1 }
                prevSign = -1
            }
        }
        let durationSec = Double(frameLength) / sampleRate
        let zcrHz = durationSec > 0 ? Float(Double(zcCount) / durationSec) : 0.0

        // 4. Autocorrelation Fundamental Pitch (F0) with parabolic lag refinement
        let pitchHz = sanitized.withUnsafeBufferPointer { ptr -> Float in
            guard let base = ptr.baseAddress else { return 0.0 }
            return estimateFundamentalPitch(
                channelData: base,
                frameLength: frameLength,
                sampleRate: sampleRate
            )
        }

        let isVoice = normalizedLevel > 0.07 && (pitchHz > 65.0 || normalizedLevel > 0.25)

        return AcousticSignalAnalysis(
            frameLength: frameLength,
            sampleRate: sampleRate,
            rmsPower: rms,
            decibelsFS: db,
            normalizedLevel: normalizedLevel,
            frequencyBands: bands,
            spectralCentroid: centroid,
            zeroCrossingRateHz: zcrHz,
            fundamentalPitchHz: pitchHz,
            isVoiceActive: isVoice
        )
    }

    public static func estimateFundamentalPitch(
        channelData: UnsafePointer<Float>,
        frameLength: Int,
        sampleRate: Double
    ) -> Float {
        guard frameLength >= 512, sampleRate.isFinite, sampleRate > 0 else { return 0.0 }

        let minFreq: Double = 65.0
        let maxFreq: Double = 1_000.0
        let minLag = max(2, Int(floor(sampleRate / maxFreq)))
        let maxLag = min(frameLength / 2, Int(ceil(sampleRate / minFreq)))
        guard minLag < maxLag else { return 0.0 }

        let windowLen = min(frameLength - maxLag, max(512, min(2048, frameLength / 2)))
        guard windowLen > 0 else { return 0.0 }

        var energy0: Float = 0.0
        vDSP_svesq(channelData, 1, &energy0, vDSP_Length(windowLen))
        guard energy0 > 0.0005 else { return 0.0 }

        var correlations = [Float](repeating: 0.0, count: maxLag + 2)
        for lag in minLag...min(maxLag + 1, frameLength - windowLen) {
            var corr: Float = 0.0
            vDSP_dotpr(channelData, 1, channelData.advanced(by: lag), 1, &corr, vDSP_Length(windowLen))
            correlations[lag] = corr / energy0
        }

        // Find the first strong local peak after the initial zero-lag descent to avoid sub-harmonic octave halving
        var passedZeroDescent = false
        for lag in minLag...maxLag {
            if correlations[lag] < 0.15 {
                passedZeroDescent = true
                break
            }
        }

        var globalMaxCorr: Float = 0.0
        var globalBestLag = 0
        let searchStart = minLag
        for lag in searchStart...maxLag {
            if correlations[lag] > globalMaxCorr {
                globalMaxCorr = correlations[lag]
                globalBestLag = lag
            }
        }

        guard globalMaxCorr > 0.28, globalBestLag > 0 else { return 0.0 }

        // Pick first local peak reaching at least 88% of global maximum after initial descent
        var chosenLag = globalBestLag
        if passedZeroDescent {
            var inNegativeOrLow = false
            for lag in minLag..<maxLag {
                if correlations[lag] < 0.15 {
                    inNegativeOrLow = true
                }
                if inNegativeOrLow &&
                    correlations[lag] >= globalMaxCorr * 0.88 &&
                    correlations[lag] >= correlations[lag - 1] &&
                    correlations[lag] >= correlations[lag + 1] {
                    chosenLag = lag
                    break
                }
            }
        }

        // Parabolic interpolation around chosenLag for sub-sample frequency precision
        var refinedLag = Double(chosenLag)
        if chosenLag > minLag && chosenLag < maxLag {
            let y1 = Double(correlations[chosenLag - 1])
            let y2 = Double(correlations[chosenLag])
            let y3 = Double(correlations[chosenLag + 1])
            let denom = y1 - 2.0 * y2 + y3
            if abs(denom) > 1e-6 {
                let delta = 0.5 * (y1 - y3) / denom
                if abs(delta) <= 0.5 {
                    refinedLag += delta
                }
            }
        }

        return Float(sampleRate / refinedLag)
    }
}

nonisolated public enum WAVCodec {
    public static func encodePCM16WAV(
        samples: [Float],
        sampleRate: Int = 48_000,
        channels: Int = 1
    ) throws -> Data {
        guard sampleRate >= 1_000 && sampleRate <= 384_000 else {
            throw WAVCodecError.invalidSampleRate
        }
        guard channels >= 1 && channels <= 8 else {
            throw WAVCodecError.invalidChannelCount
        }
        guard !samples.isEmpty else {
            throw WAVCodecError.emptyAudioBuffer
        }

        let bitsPerSample: UInt16 = 16
        let bytesPerSample = Int(bitsPerSample / 8)
        let blockAlign = UInt16(channels * bytesPerSample)
        let byteRate = UInt32(sampleRate * Int(blockAlign))
        let dataByteCount = UInt32(samples.count * bytesPerSample)
        let riffChunkSize = UInt32(36) + dataByteCount

        var data = Data(capacity: Int(44 + dataByteCount))

        func appendASCII(_ str: String) {
            data.append(contentsOf: str.utf8)
        }
        func appendUInt16LE(_ value: UInt16) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendUInt32LE(_ value: UInt32) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendInt16LE(_ value: Int16) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        // RIFF WAVE Header (44 bytes)
        appendASCII("RIFF")
        appendUInt32LE(riffChunkSize)
        appendASCII("WAVE")

        // fmt subchunk
        appendASCII("fmt ")
        appendUInt32LE(16)                  // PCM fmt chunk size
        appendUInt16LE(1)                   // AudioFormat = 1 (Linear PCM)
        appendUInt16LE(UInt16(channels))
        appendUInt32LE(UInt32(sampleRate))
        appendUInt32LE(byteRate)
        appendUInt16LE(blockAlign)
        appendUInt16LE(bitsPerSample)

        // data subchunk
        appendASCII("data")
        appendUInt32LE(dataByteCount)

        for sample in samples {
            let clean = sample.isFinite ? min(1.0, max(-1.0, Double(sample))) : 0.0
            let scaled = Int(round(clean * 32767.0))
            let clamped = Int16(min(Int(Int16.max), max(Int(Int16.min), scaled)))
            appendInt16LE(clamped)
        }

        return data
    }

    public static func writePCM16WAV(
        samples: [Float],
        sampleRate: Int = 48_000,
        channels: Int = 1,
        to url: URL
    ) throws {
        let wavData = try encodePCM16WAV(samples: samples, sampleRate: sampleRate, channels: channels)
        try wavData.write(to: url, options: .atomic)
    }

    public static func decodeWAV(data: Data) throws -> DecodedWAVBuffer {
        guard data.count >= 44 else {
            throw WAVCodecError.dataTooShort
        }

        let bytes = [UInt8](data)

        func readUInt16LE(at offset: Int) -> UInt16 {
            UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }
        func readUInt32LE(at offset: Int) -> UInt32 {
            UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
        }
        func fourCC(at offset: Int) -> String {
            String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii) ?? ""
        }

        guard fourCC(at: 0) == "RIFF", fourCC(at: 8) == "WAVE" else {
            throw WAVCodecError.invalidRIFFHeader
        }

        var cursor = 12
        var audioFormat: UInt16?
        var channels: Int?
        var sampleRate: Int?
        var bitsPerSample: UInt16?
        var dataOffset: Int?
        var dataSize: Int?

        while cursor + 8 <= bytes.count {
            let chunkID = fourCC(at: cursor)
            let chunkLen = Int(readUInt32LE(at: cursor + 4))
            let payloadStart = cursor + 8

            guard chunkLen >= 0, payloadStart + chunkLen <= bytes.count else {
                if chunkID == "data" {
                    throw WAVCodecError.truncatedDataChunk
                }
                break
            }

            if chunkID == "fmt " {
                guard chunkLen >= 16 else {
                    throw WAVCodecError.missingFormatChunk
                }
                audioFormat = readUInt16LE(at: payloadStart)
                channels = Int(readUInt16LE(at: payloadStart + 2))
                sampleRate = Int(readUInt32LE(at: payloadStart + 4))
                bitsPerSample = readUInt16LE(at: payloadStart + 14)
            } else if chunkID == "data" {
                dataOffset = payloadStart
                dataSize = chunkLen
            }

            let paddedChunkLen = chunkLen + (chunkLen % 2)
            cursor = payloadStart + paddedChunkLen
        }

        guard let fmt = audioFormat,
              let ch = channels,
              let sr = sampleRate,
              let bps = bitsPerSample else {
            throw WAVCodecError.missingFormatChunk
        }
        guard sr >= 1_000 && sr <= 384_000 else {
            throw WAVCodecError.invalidSampleRate
        }
        guard ch >= 1 && ch <= 8 else {
            throw WAVCodecError.invalidChannelCount
        }
        guard fmt == 1 || fmt == 3 else {
            throw WAVCodecError.unsupportedAudioFormat(fmt)
        }
        guard (fmt == 1 && bps == 16) || (fmt == 3 && bps == 32) else {
            throw WAVCodecError.unsupportedBitsPerSample(bps)
        }
        guard let dOffset = dataOffset, let dSize = dataSize else {
            throw WAVCodecError.missingDataChunk
        }

        let bytesPerSample = Int(bps / 8)
        let totalSamples = dSize / bytesPerSample
        let frameCount = totalSamples / ch

        var interleaved = [Float]()
        interleaved.reserveCapacity(totalSamples)

        if fmt == 1 && bps == 16 {
            for i in 0..<totalSamples {
                let pos = dOffset + i * 2
                let raw = readUInt16LE(at: pos)
                let signed = Int16(bitPattern: raw)
                interleaved.append(Float(signed) / 32767.0)
            }
        } else if fmt == 3 && bps == 32 {
            for i in 0..<totalSamples {
                let pos = dOffset + i * 4
                let bits = readUInt32LE(at: pos)
                let floatVal = Float(bitPattern: bits)
                interleaved.append(floatVal.isFinite ? min(1.0, max(-1.0, floatVal)) : 0.0)
            }
        }

        var mono = [Float](repeating: 0.0, count: frameCount)
        if ch == 1 {
            mono = interleaved
        } else {
            let invCh = 1.0 / Float(ch)
            for f in 0..<frameCount {
                var sum: Float = 0.0
                let base = f * ch
                for c in 0..<ch {
                    sum += interleaved[base + c]
                }
                mono[f] = sum * invCh
            }
        }

        return DecodedWAVBuffer(
            sampleRate: sr,
            channels: ch,
            bitsPerSample: Int(bps),
            frameCount: frameCount,
            monoSamples: mono,
            interleavedSamples: interleaved
        )
    }
}
