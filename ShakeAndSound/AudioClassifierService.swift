import Foundation
import SoundAnalysis
@preconcurrency import AVFoundation
import Combine

public struct SoundEvent: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp = Date()
    public let label: String
    public let confidence: Double
    public let isFiltered: Bool
}

/// Helper class conforming to SNResultsObserving on background queues
private final class SoundAnalysisObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    private let onClassification: @Sendable (String, Double) -> Void

    init(onClassification: @escaping @Sendable (String, Double) -> Void) {
        self.onClassification = onClassification
        super.init()
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult,
              let topClassification = classificationResult.classifications.first else { return }
        onClassification(topClassification.identifier.lowercased(), Double(topClassification.confidence))
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}
    func requestDidComplete(_ request: SNRequest) {}
}

@MainActor
public final class AudioClassifierService: ObservableObject {
    public static let shared = AudioClassifierService()

    @Published public private(set) var currentSoundLabel: String = "정상 음성 대기"
    @Published public private(set) var isNoiseOrCoughDetected: Bool = false
    @Published public private(set) var filteredEvents: [SoundEvent] = []
    @Published public var enableNoiseAndCoughSuppression: Bool = true
    @Published public var suppressionSensitivity: Double = 0.50

    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private var currentFramePosition: AVAudioFramePosition = 0
    private var observer: SoundAnalysisObserver?

    private static let filteredSoundLabels: Set<String> = [
        "cough", "throat_clearing", "sneeze", "snort", "gasp",
        "applause", "laughter", "cheering",
        "typing", "computer_keyboard", "mouse_click",
        "pant", "snore", "groan", "sigh"
    ]

    public init() {}

    public func prepareAnalyzer(format: AVAudioFormat) {
        currentFramePosition = 0
        let analyzer = SNAudioStreamAnalyzer(format: format)

        let obs = SoundAnalysisObserver { [weak self] label, confidence in
            Task { @MainActor [weak self] in
                self?.handleDetectedSound(label: label, confidence: confidence)
            }
        }
        self.observer = obs

        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try analyzer.add(request, withObserver: obs)
            self.streamAnalyzer = analyzer
        } catch {
            print("Failed to initialize sound classifier: \(error)")
        }
    }

    public func analyzeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard enableNoiseAndCoughSuppression, let analyzer = streamAnalyzer else { return }
        let pos = currentFramePosition
        currentFramePosition += AVAudioFramePosition(buffer.frameLength)
        analyzer.analyze(buffer, atAudioFramePosition: pos)
    }

    public func reset() {
        currentFramePosition = 0
        currentSoundLabel = "대기"
        isNoiseOrCoughDetected = false
        streamAnalyzer = nil
        observer = nil
    }

    public func shouldSuppressAudio() -> Bool {
        return enableNoiseAndCoughSuppression && isNoiseOrCoughDetected
    }

    private func handleDetectedSound(label: String, confidence: Double) {
        let isUnwantedNoise = Self.filteredSoundLabels.contains(where: { label.contains($0) })
        let isSignificant = confidence >= suppressionSensitivity

        if isUnwantedNoise && isSignificant {
            self.isNoiseOrCoughDetected = true
            let localizedName = self.localizeSoundLabel(label)
            self.currentSoundLabel = "\(localizedName) (차단됨 🔇)"

            let event = SoundEvent(
                label: localizedName,
                confidence: confidence,
                isFiltered: true
            )
            self.filteredEvents.insert(event, at: 0)
            if self.filteredEvents.count > 20 {
                self.filteredEvents.removeLast()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.isNoiseOrCoughDetected = false
                self?.currentSoundLabel = "음성 입력 감지 중"
            }
        } else if !self.isNoiseOrCoughDetected {
            self.currentSoundLabel = "선명한 음성 (Speech)"
        }
    }

    private func localizeSoundLabel(_ identifier: String) -> String {
        switch identifier {
        case let s where s.contains("cough"): return "기침 소리"
        case let s where s.contains("throat_clearing"): return "목 가다듬는 소리"
        case let s where s.contains("sneeze"): return "재채기 소리"
        case let s where s.contains("laughter"): return "웃음소리"
        case let s where s.contains("applause"): return "박수 소리"
        case let s where s.contains("typing") || s.contains("keyboard"): return "키보드 소음"
        case let s where s.contains("mouse_click"): return "마우스 클릭음"
        case let s where s.contains("snore"): return "코골이 소리"
        default: return "배경 소음 (\(identifier))"
        }
    }
}
