import SwiftUI

public enum VisualizerStyle: String, CaseIterable, Identifiable {
    case jarvisWave = "Jarvis Wave"
    case siriOrb = "Siri Hologram"
    case cyberSpectrum = "Cyber Spectrum"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .jarvisWave: return "waveform.path"
        case .siriOrb: return "circle.hexagongrid.fill"
        case .cyberSpectrum: return "chart.bar.xaxis"
        }
    }
}

public struct SoundVisualizerView: View {
    @ObservedObject var audioEngine: AudioWaveformEngine
    @Binding var selectedStyle: VisualizerStyle

    public init(audioEngine: AudioWaveformEngine, selectedStyle: Binding<VisualizerStyle>) {
        self.audioEngine = audioEngine
        self._selectedStyle = selectedStyle
    }

    public var body: some View {
        ZStack {
            // Dark cybernetic glass background
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.06, blue: 0.12),
                            Color(red: 0.02, green: 0.03, blue: 0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(0.35),
                                    Color.purple.opacity(0.25),
                                    Color.blue.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: Color.cyan.opacity(0.12), radius: 20, x: 0, y: 10)

            // Dynamic Visualizer Content
            Group {
                switch selectedStyle {
                case .jarvisWave:
                    JarvisWaveRibbon(level: audioEngine.audioLevel, isRunning: audioEngine.isRunning)
                case .siriOrb:
                    SiriHologramOrb(level: audioEngine.audioLevel, isRunning: audioEngine.isRunning)
                case .cyberSpectrum:
                    CyberSpectrumView(bands: audioEngine.frequencyBands, isRunning: audioEngine.isRunning)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            // Overlay HUD Info
            VStack {
                HStack {
                    // Status Badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(audioEngine.isRunning ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                            .shadow(color: audioEngine.isRunning ? Color.green : Color.clear, radius: 4)

                        Text(audioEngine.isRunning ? "LISTENING (MIC ACTIVE)" : "STANDBY")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(audioEngine.isRunning ? .green : .secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))

                    Spacer()

                    // Visualizer Mode Selector
                    Picker("", selection: $selectedStyle) {
                        ForEach(VisualizerStyle.allCases) { style in
                            Label(style.rawValue, systemImage: style.iconName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                // Bottom meter indicator
                HStack(spacing: 12) {
                    Text(String(format: "RMS: %.2f", audioEngine.audioLevel))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.8))

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.cyan, .blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geo.size.width * CGFloat(audioEngine.audioLevel)))
                                .animation(.easeOut(duration: 0.08), value: audioEngine.audioLevel)
                        }
                    }
                    .frame(height: 5)

                    Text(audioEngine.isRunning ? formatDuration(audioEngine.recordingDuration) : "00:00")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }
        }
        .frame(height: 230)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", mins, secs, tenths)
    }
}

// MARK: - 1. Jarvis Wave Ribbon Visualizer
struct JarvisWaveRibbon: View {
    let level: Float
    let isRunning: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let date = timeline.date
            let time = date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let midY = size.height / 2.0
                let width = size.width

                // Background grid lines (Jarvis HUD style)
                drawGrid(context: context, size: size)

                // 4 Layered Waves with neon gradients
                let waveConfigs: [(frequency: CGFloat, speed: CGFloat, phaseOffset: CGFloat, color: Color, opacity: Double, width: CGFloat)] = [
                    (frequency: 0.016, speed: 2.2, phaseOffset: 0.0, color: .cyan, opacity: 0.9, width: 2.6),
                    (frequency: 0.024, speed: 1.6, phaseOffset: 1.8, color: .purple, opacity: 0.8, width: 2.2),
                    (frequency: 0.032, speed: 2.8, phaseOffset: 3.4, color: .blue, opacity: 0.85, width: 2.0),
                    (frequency: 0.012, speed: 1.2, phaseOffset: 4.8, color: Color(red: 0.2, green: 0.9, blue: 0.9), opacity: 0.6, width: 1.5)
                ]

                let activeAmp = CGFloat(max(0.04, level)) * (isRunning ? 60.0 : 8.0)
                let baseIdleAmp: CGFloat = isRunning ? 6.0 : 3.0

