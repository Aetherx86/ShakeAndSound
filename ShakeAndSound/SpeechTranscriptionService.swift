import Foundation
import Speech
import NaturalLanguage
import AVFoundation
import Combine

public struct TranscriptionSegment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public let speakerId: Int
    public let speakerName: String
    public let detectedLanguage: String
    public let speakerPitchHz: Float?
    public let acousticLabel: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        text: String,
        speakerId: Int = 1,
        speakerName: String = "화자 1",
        detectedLanguage: String = "🇰🇷 한국어",
        speakerPitchHz: Float? = nil,
        acousticLabel: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.speakerId = speakerId
        self.speakerName = speakerName
        self.detectedLanguage = detectedLanguage
        self.speakerPitchHz = speakerPitchHz
        self.acousticLabel = acousticLabel
    }
}

public struct VoiceBiometricProfile: Sendable, Identifiable {
    public let id: Int // 1, 2, 3
    public var name: String
    public var averagePitchHz: Float
    public var sampleCount: Int

    public var pitchDescription: String {
        guard averagePitchHz > 0 else { return "음성 프로필 대기 중" }
        let hz = Int(averagePitchHz)
        if averagePitchHz < 140 {
            return "\(hz) Hz • 굵은 저음"
        } else if averagePitchHz < 195 {
            return "\(hz) Hz • 표준 중음"
        } else {
            return "\(hz) Hz • 밝은 고음"
        }
    }
}

public enum SupportedLocale: String, CaseIterable, Identifiable {
    case korean = "ko-KR"
    case english = "en-US"
    case japanese = "ja-JP"
    case chinese = "zh-CN"
    case spanish = "es-ES"
    case french = "fr-FR"
    case german = "de-DE"
    case auto = "auto"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .korean: return "🇰🇷 한국어 (Korean)"
        case .english: return "🇺🇸 English (US)"
        case .japanese: return "🇯🇵 日本語 (Japanese)"
        case .chinese: return "🇨🇳 中文 (Chinese)"
        case .spanish: return "🇪🇸 Español (Spanish)"
        case .french: return "🇫🇷 Français (French)"
        case .german: return "🇩🇪 Deutsch (German)"
        case .auto: return "🌐 다국어 스마트 자동 감지"
        }
    }

    public var locale: Locale {
        if self == .auto {
            return Locale(identifier: "ko-KR")
        }
        return Locale(identifier: rawValue)
    }
}

@MainActor
public final class SpeechTranscriptionService: ObservableObject {
    public static let shared = SpeechTranscriptionService()

    // MARK: - Published State
    @Published public private(set) var isTranscribing: Bool = false
    @Published public private(set) var currentLiveText: String = ""
    @Published public private(set) var committedText: String = ""
    @Published public private(set) var segments: [TranscriptionSegment] = []
    @Published public private(set) var detectedLanguageCode: String? = "ko-KR"
    @Published public private(set) var detectedLanguageDisplayName: String = "🇰🇷 한국어 (고정)"
    @Published public private(set) var detectedLanguageConfidence: Double = 1.0
    @Published public var selectedLocale: SupportedLocale = .korean {
        didSet {
            updateLanguageDisplay()
        }
    }
    @Published public var errorMessage: String? = nil
    @Published public private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    // MARK: - Voice Biometrics & Smart Diarization
    @Published public var currentSpeakerId: Int = 1
    @Published public var speakerNames: [Int: String] = [
        1: "화자 1",
        2: "화자 2",
        3: "화자 3"
    ]
    @Published public var biometricProfiles: [Int: VoiceBiometricProfile] = [
        1: VoiceBiometricProfile(id: 1, name: "화자 1", averagePitchHz: 125, sampleCount: 0),
        2: VoiceBiometricProfile(id: 2, name: "화자 2", averagePitchHz: 215, sampleCount: 0),
        3: VoiceBiometricProfile(id: 3, name: "화자 3", averagePitchHz: 170, sampleCount: 0)
    ]
    @Published public var currentLivePitchHz: Float = 0.0
    @Published public var smartAcousticDiarization: Bool = true
    @Published public var autoSpeakerSwitchOnPause: Bool = true

