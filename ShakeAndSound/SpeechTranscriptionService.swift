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
    case auto = "auto"
    case korean = "ko-KR"
    case english = "en-US"
    case japanese = "ja-JP"
    case chinese = "zh-CN"
    case spanish = "es-ES"
    case french = "fr-FR"
    case german = "de-DE"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "🌐 자동 감지 (Auto Detect)"
        case .korean: return "🇰🇷 한국어 (Korean)"
        case .english: return "🇺🇸 English (US)"
        case .japanese: return "🇯🇵 日本語 (Japanese)"
        case .chinese: return "🇨🇳 中文 (Chinese)"
        case .spanish: return "🇪🇸 Español (Spanish)"
        case .french: return "🇫🇷 Français (French)"
        case .german: return "🇩🇪 Deutsch (German)"
        }
    }

    public var locale: Locale {
        if self == .auto {
            return Locale.current
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
    @Published public private(set) var detectedLanguageCode: String? = nil
    @Published public private(set) var detectedLanguageDisplayName: String = "대기 중..."
    @Published public private(set) var detectedLanguageConfidence: Double = 0.0
    @Published public var selectedLocale: SupportedLocale = .auto
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

        let targetLocale = selectedLocale.locale
        speechRecognizer = SFSpeechRecognizer(locale: targetLocale) ?? SFSpeechRecognizer()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = "선택된 언어의 음성 인식 서비스를 현재 사용할 수 없습니다."
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let result = result {
                    let transcribedString = result.bestTranscription.formattedString
                    self.currentLiveText = transcribedString
                    self.lastSpeechTime = Date()
                    self.analyzeSpokenLanguage(text: transcribedString)

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

                // Suppress buffer if sound analysis detects cough or noise
                if !AudioClassifierService.shared.shouldSuppressAudio() {
                    self.recognitionRequest?.append(buffer)
                }
            }
        }

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
                            // Cycle between 화자 1 and 화자 2
                            self.currentSpeakerId = (self.currentSpeakerId == 1) ? 2 : 1
                        }
                    }
                }
            }
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
        detectedLanguageCode = nil
        detectedLanguageDisplayName = "대기 중..."
        detectedLanguageConfidence = 0.0
        errorMessage = nil
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

    // MARK: - Language Detection
    private func analyzeSpokenLanguage(text: String) {
        guard text.count >= 2 else { return }

        languageRecognizer.reset()
        languageRecognizer.processString(text)

        let hypotheses = languageRecognizer.languageHypotheses(withMaximum: 3)
        if let dominant = languageRecognizer.dominantLanguage {
            let code = dominant.rawValue
            let confidence = hypotheses[dominant] ?? 0.8
            self.detectedLanguageCode = code
            self.detectedLanguageConfidence = confidence
            self.detectedLanguageDisplayName = localizedLanguageName(for: code)
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
