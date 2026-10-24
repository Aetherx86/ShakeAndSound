import SwiftUI

public struct SeismoView: View {
    @ObservedObject var seismoService = SeismographService.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            // Header stats row
            HStack(spacing: 16) {
                // PGA Card
                StatCard(
                    title: "PEAK GROUND ACCEL",
                    value: String(format: "%.2f mg", seismoService.currentPGA),
                    subvalue: seismoService.currentPGA > 10.0 ? "강한 진동" : "정상 진동 폭",
                    icon: "waveform.path.ecg",
                    tintColor: seismoService.currentPGA > 10.0 ? .orange : .cyan
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
                    title: "IMU SENSOR STATUS",
                    value: seismoService.isMonitoring ? (seismoService.isEventTriggered ? "EVENT DETECTED!" : "ACTIVE STREAM") : "IDLE",
                    subvalue: seismoService.isSimulatedMode ? "Synthetic MEMS Mock" : "Apple SPU Direct",
                    icon: "cpu",
                    tintColor: seismoService.isEventTriggered ? .red : (seismoService.isMonitoring ? .green : .secondary)
                )
            }

            // Real-time Helicorder / Waveform Canvas
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("HELICORDER WAVEFORM (REAL-TIME SEISMIC FEED)", systemImage: "waveform.path.badge.plus")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)

                    Spacer()

                    Text("\(seismoService.recentSamples.count) samples / 50ms")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.03, green: 0.05, blue: 0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
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
                            let yOffset = CGFloat(sample.magnitude) * 1.8
                            let y = midY - yOffset

                            if i == 0 {
                                wavePath.move(to: CGPoint(x: x, y: y))
                            } else {
                                wavePath.addLine(to: CGPoint(x: x, y: y))
                            }
                        }

                        context.addFilter(.blur(radius: 2))
                        context.stroke(wavePath, with: .color(seismoService.isEventTriggered ? Color.red.opacity(0.6) : Color.cyan.opacity(0.4)), lineWidth: 3)

                        context.addFilter(.blur(radius: 0))
                        context.stroke(wavePath, with: .color(seismoService.isEventTriggered ? Color.red : Color.cyan), lineWidth: 1.5)
                    }
                }
                .frame(height: 160)
            }

            // Quick Impulse Injection Buttons
            VStack(alignment: .leading, spacing: 10) {
                Text("TEST IMPULSE GENERATION (하드웨어 진동 시뮬레이션)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button {
                        seismoService.injectImpulse(type: "책상 톡톡 두드림", strength: 0.5)
                    } label: {
                        Label("책상 두드림 (Tap)", systemImage: "hand.tap.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        seismoService.injectImpulse(type: "키보드 타이핑 진동", strength: 0.25)
                    } label: {
                        Label("타이핑 진동", systemImage: "keyboard.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        seismoService.injectImpulse(type: "발걸음 충격", strength: 0.8)
                    } label: {
                        Label("발걸음 충격", systemImage: "figure.walk")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        seismoService.injectImpulse(type: "지진 흔들림 이벤트", strength: 1.6)
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
                        Label(seismoService.isMonitoring ? "모니터링 중지" : "지진계 시작",
                              systemImage: seismoService.isMonitoring ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(seismoService.isMonitoring ? .orange : .green)
                }
            }

            // Detected Events History
            if !seismoService.detectedEvents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DETECTED TREMOR EVENTS LOG")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

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
        .onAppear {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: icon)
                    .foregroundColor(tintColor)
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)

            Text(subvalue)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tintColor.opacity(0.2), lineWidth: 1)
        )
    }
}
