import Foundation
import NaturalLanguage
import Combine

public enum SummarizerEngine: String, CaseIterable, Identifiable, Sendable {
    case geminiFlashLite = "Gemini 2.0 Flash-Lite (Cheapest ⚡)"
    case geminiFlash8B = "Gemini 1.5 Flash-8B (Ultra Low Cost)"
    case smartLocal = "Smart On-Device (Apple Intelligence / NL)"

    public var id: String { rawValue }

    public var requiresApiKey: Bool {
        switch self {
        case .smartLocal: return false
        case .geminiFlashLite, .geminiFlash8B: return true
        }
    }

    public var modelName: String {
        switch self {
        case .geminiFlashLite: return "gemini-2.0-flash-lite"
        case .geminiFlash8B: return "gemini-1.5-flash-8b"
        case .smartLocal: return "on-device-nl"
        }
    }
}

public struct TokenUsageInfo: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp = Date()
    public let promptTokens: Int
    public let candidatesTokens: Int
    public let totalTokens: Int
    public let maxContextTokens: Int = 1_048_576 // 1M tokens limit for Gemini Flash Lite

    public var usedPercentage: Double {
        return (Double(totalTokens) / Double(maxContextTokens)) * 100.0
    }

    public var remainingPercentage: Double {
        return max(0.0, 100.0 - usedPercentage)
    }

    public var remainingTokens: Int {
        return max(0, maxContextTokens - totalTokens)
    }
}

public struct AudioSummaryResult: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp = Date()
    public let engine: SummarizerEngine
    public let originalWordCount: Int
    public let formattedMarkdown: String
    public let detectedTopics: [String]
    public let sentiment: String
    public let tokenUsage: TokenUsageInfo?

    public nonisolated init(
        engine: SummarizerEngine,
        originalWordCount: Int,
        formattedMarkdown: String,
        detectedTopics: [String],
        sentiment: String,
        tokenUsage: TokenUsageInfo? = nil
    ) {
        self.engine = engine
        self.originalWordCount = originalWordCount
        self.formattedMarkdown = formattedMarkdown
        self.detectedTopics = detectedTopics
        self.sentiment = sentiment
        self.tokenUsage = tokenUsage
    }
}

@MainActor
public final class SummarizationService: ObservableObject {
    public static let shared = SummarizationService()

    @Published public var selectedEngine: SummarizerEngine = .geminiFlashLite
    @Published public var geminiApiKey: String = "" {
        didSet {
            UserDefaults.standard.set(geminiApiKey, forKey: "gemini_api_key")
        }
    }
    @Published public private(set) var isKeyFromEnv: Bool = false
    @Published public private(set) var isSummarizing: Bool = false
    @Published public private(set) var currentSummary: AudioSummaryResult? = nil
    @Published public private(set) var lastTokenUsage: TokenUsageInfo? = nil
    @Published public private(set) var sessionTotalTokens: Int = 0
    @Published public var errorMessage: String? = nil

    public init() {
        // 1. Try loading from .env file first
        if let envKey = Self.loadGeminiKeyFromEnv(), !envKey.isEmpty {
            self.geminiApiKey = envKey
            self.isKeyFromEnv = true
        } else if let envVar = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envVar.isEmpty {
            self.geminiApiKey = envVar
            self.isKeyFromEnv = true
        } else {
            self.geminiApiKey = UserDefaults.standard.string(forKey: "gemini_api_key") ?? ""
            self.isKeyFromEnv = false
        }
    }

