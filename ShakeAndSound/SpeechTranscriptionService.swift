import Foundation
import Speech
import NaturalLanguage
import AVFoundation
import Combine

public struct TranscriptionSegment: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: Date
    public let text: String
    public let speakerId: Int
    public let speakerName: String
    public let detectedLanguage: String?

    public init(timestamp: Date = Date(), text: String, speakerId: Int = 1, speakerName: String = "화자 1", detectedLanguage: String? = nil) {
        self.timestamp = timestamp
        self.text = text
        self.speakerId = speakerId
        self.speakerName = speakerName
        self.detectedLanguage = detectedLanguage
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
        case .auto: return "🌐 자동 감지 (Auto Detect)"
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

    // MARK: - Speaker Diarization State
    @Published public var currentSpeakerId: Int = 1
    @Published public var speakerNames: [Int: String] = [
        1: "화자 1",
        2: "화자 2",
        3: "화자 3"
    ]
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
            "[\(seg.speakerName)] \(formatTimestamp(seg.timestamp)): \(seg.text)"
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
                detectedLanguageDisplayName = "🌐 자동 감지 대기..."
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
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.authorizationStatus = status
                    continuation.resume(returning: status == .authorized)
                }
            }
        }

        let micGranted: Bool
        if #available(macOS 14.0, *) {
            micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            micGranted = true
        }

        return speechGranted && micGranted
    }

    // MARK: - Start Transcription
    public func startTranscription(audioEngine: AudioWaveformEngine) async throws {
        guard !isTranscribing else { return }

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
        silenceCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isTranscribing && !self.currentLiveText.isEmpty {
                    let elapsed = Date().timeIntervalSince(self.lastSpeechTime)
                    // If speaker paused for > 1.6 seconds, commit segment and optionally switch speaker turn
                    if elapsed > 1.6 {
                        self.commitCurrentLiveText()
                        if self.autoSpeakerSwitchOnPause {
                            self.currentSpeakerId = (self.currentSpeakerId == 1) ? 2 : 1
                        }
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

                    // Only run auto-language detector if auto mode is enabled
                    if self.selectedLocale == .auto {
                        self.analyzeSpokenLanguage(text: transcribedString)
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

        // Hook audio engine buffer tap with cough & noise suppression filter
        audioEngine.onBufferReceived = { [weak self] buffer, _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if !AudioClassifierService.shared.shouldSuppressAudio() {
                    self.recognitionRequest?.append(buffer)
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

        recognitionRequest?.endAudio()
        recognitionTask?.finish()

        recognitionRequest = nil
        recognitionTask = nil
        isTranscribing = false

        commitCurrentLiveText()
    }

    public func clearTranscript() {
        currentLiveText = ""
        committedText = ""
        segments.removeAll()
        languageHistory.removeAll()
        errorMessage = nil
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
        }
    }

    private func commitCurrentLiveText() {
        let trimmed = currentLiveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let speakerName = speakerNames[currentSpeakerId] ?? "화자 \(currentSpeakerId)"
        let segment = TranscriptionSegment(
            timestamp: Date(),
            text: trimmed,
            speakerId: currentSpeakerId,
            speakerName: speakerName,
            detectedLanguage: detectedLanguageDisplayName
        )
        segments.append(segment)
        currentLiveText = ""
    }

    // MARK: - Robust Script-Aware Language Detection
    private func analyzeSpokenLanguage(text: String) {
        guard selectedLocale == .auto else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return }

        // 1. Deterministic Unicode Script Analysis
        var hangulCount = 0
        var kanaCount = 0
        var latinCount = 0
        var cjkCount = 0

        for scalar in trimmed.unicodeScalars {
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

        let totalMeaningful = hangulCount + kanaCount + latinCount + cjkCount
        guard totalMeaningful >= 3 else { return }

        let detectedCode: String
        let confidence: Double

        if Double(hangulCount) / Double(totalMeaningful) >= 0.30 {
            detectedCode = "ko"
            confidence = 0.98
        } else if kanaCount > 0 {
            detectedCode = "ja"
            confidence = 0.95
        } else if cjkCount >= 2 && latinCount == 0 {
            detectedCode = "zh"
            confidence = 0.90
        } else if Double(latinCount) / Double(totalMeaningful) >= 0.60 {
            languageRecognizer.reset()
            languageRecognizer.processString(trimmed)
            if let dominant = languageRecognizer.dominantLanguage {
                detectedCode = dominant.rawValue
                confidence = languageRecognizer.languageHypotheses(withMaximum: 1)[dominant] ?? 0.85
            } else {
                detectedCode = "en"
                confidence = 0.80
            }
        } else {
            return
        }

        // 2. Hysteresis (Voting filter to prevent jitter)
        languageHistory.append(detectedCode)
        if languageHistory.count > 5 {
            languageHistory.removeFirst()
        }

        let codeVotes = languageHistory.filter { $0 == detectedCode }.count
        if codeVotes >= 2 || confidence >= 0.95 {
            self.detectedLanguageCode = detectedCode
            self.detectedLanguageConfidence = confidence
            self.detectedLanguageDisplayName = localizedLanguageName(for: detectedCode)
        }
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