                for config in waveConfigs {
                    var path = Path()
                    let totalAmp = baseIdleAmp + activeAmp

                    let step: CGFloat = 3.0
                    path.move(to: CGPoint(x: 0, y: midY))

                    var x: CGFloat = 0
                    while x <= width {
                        // Envelope dampening at edges
                        let normalizedX = x / width
                        let envelope = sin(normalizedX * .pi)

                        let phase = CGFloat(time) * config.speed + config.phaseOffset
                        let yOffset = sin(x * config.frequency + phase) * cos(x * 0.008 + phase * 0.5) * totalAmp * envelope
                        let y = midY + yOffset

                        if x == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        x += step
                    }

                    // Draw glowing wave stroke
                    context.addFilter(.blur(radius: 6))
                    context.stroke(path, with: .color(config.color.opacity(config.opacity * 0.5)), lineWidth: config.width + 4)

                    context.addFilter(.blur(radius: 0))
                    context.stroke(path, with: .color(config.color.opacity(config.opacity)), lineWidth: config.width)
                }

                // Center glowing horizon beam
                var centerPath = Path()
                centerPath.move(to: CGPoint(x: 0, y: midY))
                centerPath.addLine(to: CGPoint(x: width, y: midY))
                context.stroke(
                    centerPath,
                    with: .linearGradient(
                        Gradient(colors: [.clear, .cyan.opacity(0.3), .clear]),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: width, y: midY)
                    ),
                    lineWidth: 1
                )
            }
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let stepX: CGFloat = 40.0
        let stepY: CGFloat = 30.0

        for x in stride(from: CGFloat(0), to: size.width, by: stepX) {
            var p = Path()
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(p, with: .color(Color.cyan.opacity(0.04)), lineWidth: 0.5)
        }

        for y in stride(from: CGFloat(0), to: size.height, by: stepY) {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(p, with: .color(Color.cyan.opacity(0.04)), lineWidth: 0.5)
        }
    }
}

// MARK: - 2. Siri Hologram Orb Visualizer
struct SiriHologramOrb: View {
    let level: Float
    let isRunning: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let date = timeline.date
            let time = date.timeIntervalSinceReferenceDate
            let reactiveScale: CGFloat = 1.0 + CGFloat(level) * (isRunning ? 0.65 : 0.08)

            ZStack {
                // Background radial glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.purple.opacity(0.4),
                                Color.cyan.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 130
                        )
                    )
                    .scaleEffect(reactiveScale * 1.2)
                    .blur(radius: 20)

                // Rotating gradient outer rings
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.cyan, .purple, .pink, .blue, .cyan]),
                            center: .center
                        ),
                        lineWidth: 2.0
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(time * 45))
                    .scaleEffect(reactiveScale)

                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.indigo, .cyan, .purple, .indigo]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                    .frame(width: 165, height: 165)
                    .rotationEffect(.degrees(-time * 30))
                    .scaleEffect(reactiveScale * 1.05)

                // Organic Siri Fluid Core (overlapping morphing circles)
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.0, green: 0.85, blue: 1.0), Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .offset(
                            x: cos(time * 2.0) * 12 * reactiveScale,
                            y: sin(time * 1.8) * 12 * reactiveScale
                        )
                        .opacity(0.75)
                        .blur(radius: 8)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.9, green: 0.2, blue: 0.8), Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 75, height: 75)
                        .offset(
                            x: -sin(time * 1.5) * 14 * reactiveScale,
                            y: cos(time * 2.2) * 10 * reactiveScale
                        )
                        .opacity(0.7)
                        .blur(radius: 8)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.2, green: 1.0, blue: 0.6), Color.cyan],
                                startPoint: .bottomLeading,
                                endPoint: .topTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                        .offset(
                            x: sin(time * 2.7) * 8 * reactiveScale,
                            y: -cos(time * 1.9) * 8 * reactiveScale
                        )
                        .opacity(0.65)
                        .blur(radius: 6)

                    // Core bright spark
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 14 * reactiveScale, height: 14 * reactiveScale)
                        .blur(radius: 2)
                }
            }
        }
    }
}

// MARK: - 3. Cyber Spectrum View
struct CyberSpectrumView: View {
    let bands: [Float]
    let isRunning: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<bands.count, id: \.self) { index in
                let val = CGFloat(bands[index])
                let height = max(8, val * (isRunning ? 140 : 18))

                VStack(spacing: 3) {
                    // Floating peak dot
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 10, height: 2)
                        .shadow(color: .cyan, radius: 3)

                    // Equalizer Bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.cyan,
                                    Color.blue,
                                    Color.purple.opacity(0.8)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 10, height: height)
                        .shadow(color: Color.cyan.opacity(Double(val) * 0.4), radius: 6)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 30)
    }
}
