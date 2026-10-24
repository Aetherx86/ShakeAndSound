import SwiftUI

public struct SeismoView: View {
    @ObservedObject var seismoService = SeismographService.shared
    @FocusState private var isViewFocused: Bool

    public init() {}

    public var body: some View {
        VStack(spacing: 18) {
            // Header stats row
            HStack(spacing: 16) {
                // PGA Card
                StatCard(
                    title: "PEAK GROUND ACCEL",
                    value: String(format: "%.2f mg", seismoService.currentPGA),
                    subvalue: seismoService.currentPGA > 12.0 ? "강한 진동 발생" : "정상 배경 진동",
                    icon: "waveform.path.ecg",
                    tintColor: seismoService.currentPGA > 12.0 ? .orange : .cyan
                )

                // STA/LTA Ratio Card
                StatCard(
                    title: "STA / LTA RATIO",
                    value: String(format: "%.2f", seismoService.staLtaRatio),
                    subvalue: "Trigger 임계값: \(String(format: "%.1f", seismoService.triggerThreshold))",
                    icon: "bell.badge",
                    tintColor: seismoService.isEventTriggered ? .red : .purple
                )

                // Status Card
                StatCard(
                    title: "PHYSICAL SENSOR STATUS",
                    value: seismoService.isMonitoring ? (seismoService.isEventTriggered ? "SHAKE DETECTED!" : "LIVE SENSING") : "IDLE",
                    subvalue: "Keyboard + Trackpad + Acoustic Fusion",
                    icon: "wave.3.forward",
                    tintColor: seismoService.isEventTriggered ? .red : (seismoService.isMonitoring ? .green : .secondary)
                )
            }

            // Real-time Helicorder / Waveform Canvas
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("HELICORDER WAVEFORM (REAL-TIME SEISMIC FEED)", systemImage: "waveform.path.badge.plus")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(seismoService.isEventTriggered ? .red : .cyan)

                    Spacer()

                    if seismoService.isEventTriggered {
                        Text("🚨 진동 이벤트 감지됨!")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(.red)
                    }

                    Text("\(seismoService.recentSamples.count) samples / 40ms")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.03, green: 0.05, blue: 0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(seismoService.isEventTriggered ? Color.red.opacity(0.85) : Color.cyan.opacity(0.2), lineWidth: seismoService.isEventTriggered ? 2.5 : 1)
                        )

                    Canvas { context, size in
                        let samples = seismoService.recentSamples
                        guard samples.count > 1 else { return }

                        let midY = size.height / 2.0
                        let width = size.width
                        let stepX = width / CGFloat(max(1, samples.count - 1))

                        // Grid lines
                        var gridPath = Path()
                        gridPath.move(to: CGPoint(x: 0, y: midY))
                        gridPath.addLine(to: CGPoint(x: width, y: midY))
                        context.stroke(gridPath, with: .color(Color.cyan.opacity(0.15)), lineWidth: 0.8)

                        // Draw seismic waveform
                        var wavePath = Path()
                        for (i, sample) in samples.enumerated() {
                            let x = CGFloat(i) * stepX
                            let yOffset = CGFloat(sample.magnitude) * 2.2
                            let y = midY - yOffset

                            if i == 0 {
                                wavePath.move(to: CGPoint(x: x, y: y))
                            } else {
                                wavePath.addLine(to: CGPoint(x: x, y: y))
                            }
                        }

                        context.addFilter(.blur(radius: 2))
                        context.stroke(wavePath, with: .color(seismoService.isEventTriggered ? Color.red.opacity(0.7) : Color.cyan.opacity(0.4)), lineWidth: 3)

                        context.addFilter(.blur(radius: 0))
                        context.stroke(wavePath, with: .color(seismoService.isEventTriggered ? Color.red : Color.cyan), lineWidth: 1.6)
                    }

                    // Direct Drag / Tap Interaction
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let translation = value.translation
                                    let dragSpeed = sqrt(translation.width * translation.width + translation.height * translation.height)
                                    seismoService.injectDirectShake(intensity: Double(min(5.0, dragSpeed / 10.0)))
                                }
                        )
                }
                .frame(height: 170)
            }

            // Real-Time Sensor Input Status & Sensitivity Slider
            HStack(spacing: 12) {
                Label("센서 감도:", systemImage: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.cyan)

                Slider(value: $seismoService.sensorSensitivity, in: 0.5...5.0, step: 0.5)
                    .frame(width: 130)

                Text("\(String(format: "%.1f", seismoService.sensorSensitivity))x")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(seismoService.isMonitoring ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text("🟢 실시간 감지 중: 키보드 타이핑, 트랙패드/마우스 흔들기, 책상/맥북 충격")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))

            // Quick Impulse Injection Buttons
            VStack(alignment: .leading, spacing: 10) {
                Text("TEST IMPULSE INJECTION (원터치 충격 시뮬레이션)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button {
                        seismoService.injectImpulse(type: "책상 톡톡 두드림", strength: 0.7)
                    } label: {
                        Label("책상 두드림 (Tap)", systemImage: "hand.tap.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        seismoService.injectImpulse(type: "키보드 타이핑 진동", strength: 0.4)
                    } label: {
                        Label("타이핑 진동", systemImage: "keyboard.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        seismoService.injectImpulse(type: "발걸음 쿵쿵 충격", strength: 0.9)
                    } label: {
                        Label("발걸음 충격", systemImage: "figure.walk")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        seismoService.injectImpulse(type: "강한 지진 흔들림", strength: 2.2)
                    } label: {
                        Label("지진 경보 이벤트", systemImage: "exclamationmark.triangle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Spacer()

                    Button {
                        if seismoService.isMonitoring {
                            seismoService.stopMonitoring()
                        } else {
                            seismoService.startMonitoring()
                        }
                    } label: {
                        Label(seismoService.isMonitoring ? "모니터링 일시정지" : "지진계 시작",
                              systemImage: seismoService.isMonitoring ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(seismoService.isMonitoring ? .orange : .green)
                }
            }

            // Detected Events History
            if !seismoService.detectedEvents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("DETECTED TREMOR EVENTS LOG (\(seismoService.detectedEvents.count)건)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(seismoService.detectedEvents) { event in
                                HStack {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)

                                    Text(event.label)
                                        .font(.system(size: 12, weight: .semibold))

                                    Spacer()

                                    Text("PGA: \(String(format: "%.1f", event.peakPGA)) mg")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.orange)

                                    Text("STA/LTA: \(String(format: "%.2f", event.staLtaRatio))")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.purple)

                                    Text(event.timestamp, style: .time)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }
        }
        .padding()
        .focusable()
        .focused($isViewFocused)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                seismoService.registerPointerMotion(location: location)
            case .ended:
                break
            }
        }
        .onAppear {
            isViewFocused = true
            DispatchQueue.main.async {
                NSApplication.shared.windows.forEach { $0.acceptsMouseMovedEvents = true }
            }
            if !seismoService.isMonitoring {
                seismoService.startMonitoring()
            }
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let subvalue: String
    let icon: String
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: icon)
                    .foregroundColor(tintColor)
            }

            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white)

            Text(subvalue)
                .font(.system(size: 10))
                .foregroundColor(tintColor)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tintColor.opacity(0.3), lineWidth: 1))
    }
}
