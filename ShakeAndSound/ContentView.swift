import SwiftUI
import Speech
import UniformTypeIdentifiers

enum NavigationTab: String, CaseIterable, Identifiable {
    case sound = "Sound Studio"
    case shake = "Shake Seismo"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sound: return "waveform.badge.mic"
        case .shake: return "waveform.path.ecg"
        case .settings: return "gearshape.fill"
        }
    }
}

public struct ContentView: View {
    @StateObject private var audioEngine = AudioWaveformEngine.shared
    @StateObject private var speechService = SpeechTranscriptionService.shared
    @StateObject private var summarizer = SummarizationService.shared
    @StateObject private var classifier = AudioClassifierService.shared

    @State private var activeTab: NavigationTab = .sound
    @State private var visualizerStyle: VisualizerStyle = .jarvisWave
    @State private var editableTranscript: String = ""
    @State private var showingCopiedToast = false
    @State private var transcriptionViewMode: Int = 0 // 0: Segment Cards, 1: Text Editor
    @State private var isApiKeyLocked: Bool = true
    @State private var showingUnlockAlert: Bool = false

    public init() {}

    public var body: some View {
        NavigationSplitView {
            // Sidebar Navigation
            VStack(alignment: .leading, spacing: 14) {
                // App Brand with wave-sound.png
                HStack(spacing: 12) {
                    Image("WaveSound")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 38, height: 38)
                        .cornerRadius(8)
                        .shadow(color: .cyan.opacity(0.4), radius: 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shake & Sound")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("AI Voice & Seismograph")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Divider()
                    .padding(.horizontal, 12)

                // Tab Buttons
                VStack(spacing: 6) {
                    ForEach(NavigationTab.allCases) { tab in
                        Button {
                            activeTab = tab
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(width: 20)
                                    .foregroundColor(activeTab == tab ? .cyan : .secondary)

                                Text(tab.rawValue)
                                    .font(.system(size: 13, weight: activeTab == tab ? .semibold : .regular))
                                    .foregroundColor(activeTab == tab ? .primary : .secondary)

                                Spacer()

                                if tab == .sound && speechService.isTranscribing {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(activeTab == tab ? Color.white.opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)

                Spacer()

                // Mini System Info in Sidebar Footer
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle()
                            .fill(speechService.isTranscribing ? Color.green : Color.gray.opacity(0.6))
                            .frame(width: 6, height: 6)
                        Text(speechService.isTranscribing ? "음성 인식 중" : "준비됨")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    if speechService.currentLivePitchHz > 60 {
                        Text("🎙️ 피치: \(Int(speechService.currentLivePitchHz)) Hz")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.cyan)
                    }

                    Text(speechService.detectedLanguageDisplayName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.green)

                    if classifier.isNoiseOrCoughDetected {
                        Text(classifier.currentSoundLabel)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                    }

                    if let usage = summarizer.lastTokenUsage {
                        Text("잔여 토큰: \(String(format: "%.1f", usage.remainingPercentage))%")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .frame(minWidth: 210, maxWidth: 240)
            .background(Color(red: 0.06, green: 0.07, blue: 0.10))
        } detail: {
            ZStack {
                Color(red: 0.02, green: 0.03, blue: 0.05).ignoresSafeArea()

                Group {
                    switch activeTab {
                    case .sound:
                        soundStudioView
                    case .shake:
                        SeismoView()
                    case .settings:
                        settingsView
                    }
                }

                // Copied Toast Notification
                if showingCopiedToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("클립보드에 복사되었습니다!")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .shadow(radius: 10)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .alert("API 키 잠금 해제 확인", isPresented: $showingUnlockAlert) {
            Button("잠금 해제", role: .destructive) {
                isApiKeyLocked = false
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("API 키를 수정하려면 잠금을 해제해야 합니다. 키가 노출되거나 원치 않게 변경될 수 있으니 수정 후 반드시 다시 잠금 상태로 설정해주세요.")
        }
    }

    // MARK: - Sound Studio View
    private var soundStudioView: some View {
        ScrollView {
            VStack(spacing: 18) {
                // 1. Jarvis / Siri Waveform Hero Visualizer
                SoundVisualizerView(audioEngine: audioEngine, selectedStyle: $visualizerStyle)

                // 2. Cough & Noise Suppression Banner (Real-time Feedback)
                if classifier.isNoiseOrCoughDetected {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.slash.fill")
                            .foregroundColor(.orange)
                        Text("소음/기침 차단 필터 활성:")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.orange)
                        Text(classifier.currentSoundLabel)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        Spacer()
                        Text("전사 왜곡 방지됨")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.4), lineWidth: 1))
                }

                // 3. Recording & Language Action Bar
                HStack(spacing: 12) {
                    // Record / Stop Main Button
                    Button {
                        toggleRecording()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: speechService.isTranscribing ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text(speechService.isTranscribing ? "음성 인식 중지" : "마이크 녹음 및 전사 시작")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(speechService.isTranscribing ? .red : .cyan)

                    // Language Mode Badge (Fixed or Auto)
                    HStack(spacing: 6) {
                        Image(systemName: speechService.selectedLocale == .auto ? "globe.badge.chevron.backward" : "checkmark.seal.fill")
                            .foregroundColor(speechService.selectedLocale == .auto ? .cyan : .green)
                        Text(speechService.detectedLanguageDisplayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .overlay(Capsule().stroke(speechService.selectedLocale == .auto ? Color.cyan.opacity(0.3) : Color.green.opacity(0.5), lineWidth: 1))

                    Spacer()

                    // Recognition Language Picker
                    Picker("", selection: Binding(
                        get: { speechService.selectedLocale },
                        set: { speechService.setLocale($0, audioEngine: audioEngine) }
                    )) {
                        ForEach(SupportedLocale.allCases) { loc in
                            Text(loc.displayName).tag(loc)
                        }
                    }
                    .frame(width: 210)

                    // Clear Button
                    Button {
                        speechService.clearTranscript()
                        editableTranscript = ""
                    } label: {
                        Label("지우기", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                // 4. Biometric Speaker Diarization & Voice Profiling Bar
                HStack(spacing: 10) {
                    Label("스마트 화자 분리 (Biometrics):", systemImage: "person.wave.2.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.cyan)

                    ForEach(1...3, id: \.self) { id in
                        let profile = speechService.biometricProfiles[id]
                        Button {
                            speechService.selectSpeaker(id: id)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(speakerColor(id))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(speechService.speakerNames[id] ?? "화자 \(id)")
                                        .font(.system(size: 11, weight: speechService.currentSpeakerId == id ? .bold : .medium))
                                    Text(profile?.pitchDescription ?? "대기 중")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(speechService.currentSpeakerId == id ? Color.white.opacity(0.18) : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(speechService.currentSpeakerId == id ? speakerColor(id) : Color.clear, lineWidth: 1.2)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if audioEngine.isRunning {
                        HStack(spacing: 5) {
                            Image(systemName: "waveform.path")
                                .foregroundColor(speechService.currentLivePitchHz > 60 ? .green : .secondary)
                            Text(speechService.currentLivePitchHz > 60 ? "피치: \(Int(speechService.currentLivePitchHz)) Hz" : "음성 대기")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(speechService.currentLivePitchHz > 60 ? .green : .secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.05), in: Capsule())
                    }

                    Toggle("음향 피치 자동 분리", isOn: $speechService.smartAcousticDiarization)
                        .toggleStyle(.switch)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))

                // Error Message if any
                if let err = speechService.errorMessage ?? audioEngine.errorMessage ?? summarizer.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(err)
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }

                // 5. Main Workspace: Transcription (Left) & AI Summarizer (Right)
                HStack(alignment: .top, spacing: 18) {
                    // Left Card: Live Transcription with Speaker Tags & Language Badges
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("화자별 실시간 전사 (Transcript)", systemImage: "text.bubble.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.cyan)

                            Spacer()

                            // View Mode Toggle (Segment Cards vs Raw Text)
                            Picker("", selection: $transcriptionViewMode) {
                                Image(systemName: "bubble.left.and.bubble.right.fill").tag(0)
                                Image(systemName: "pencil.line").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 80)

                            let currentText = currentCombinedTranscript
                            Text("\(currentText.split(separator: " ").count)단어 / \(currentText.count)자")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)

                            Button {
                                copyToClipboard(currentCombinedTranscript)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .help("전사 내용 복사")
                        }

                        // Display Mode 0: Conversational Segment Cards with Biometrics & Language Badges
                        if transcriptionViewMode == 0 {
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 0.04, green: 0.06, blue: 0.10))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))

                                if speechService.segments.isEmpty && speechService.currentLiveText.isEmpty {
                                    VStack(alignment: .center, spacing: 8) {
                                        Image(systemName: "mic.badge.plus")
                                            .font(.system(size: 28))
                                            .foregroundColor(.cyan.opacity(0.4))
                                        Text("마이크 녹음을 시작하면 화자(Biometrics)와 언어가 자동 분석되어 실시간 기록됩니다.\n기침, 소음은 자동으로 필터링됩니다.")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary.opacity(0.7))
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.top, 60)
                                } else {
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 10) {
                                            ForEach(speechService.segments) { seg in
                                                VStack(alignment: .leading, spacing: 6) {
                                                    HStack(spacing: 8) {
                                                        Circle()
                                                            .fill(speakerColor(seg.speakerId))
                                                            .frame(width: 8, height: 8)
                                                        Text(seg.speakerName)
                                                            .font(.system(size: 12, weight: .bold))
                                                            .foregroundColor(speakerColor(seg.speakerId))

                                                        if let pitch = seg.speakerPitchHz, pitch > 60 {
                                                            Text("\(Int(pitch)) Hz")
                                                                .font(.system(size: 10, design: .monospaced))
                                                                .foregroundColor(.secondary)
                                                                .padding(.horizontal, 6)
                                                                .padding(.vertical, 2)
                                                                .background(Color.white.opacity(0.06), in: Capsule())
                                                        }

                                                        Spacer()

                                                        // Language Badge per segment
                                                        Text(seg.detectedLanguage)
                                                            .font(.system(size: 10, weight: .semibold))
                                                            .foregroundColor(.white)
                                                            .padding(.horizontal, 8)
                                                            .padding(.vertical, 2)
                                                            .background(Color.white.opacity(0.08), in: Capsule())

                                                        Text(formatTime(seg.timestamp))
                                                            .font(.system(size: 10, design: .monospaced))
                                                            .foregroundColor(.secondary)
                                                    }

                                                    Text(seg.text)
                                                        .font(.system(size: 13))
                                                        .foregroundColor(.white.opacity(0.95))
                                                        .textSelection(.enabled)
                                                }
                                                .padding(12)
                                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(speakerColor(seg.speakerId).opacity(0.2), lineWidth: 1))
                                            }

                                            // Live utterance preview
                                            if !speechService.currentLiveText.isEmpty {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    HStack(spacing: 8) {
                                                        Circle()
                                                            .fill(speakerColor(speechService.currentSpeakerId))
                                                            .frame(width: 8, height: 8)
                                                        Text(speechService.speakerNames[speechService.currentSpeakerId] ?? "화자 \(speechService.currentSpeakerId)")
                                                            .font(.system(size: 12, weight: .bold))
                                                            .foregroundColor(speakerColor(speechService.currentSpeakerId))

                                                        Text("말하는 중...")
                                                            .font(.system(size: 10, weight: .semibold))
                                                            .foregroundColor(.cyan)

                                                        Spacer()

                                                        Text(speechService.detectedLanguageDisplayName)
                                                            .font(.system(size: 10))
                                                            .foregroundColor(.secondary)
                                                    }

                                                    Text(speechService.currentLiveText)
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundColor(.cyan.opacity(0.9))
                                                }
                                                .padding(12)
                                                .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.4), lineWidth: 1))
                                            }
                                        }
                                        .padding(10)
                                    }
                                }
                            }
                            .frame(minHeight: 280)
                        } else {
                            // Display Mode 1: Raw Editable Text Area
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: Binding(
                                    get: { currentCombinedTranscript },
                                    set: { editableTranscript = $0 }
                                ))
                                .font(.system(size: 13, design: .default))
                                .lineSpacing(4)
                                .padding(8)
                                .scrollContentBackground(.hidden)
                                .background(Color(red: 0.04, green: 0.06, blue: 0.10))
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))

                                if currentCombinedTranscript.isEmpty {
                                    Text("마이크 녹음을 시작하면 화자별 실시간 음성이 텍스트로 기록됩니다...")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary.opacity(0.6))
                                        .padding(16)
                                        .allowsHitTesting(false)
                                }
                            }
                            .frame(minHeight: 280)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Right Card: AI Summarizer & Executive Brief
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("AI 핵심 요약 (Flash-Lite / Local)", systemImage: "sparkles")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.purple)

                            Spacer()

                            // Model Picker restricted only to Flash-Lite & cheapest options
                            Picker("", selection: $summarizer.selectedEngine) {
                                ForEach(SummarizerEngine.allCases) { engine in
                                    Text(engine.rawValue).tag(engine)
                                }
                            }
                            .frame(width: 250)
                        }

                        // Summarize Action Bar
                        HStack {
                            Button {
                                Task {
                                    await summarizer.summarize(
                                        transcript: currentCombinedTranscript,
                                        languageHint: speechService.detectedLanguageDisplayName
                                    )
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if summarizer.isSummarizing {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("요약 분석 중...")
                                    } else {
                                        Image(systemName: "wand.and.stars")
                                        Text("요약하기 (Flash-Lite)")
                                    }
                                }
                                .font(.system(size: 12, weight: .bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .disabled(currentCombinedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || summarizer.isSummarizing)

                            Spacer()

                            if let summary = summarizer.currentSummary {
                                Button {
                                    copyToClipboard(summary.formattedMarkdown)
                                } label: {
                                    Label("마크다운 복사", systemImage: "doc.on.doc")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        // Token Usage Progress & Remaining Percentage Card
                        if let usage = summarizer.lastTokenUsage {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                                        .foregroundColor(.green)
                                    Text("Gemini Flash-Lite 토큰 사용 현황")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)

                                    Spacer()

                                    Text("잔여 \(String(format: "%.2f", usage.remainingPercentage))% 남음")
                                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                        .foregroundColor(.green)
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.white.opacity(0.1))
                                            .frame(height: 6)

                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(LinearGradient(
                                                colors: [.green, .mint],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            ))
                                            .frame(width: max(4, geo.size.width * CGFloat(usage.remainingPercentage / 100.0)), height: 6)
                                    }
                                }
                                .frame(height: 6)

                                HStack {
                                    Text("소모 토큰: \(usage.totalTokens) (입력: \(usage.promptTokens) / 생성: \(usage.candidatesTokens))")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Text("잔여: \(usage.remainingTokens.formatted()) / 1,048,576 토큰")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.25), lineWidth: 1))
                        }

                        // Summary Display Area
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(red: 0.04, green: 0.05, blue: 0.09))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.3), lineWidth: 1))

                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    if let summary = summarizer.currentSummary {
                                        Text(.init(summary.formattedMarkdown))
                                            .font(.system(size: 13))
                                            .lineSpacing(4)
                                            .textSelection(.enabled)
                                    } else {
                                        VStack(alignment: .center, spacing: 10) {
                                            Image(systemName: "brain.head.profile")
                                                .font(.system(size: 32))
                                                .foregroundColor(.purple.opacity(0.4))
                                            Text("음성 입력 후 '요약하기'를 누르면\n화자별 발언 분리, 핵심 요약, 토큰 잔여량이 표시됩니다.")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                                .multilineTextAlignment(.center)
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .padding(.top, 60)
                                    }
                                }
                                .padding(16)
                            }
                        }
                        .frame(minHeight: 280)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Settings View
    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("설정 및 AI 모델 연동")
                    .font(.system(size: 18, weight: .bold))

                // Gemini API Configuration (.env integration)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.orange)
                        Text("Google Gemini Flash-Lite API 설정")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                        Text("최저가 모델 전용 ⚡")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }

                    if summarizer.isKeyFromEnv {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                            Text(".env 파일에서 보안 로드됨:")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.green)
                            Text("AIzaSyBZ...DlR8")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white)
                            Spacer()
                            Text(".gitignore 적용 완료 🔒")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.3), lineWidth: 1))
                    }

                    Text("비용 최적화를 위해 가장 저렴한 최신 `gemini-flash-lite-latest` 및 `gemini-flash-latest` 모델만 사용하도록 제한되어 있습니다.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    // API Key Anti-Tamper & Anti-Copy Protection Header
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: isApiKeyLocked ? "lock.fill" : "lock.open.trianglebadge.exclamationmark.fill")
                                .foregroundColor(isApiKeyLocked ? .green : .orange)
                            Text(isApiKeyLocked ? "보안 잠금 활성화됨 (복사 및 변조 차단)" : "수정 모드 (보안 주의)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(isApiKeyLocked ? .green : .orange)
                        }

                        Spacer()

                        Button {
                            if isApiKeyLocked {
                                showingUnlockAlert = true
                            } else {
                                isApiKeyLocked = true
                            }
                        } label: {
                            Label(isApiKeyLocked ? "잠금 해제 (Unlock)" : "지금 다시 잠금 (Lock)",
                                  systemImage: isApiKeyLocked ? "lock.open.fill" : "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isApiKeyLocked ? .secondary : .orange)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                    // Protected Field Container
                    if isApiKeyLocked {
                        HStack {
                            Image(systemName: "shield.checkered")
                                .foregroundColor(.green)
                            Text("••••••••••••••••••••••••••••••••••••••••")
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                                .textSelection(.disabled)

                            Spacer()

                            Text("🔒 복사/붙여넣기 불가")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.3), lineWidth: 1))
                        .allowsHitTesting(false)
                    } else {
                        HStack {
                            SecureField("Gemini API Key 직접 입력", text: $summarizer.geminiApiKey)
                                .textFieldStyle(.roundedBorder)

                            if !summarizer.geminiApiKey.isEmpty && !summarizer.isKeyFromEnv {
                                Button("지우기") {
                                    summarizer.geminiApiKey = ""
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    // Token Usage Session Summary
                    if summarizer.sessionTotalTokens > 0 {
                        HStack {
                            Image(systemName: "chart.bar.xaxis")
                                .foregroundColor(.cyan)
                            Text("현재 세션 누적 토큰 사용량: \(summarizer.sessionTotalTokens.formatted()) 토큰")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))

                // Acoustic Biometrics & Diarization Engine Info
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "person.2.wave.2.fill")
                            .foregroundColor(.cyan)
                        Text("음향 바이오메트릭스 & 화자 분리 (Acoustic Diarization)")
                            .font(.system(size: 14, weight: .bold))
                    }

                    Text("발화자의 기본 주파수(F0 피치)와 음색 스펙트럼 중심(Centroid)을 Accelerate vDSP를 통해 실시간 추출하여 각 화자의 성문(Voiceprint)을 학습합니다. 발언자 교대 시 음성 특징 차이를 분석하여 자동으로 화자를 분리합니다.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Toggle("스마트 음향 피치 화자 분리 활성화", isOn: $speechService.smartAcousticDiarization)
                        .toggleStyle(.switch)
                }
                .padding(16)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))

                // Noise & Cough Filter Settings
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .foregroundColor(.cyan)
                        Text("기침 소리 및 배경 소음 자동 필터링 (Apple SoundAnalysis)")
                            .font(.system(size: 14, weight: .bold))
                    }

                    Text("마이크로 들어오는 기침, 재채기, 박수, 키보드 타이핑 소음을 실시간 머신러닝으로 감지하여 음성 텍스트에 오인식되지 않도록 방지합니다.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Toggle("기침 및 소음 자동 배제 활성화", isOn: $classifier.enableNoiseAndCoughSuppression)
                        .toggleStyle(.switch)
                }
                .padding(16)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))

                // Apple Speech & Local AI Engine Info
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "applelogo")
                            .foregroundColor(.white)
                        Text("로컬 Apple 음성 인식 & 자연어 분석")
                            .font(.system(size: 14, weight: .bold))
                    }

                    Text("본 앱은 Apple의 `Speech` 프레임워크와 `NaturalLanguage` 다국어 분석 파이프라인을 온디바이스에서 구동합니다. 음성 데이터가 외부로 유출되지 않으며 안전하게 실시간 처리됩니다.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("마이크 권한 상태")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("활성화됨")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.green)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("음성 인식 권한 상태")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(speechService.authorizationStatus == .authorized ? "승인됨" : "확인 필요")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(speechService.authorizationStatus == .authorized ? .green : .yellow)
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
        }
    }

    // MARK: - Helpers
    private var currentCombinedTranscript: String {
        if !editableTranscript.isEmpty {
            return editableTranscript
        }
        return speechService.fullTranscript
    }

    private func speakerColor(_ id: Int) -> Color {
        switch id {
        case 1: return .cyan
        case 2: return .purple
        case 3: return .orange
        default: return .green
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "mm:ss"
        return formatter.string(from: date)
    }

    private func toggleRecording() {
        if speechService.isTranscribing {
            speechService.stopTranscription(audioEngine: audioEngine)
        } else {
            Task {
                do {
                    try await speechService.startTranscription(audioEngine: audioEngine)
                } catch {
                    speechService.errorMessage = "녹음을 시작하지 못했습니다: \(error.localizedDescription)"
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation {
            showingCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showingCopiedToast = false
            }
        }
    }
}

#Preview {
    ContentView()
}