    // MARK: - .env Loader
    public static func loadGeminiKeyFromEnv() -> String? {
        let possiblePaths = [
            "/Users/sushikim/Documents/ShakeAndSound/.env",
            FileManager.default.currentDirectoryPath + "/.env",
            Bundle.main.bundlePath + "/.env",
            Bundle.main.bundlePath + "/Contents/Resources/.env"
        ]

        for path in possiblePaths {
            guard FileManager.default.fileExists(atPath: path),
                  let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
                continue
            }

            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == "GEMINI_API_KEY" {
                    let key = parts[1].trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"\'"))
                    if !key.isEmpty {
                        return key
                    }
                }
            }
        }
        return nil
    }

    public func summarize(transcript: String, languageHint: String? = nil) async {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "요약할 텍스트가 비어 있습니다. 먼저 음성을 녹음하거나 텍스트를 입력해주세요."
            return
        }

        isSummarizing = true
        errorMessage = nil

        do {
            switch selectedEngine {
            case .smartLocal:
                let result = await generateSmartLocalSummary(text: trimmed, languageHint: languageHint)
                self.currentSummary = result
            case .geminiFlashLite:
                let result = try await generateGeminiSummary(text: trimmed, modelName: "gemini-2.0-flash-lite", languageHint: languageHint)
                self.currentSummary = result
            case .geminiFlash8B:
                let result = try await generateGeminiSummary(text: trimmed, modelName: "gemini-1.5-flash-8b", languageHint: languageHint)
                self.currentSummary = result
            }
        } catch {
            self.errorMessage = "요약 중 오류가 발생했습니다: \(error.localizedDescription)"
        }

        isSummarizing = false
    }

    // MARK: - Smart On-Device Summarization (NaturalLanguage Framework)
    private func generateSmartLocalSummary(text: String, languageHint: String?) async -> AudioSummaryResult {
        return await Task.detached(priority: .userInitiated) {
            let tagger = NLTagger(tagSchemes: [.tokenType, .lexicalClass, .nameType, .sentimentScore])
            tagger.string = text

            // 1. Sentence splitting & word counting
            var sentences: [String] = []
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .localized]) { substring, _, _, _ in
                if let s = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                    sentences.append(s)
                }
            }
            if sentences.isEmpty {
                sentences = [text]
            }

            var words: [String] = []
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .localized]) { substring, _, _, _ in
                if let w = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !w.isEmpty {
                    words.append(w.lowercased())
                }
            }

            let wordCount = words.count

            // 2. Keyword & Entity extraction
            var wordFrequencies: [String: Int] = [:]
            let stopWords: Set<String> = [
                "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "is", "was", "are", "were", "it", "this", "that",
                "이", "그", "저", "것", "수", "등", "및", "를", "을", "에", "의", "로", "으로", "에서", "하고", "하다", "있다", "되다", "하는", "있는", "화자"
            ]

            for word in words where word.count >= 2 && !stopWords.contains(word) {
                wordFrequencies[word, default: 0] += 1
            }

            let sortedKeywords = wordFrequencies.sorted { $0.value > $1.value }.prefix(6).map { $0.key }

            // 3. Sentiment Analysis
            let (sentimentScore, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
            let scoreValue = Double(sentimentScore?.rawValue ?? "0") ?? 0.0
            let sentimentDescription: String
            if scoreValue > 0.2 {
                sentimentDescription = "긍정적 (Positive ✨ \(String(format: "%.1f", scoreValue * 100))%)"
            } else if scoreValue < -0.2 {
                sentimentDescription = "진지 / 부정적 (Serious/Negative ⚠️ \(String(format: "%.1f", scoreValue * 100))%)"
            } else {
                sentimentDescription = "중립적 / 객관적 (Neutral ⚖️)"
            }

            // 4. Extractive Key Sentences
            let topSentences: [String]
            if sentences.count <= 2 {
                topSentences = sentences
            } else {
                let scored = sentences.map { sentence -> (sentence: String, score: Int) in
                    let lower = sentence.lowercased()
                    let score = sortedKeywords.reduce(0) { acc, kw in
                        acc + (lower.contains(kw) ? (wordFrequencies[kw] ?? 1) : 0)
                    }
                    return (sentence, score)
                }
                let ranked = scored.sorted { $0.score > $1.score }.prefix(3).map { $0.sentence }
                topSentences = ranked
            }

            // 5. Speaker Breakdown if speaker tags exist
            var speakerLines: [String: [String]] = [:]
            let lines = text.components(separatedBy: .newlines)
            for line in lines {
                if let match = line.range(of: "^\\[(화자 [0-9]+|[^\\]]+)\\]", options: .regularExpression) {
                    let speakerTag = String(line[match])
                    let content = line[match.upperBound...].trimmingCharacters(in: .whitespaces)
                    if !content.isEmpty {
                        speakerLines[speakerTag, default: []].append(content)
                    }
                }
            }

            // 6. Build Markdown
            var md = "### 📌 핵심 요약 (Executive Summary)\n"
            for sentence in topSentences {
                md += "- \(sentence)\n"
            }

            if !speakerLines.isEmpty {
                md += "\n### 👥 화자별 발언 분석 (Speaker Breakdown)\n"
                for (speaker, utterances) in speakerLines.sorted(by: { $0.key < $1.key }) {
                    let sample = utterances.prefix(2).joined(separator: " / ")
                    md += "- **\(speaker)**: \(sample)\n"
                }
            }

            md += "\n### 💡 주요 키워드 및 토픽\n"
            if sortedKeywords.isEmpty {
                md += "_감지된 주요 키워드가 없습니다._\n"
            } else {
                let tags = sortedKeywords.map { "`#\($0)`" }.joined(separator: " ")
                md += "\(tags)\n"
            }

            md += "\n### 📊 음성 텍스트 분석\n"
            md += "- **총 단어 수**: 약 \(wordCount)개 (\(sentences.count)개 문장)\n"
            let estimatedSeconds = max(1, Int(Double(wordCount) / 2.5))
            md += "- **예상 발화 시간**: 약 \(estimatedSeconds)초\n"
            md += "- **어조 및 감정**: \(sentimentDescription)\n"
            if let lang = languageHint {
                md += "- **언어**: \(lang)\n"
            }

            md += "\n> _💡 로컬 Apple NaturalLanguage 엔진으로 즉시 생성된 요약입니다. (토큰 소모 없음)_"

            return AudioSummaryResult(
                engine: .smartLocal,
                originalWordCount: wordCount,
                formattedMarkdown: md,
                detectedTopics: Array(sortedKeywords),
                sentiment: sentimentDescription,
                tokenUsage: nil
            )
        }.value
    }

    // MARK: - Gemini API Summarization (Flash-Lite / Flash-8B)
    private func generateGeminiSummary(text: String, modelName: String, languageHint: String?) async throws -> AudioSummaryResult {
        guard !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "SummarizationService", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Gemini API 키가 설정되지 않았습니다. .env 파일 또는 설정 탭에서 API 키를 입력해주세요."
            ])
        }

        let endpointString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines))"
        guard let url = URL(string: endpointString) else {
            throw NSError(domain: "SummarizationService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Gemini API endpoint URL"])
        }

        let prompt = """
        당신은 음성 회의 및 오디오 전사 내용을 정리하고 요약하는 최고의 AI 비서입니다.
        아래 음성 전사 텍스트를 분석하여 사용자가 한눈에 이해할 수 있도록 구조화된 한국어 마크다운으로 작성해주세요.
        텍스트에 [화자 1], [화자 2] 등 여러 발언자가 표시되어 있다면 각 화자별 입장과 논점을 명확히 분리하여 요약해주세요.

        [전사 내용]:
        \(text)

        [작성 형식 가이드]:
        ### 📌 3줄 핵심 요약
        - 핵심 요약 1
        - 핵심 요약 2
        - 핵심 요약 3

        ### 👥 화자별 발언 및 의견 요약 (화자 분리)
        - **화자 1**: 발언 내용 및 주요 관점
        - **화자 2**: 발언 내용 및 피드백

        ### 📋 주요 논의 사항 및 세부 결정
        - 세부 포인트 정리

        ### 🎯 액션 아이템 / 다음 할 일 (Action Items)
        - [ ] 할 일 1
        - [ ] 할 일 2

        ### 🏷️ 핵심 키워드
        `#키워드1` `#키워드2` `#키워드3`

        언어 힌트: \(languageHint ?? "한국어")
        친절하고 명확하며 세련된 톤으로 정리해주세요.
        """

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.4,
                "topP": 0.9,
                "maxOutputTokens": 2048
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "SummarizationService", code: 500, userInfo: [NSLocalizedDescriptionKey: "응답을 받지 못했습니다."])
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "SummarizationService", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Gemini API 오류 (\(httpResponse.statusCode)): \(errorMsg)"
            ])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let summaryText = firstPart["text"] as? String else {
            throw NSError(domain: "SummarizationService", code: 502, userInfo: [NSLocalizedDescriptionKey: "Gemini 응답 형식이 올바르지 않습니다."])
        }

        // Parse token usage metadata
        var usageInfo: TokenUsageInfo? = nil
        if let usageDict = json?["usageMetadata"] as? [String: Any] {
            let promptTokens = usageDict["promptTokenCount"] as? Int ?? 0
            let candidatesTokens = usageDict["candidatesTokenCount"] as? Int ?? 0
            let totalTokens = usageDict["totalTokenCount"] as? Int ?? (promptTokens + candidatesTokens)

            let info = TokenUsageInfo(
                promptTokens: promptTokens,
                candidatesTokens: candidatesTokens,
                totalTokens: totalTokens
            )
            usageInfo = info
            self.lastTokenUsage = info
            self.sessionTotalTokens += totalTokens
        }

        let words = text.split(separator: " ").count
        let engine = modelName.contains("8b") ? SummarizerEngine.geminiFlash8B : SummarizerEngine.geminiFlashLite

        return AudioSummaryResult(
            engine: engine,
            originalWordCount: words,
            formattedMarkdown: summaryText,
            detectedTopics: [],
            sentiment: "AI 분석 완료",
            tokenUsage: usageInfo
        )
    }
}