    // MARK: - Private Speech Objects
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let languageRecognizer = NLLanguageRecognizer()
    private var languageHistory: [String] = []
    private var lastSpeechTime: Date = Date()
    private var silenceCheckTimer: Timer?

    public var fullTranscript: String {
        if segments.isEmpty {
            return currentLiveText
        }
        let formattedSegments = segments.map { seg in
            let pitchTag = seg.speakerPitchHz != nil ? " [\(Int(seg.speakerPitchHz!))Hz]" : ""
            return "[\(seg.speakerName)\(pitchTag) • \(seg.detectedLanguage)] \(formatTimestamp(seg.timestamp)):\n\(seg.text)"
        }.joined(separator: "\n\n")

        if !currentLiveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let activeSpeaker = speakerNames[currentSpeakerId] ?? "화자 \(currentSpeakerId)"
            return "\(formattedSegments)\n\n[\(activeSpeaker)] (말하는 중...): \(currentLiveText)"
        }
        return formattedSegments
    }

    public init() {
        self.authorizationStatus = SFSpeechRecognizer.authorizationStatus()
        self.updateLanguageDisplay()
    }

    public func updateLanguageDisplay() {
        if selectedLocale == .auto {
            if detectedLanguageCode == nil || detectedLanguageCode == "auto" {
                detectedLanguageDisplayName = "🌐 다국어 스마트 감지 활성"
                detectedLanguageConfidence = 0.0
            }
        } else {
            detectedLanguageCode = selectedLocale.rawValue
            detectedLanguageDisplayName = "\(selectedLocale.displayName) (고정)"
            detectedLanguageConfidence = 1.0
        }
    }

    public func setLocale(_ newLocale: SupportedLocale, audioEngine: AudioWaveformEngine? = nil) {
        guard selectedLocale != newLocale else { return }
        selectedLocale = newLocale
        languageHistory.removeAll()

        if isTranscribing, let engine = audioEngine {
            commitCurrentLiveText()
            restartRecognition(audioEngine: engine)
        }
    }

    // MARK: - Permissions
    public func requestPermissions() async -> Bool {
        let currentSpeechStatus = SFSpeechRecognizer.authorizationStatus()
        let speechGranted: Bool
        if currentSpeechStatus == .authorized {
            self.authorizationStatus = .authorized
            speechGranted = true
        } else {
            speechGranted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    Task { @MainActor in
                        self.authorizationStatus = status
                        continuation.resume(returning: status == .authorized)
                    }
                }
            }
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let micGranted: Bool
        if micStatus == .authorized {
            micGranted = true
        } else if #available(macOS 14.0, *) {
            micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            micGranted = true
        }

        return speechGranted && micGranted
    }

    // MARK: - Start Transcription
    public func startTranscription(audioEngine: AudioWaveformEngine) async throws {
        guard !isTranscribing else { return }

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        let permitted = await requestPermissions()
        guard permitted else {
            errorMessage = "마이크 또는 음성 인식 권한이 필요합니다. 시스템 설정에서 권한을 확인해주세요."
            return
        }

        updateLanguageDisplay()
        try startRecognitionTask(audioEngine: audioEngine)
        try audioEngine.start()
        self.isTranscribing = true
        self.errorMessage = nil
        self.lastSpeechTime = Date()

        // Silence check timer for speaker diarization
        silenceCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isTranscribing && !self.currentLiveText.isEmpty {
                    let elapsed = Date().timeIntervalSince(self.lastSpeechTime)
                    // If speaker paused for > 1.2 seconds, commit segment and allow next speaker turn
                    if elapsed > 1.2 {
                        self.commitCurrentLiveText()
                    }
                }
            }
        }
    }

    private func startRecognitionTask(audioEngine: AudioWaveformEngine) throws {
        let targetLocale = selectedLocale.locale
        guard let recognizer = SFSpeechRecognizer(locale: targetLocale), recognizer.isAvailable else {
            throw NSError(
                domain: "SpeechTranscriptionService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "'\(selectedLocale.displayName)' 언어 음성 인식기를 초기화할 수 없습니다."]
            )
        }
        self.speechRecognizer = recognizer

        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let result = result {
                    let transcribedString = result.bestTranscription.formattedString
                    self.currentLiveText = transcribedString
                    self.lastSpeechTime = Date()

                    // Real-time language classification for live feedback
                    let (langBadge, conf) = self.classifySegmentLanguage(text: transcribedString)
                    if self.selectedLocale == .auto {
                        self.detectedLanguageDisplayName = langBadge
                        self.detectedLanguageConfidence = conf
                    }

                    if result.isFinal {
                        self.commitCurrentLiveText()
                    }
                }

                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                        // ignore normal resets
                    }
                }
            }
        }

        // Acoustic Voice Feature Analysis (Pitch + Voice Activity + Diarization)
        audioEngine.onAcousticFeatures = { [weak self] features in
            Task { @MainActor [weak self] in
                self?.processAcousticFeatures(features)
            }
        }

        // Hook audio engine buffer tap with direct feed to Speech Recognizer (thread-safe, zero buffer delay)
        audioEngine.onBufferReceived = { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
    }

    private func processAcousticFeatures(_ features: AcousticVoiceFeatures) {
        guard isTranscribing else { return }

        if features.pitchHz > 60.0 {
            self.currentLivePitchHz = features.pitchHz

            // Update current speaker's biometric pitch profile with running average
            if var profile = biometricProfiles[currentSpeakerId] {
                profile.averagePitchHz = (profile.averagePitchHz * 0.94) + (features.pitchHz * 0.06)
                profile.sampleCount += 1
                biometricProfiles[currentSpeakerId] = profile
            }

            // Biometric Acoustic Speaker Diarization:
            // If speaker paused (> 0.75s) and new voice has distinct pitch, switch speaker turn automatically
            let pauseDuration = Date().timeIntervalSince(lastSpeechTime)
            if smartAcousticDiarization && pauseDuration > 0.75 && features.isVoiceActive {
                var bestCandidate = currentSpeakerId
                var closestDistance: Float = Float.infinity

                for (spkId, profile) in biometricProfiles {
                    let distance = abs(profile.averagePitchHz - features.pitchHz)
                    if distance < closestDistance {
                        closestDistance = distance
                        bestCandidate = spkId
                    }
                }

                // If closest candidate is different and has a confident pitch separation (> 28 Hz)
                let currentSpeakerDistance = abs((biometricProfiles[currentSpeakerId]?.averagePitchHz ?? 0) - features.pitchHz)
                if bestCandidate != currentSpeakerId && currentSpeakerDistance > 28.0 && closestDistance < 22.0 {
                    commitCurrentLiveText()
                    currentSpeakerId = bestCandidate
                }
            }
        }
    }

    private func restartRecognition(audioEngine: AudioWaveformEngine) {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        do {
            try startRecognitionTask(audioEngine: audioEngine)
        } catch {
            self.errorMessage = "언어 전환 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Stop Transcription
    public func stopTranscription(audioEngine: AudioWaveformEngine) {
        guard isTranscribing else { return }

        silenceCheckTimer?.invalidate()
        silenceCheckTimer = nil

        audioEngine.stop()
        audioEngine.onBufferReceived = nil
        audioEngine.onAcousticFeatures = nil

        recognitionRequest?.endAudio()
        recognitionTask?.finish()

        recognitionRequest = nil
        recognitionTask = nil
        isTranscribing = false
        currentLivePitchHz = 0.0

        commitCurrentLiveText()
    }

    public func clearTranscript() {
        currentLiveText = ""
        committedText = ""
        segments.removeAll()
        languageHistory.removeAll()
        errorMessage = nil
        currentLivePitchHz = 0.0
        updateLanguageDisplay()
    }

    public func selectSpeaker(id: Int) {
        if !currentLiveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commitCurrentLiveText()
        }
        currentSpeakerId = id
    }

    public func renameSpeaker(id: Int, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            speakerNames[id] = trimmed
            if var profile = biometricProfiles[id] {
                profile.name = trimmed
                biometricProfiles[id] = profile
            }
        }
    }

    private func commitCurrentLiveText() {
        let trimmed = currentLiveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let speakerName = speakerNames[currentSpeakerId] ?? "화자 \(currentSpeakerId)"
        let (langBadge, _) = classifySegmentLanguage(text: trimmed)
        let pitch = currentLivePitchHz > 60 ? currentLivePitchHz : biometricProfiles[currentSpeakerId]?.averagePitchHz

        let segment = TranscriptionSegment(
            timestamp: Date(),
            text: trimmed,
            speakerId: currentSpeakerId,
            speakerName: speakerName,
            detectedLanguage: langBadge,
            speakerPitchHz: pitch,
            acousticLabel: biometricProfiles[currentSpeakerId]?.pitchDescription
        )
        segments.append(segment)
        currentLiveText = ""
    }

    // MARK: - State-of-the-Art Language Input Distinction
    public func classifySegmentLanguage(text: String) -> (displayName: String, confidence: Double) {
        var hangulCount = 0
        var latinCount = 0
        var kanaCount = 0
        var cjkCount = 0

        for scalar in text.unicodeScalars {
            let val = scalar.value
            if (val >= 0xAC00 && val <= 0xD7AF) || (val >= 0x1100 && val <= 0x11FF) || (val >= 0x3130 && val <= 0x318F) {
                hangulCount += 1
            } else if (val >= 0x3040 && val <= 0x309F) || (val >= 0x30A0 && val <= 0x30FF) {
                kanaCount += 1
            } else if (val >= 0x4E00 && val <= 0x9FFF) {
                cjkCount += 1
            } else if (val >= 0x0041 && val <= 0x005A) || (val >= 0x0061 && val <= 0x007A) {
                latinCount += 1
            }
        }

        let total = hangulCount + latinCount + kanaCount + cjkCount
        guard total > 0 else { return ("🇰🇷 한국어", 1.0) }

        if kanaCount > 0 {
            return ("🇯🇵 日本語", 0.95)
        }
        if cjkCount >= 2 && hangulCount == 0 && latinCount == 0 {
            return ("🇨🇳 中文", 0.90)
        }

        // Bilingual / Code-switching check (Korean + English technical terms mixed)
        if hangulCount >= 2 && latinCount >= 2 {
            return ("🇰🇷 한/영 혼용 (Bilingual)", 0.99)
        }

        if hangulCount >= 1 {
            return ("🇰🇷 한국어", 0.98)
        }

        if latinCount >= 3 {
            languageRecognizer.reset()
            languageRecognizer.processString(text)
            if let dominant = languageRecognizer.dominantLanguage {
                let code = dominant.rawValue
                return (localizedLanguageName(for: code), 0.90)
            }
            return ("🇺🇸 English", 0.90)
        }

        return ("🇰🇷 한국어", 0.90)
    }

    private func localizedLanguageName(for code: String) -> String {
        switch code {
        case "ko": return "🇰🇷 한국어"
        case "en": return "🇺🇸 English"
        case "ja": return "🇯🇵 日本語"
        case "zh", "zh-Hans", "zh-Hant": return "🇨🇳 中文"
        case "es": return "🇪🇸 Español"
        case "fr": return "🇫🇷 Français"
        case "de": return "🇩🇪 Deutsch"
        case "it": return "🇮🇹 Italiano"
        case "ru": return "🇷🇺 Русский"
        default:
            let locale = Locale(identifier: code)
            let name = locale.localizedString(forIdentifier: code) ?? code
            return "🌐 \(name)"
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "mm:ss"
        return formatter.string(from: date)
    }
}
