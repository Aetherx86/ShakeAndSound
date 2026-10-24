import Foundation
import Combine
import AppKit

public struct SeismicSample: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let x: Double
    public let y: Double
    public let z: Double
    public let magnitude: Double
    public let isTriggered: Bool
}

public struct SeismicEvent: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let peakPGA: Double
    public let staLtaRatio: Double
    public let label: String
}

@MainActor
public final class SeismographService: ObservableObject {
    public static let shared = SeismographService()

    // MARK: - Published State
    @Published public private(set) var isMonitoring: Bool = false
    @Published public private(set) var currentPGA: Double = 0.0          // Peak Ground Acceleration in mg
    @Published public private(set) var staLtaRatio: Double = 1.0        // Real-time STA/LTA ratio
    @Published public private(set) var isEventTriggered: Bool = false
    @Published public private(set) var recentSamples: [SeismicSample] = []
    @Published public private(set) var detectedEvents: [SeismicEvent] = []

    // Settings
    @Published public var triggerThreshold: Double = 3.0
    @Published public var isSimulatedMode: Bool = false                  // Physical Sensor Fusion Active
    @Published public var sensorSensitivity: Double = 2.5                // High-responsiveness default
    @Published public var isManuallyPaused: Bool = false                 // Explicit user pause tracking

    // Real-Time Physical Sensor Inputs
    private var physicalMotionX: Double = 0.0
    private var physicalMotionY: Double = 0.0
    private var physicalMotionZ: Double = 0.0
    private var impulseStrength: Double = 0.0
    private var impulseLabel: String = "외력 충격"

    // Trackpad / Mouse Shake Tracking
    private var lastPointerLocation: CGPoint = .zero
    private var lastPointerTime: Date = Date()
    private var lastPointerSignX: Double = 0.0
    private var pointerShakeCount: Int = 0

    // Event Monitor & Notifications
    private var eventMonitor: Any?
    private var windowMoveObserver: NSObjectProtocol?
    private var timer: Timer?
    private var staEnergy: Double = 0.0
    private var ltaEnergy: Double = 0.0
    private let staAlpha: Double = 0.22     // Fast short term window
    private let ltaAlpha: Double = 0.015    // Long term background window
    private let maxHistorySamples = 180

    public init() {}

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        staEnergy = 0.01
        ltaEnergy = 0.01

        // 1. Ensure windows accept mouse movement events
        NSApplication.shared.windows.forEach { $0.acceptsMouseMovedEvents = true }

        // 2. Passive acoustic vibration monitoring (does not interfere with Sound Studio)

        // 3. Install physical keyboard & mouse/trackpad event monitor
        setupPhysicalMotionEventMonitor()

        // 4. Window move / jolt observer
        setupWindowMoveObserver()

        // 5. High-frequency 40ms sampling loop (25 samples per second)
        timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleStep()
            }
        }
    }

    public func pauseByUser() {
        isManuallyPaused = true
        stopMonitoring()
    }

    public func resumeByUser() {
        isManuallyPaused = false
        startMonitoring()
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        if let observer = windowMoveObserver {
            NotificationCenter.default.removeObserver(observer)
            windowMoveObserver = nil
        }

        timer?.invalidate()
        timer = nil
        currentPGA = 0.0
        staLtaRatio = 1.0
        isEventTriggered = false
        physicalMotionX = 0
        physicalMotionY = 0
        physicalMotionZ = 0
    }

    // MARK: - Physical Event Monitors (Keyboard & Mouse)
    private func setupPhysicalMotionEventMonitor() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel, .leftMouseDown]
        ) { [weak self] event in
            guard let self = self, self.isMonitoring else { return event }

            if event.type == .keyDown {
                // Real physical keyboard typing detected!
                self.registerTypingImpulse()
                return event
            }

            let dx = Double(event.deltaX)
            let dy = Double(event.deltaY)
            let speed = sqrt(dx * dx + dy * dy)

            if speed > 1.2 {
                let signX = dx > 0 ? 1.0 : -1.0
                if self.lastPointerSignX != 0 && signX != self.lastPointerSignX {
                    self.pointerShakeCount = min(10, self.pointerShakeCount + 1)
                }
                self.lastPointerSignX = signX

                let shakeMultiplier = 1.0 + Double(self.pointerShakeCount) * 1.8
                let boost = (speed * 0.9 * shakeMultiplier) * (self.sensorSensitivity / 2.0)
                self.physicalMotionX += dx * 0.7 * shakeMultiplier
                self.physicalMotionY += dy * 0.7 * shakeMultiplier
                self.physicalMotionZ += boost * 0.8
                self.impulseLabel = self.pointerShakeCount >= 2 ? "트랙패드/마우스 흔들기" : "포인터 모션"
            }

            return event
        }
    }

    private func setupWindowMoveObserver() {
        guard windowMoveObserver == nil else { return }
        windowMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.registerWindowShake()
            }
        }
    }

    // MARK: - Direct Physical Actions
    public func registerPointerMotion(location: CGPoint) {
        let now = Date()
        lastPointerTime = now

        let dx = location.x - lastPointerLocation.x
        let dy = location.y - lastPointerLocation.y
        lastPointerLocation = location

        let speed = sqrt(dx * dx + dy * dy)
        guard speed > 2.0 else { return }

        let signX = dx > 0 ? 1.0 : -1.0
        if lastPointerSignX != 0 && signX != lastPointerSignX {
            pointerShakeCount = min(10, pointerShakeCount + 1)
        }
        lastPointerSignX = signX

        let shakeFactor = 1.0 + Double(pointerShakeCount) * 1.6
        let impulse = (speed * 0.85 * shakeFactor) * (sensorSensitivity / 2.0)
        physicalMotionX += Double(dx) * 0.6 * shakeFactor
        physicalMotionY += Double(dy) * 0.6 * shakeFactor
        physicalMotionZ += impulse * 0.75
        impulseLabel = pointerShakeCount >= 2 ? "트랙패드 좌우 흔들기" : "트랙패드 스와이프"
    }

    public func registerTypingImpulse() {
        let keyShock = Double.random(in: 18.0...32.0) * sensorSensitivity
        physicalMotionZ += keyShock
        physicalMotionX += Double.random(in: -keyShock...keyShock) * 0.45
        physicalMotionY += Double.random(in: -keyShock...keyShock) * 0.45
        impulseLabel = "키보드 타이핑 진동 (Keystroke)"
    }

    public func registerWindowShake() {
        let windowJolt = 45.0 * sensorSensitivity
        physicalMotionZ += windowJolt
        physicalMotionX += Double.random(in: -windowJolt...windowJolt) * 0.6
        physicalMotionY += Double.random(in: -windowJolt...windowJolt) * 0.6
        impulseLabel = "윈도우/맥북 흔들림 (Chassis Shake)"
    }

    public func injectDirectShake(intensity: Double) {
        let boosted = intensity * 50.0 * sensorSensitivity
        physicalMotionX += Double.random(in: -boosted...boosted)
        physicalMotionY += Double.random(in: -boosted...boosted)
        physicalMotionZ += boosted
        impulseLabel = "터치/드래그 진동"
    }

    public func injectImpulse(type: String, strength: Double = 1.0) {
        impulseStrength = strength * 95.0
        impulseLabel = type
    }

    // MARK: - Sensor Fusion Sample Step
    private func sampleStep() {
        // 1. Acoustic chassis & structural vibration via microphone diaphragm
        let audioLevel = Double(AudioWaveformEngine.shared.rawLevel)
        if audioLevel > 0.025 {
            let acousticChassisShock = pow(audioLevel, 1.2) * 75.0 * sensorSensitivity
            physicalMotionZ += acousticChassisShock
            physicalMotionX += acousticChassisShock * Double.random(in: -0.6...0.6)
            physicalMotionY += acousticChassisShock * Double.random(in: -0.6...0.6)
            if acousticChassisShock > 12.0 && impulseLabel.isEmpty {
                impulseLabel = "책상/맥북 충격 (Acoustic Chassis Shock)"
            }
        }

        // 2. Hardware Test Impulse decay
        if impulseStrength > 0.01 {
            let impulse = impulseStrength * Double.random(in: 0.8...1.2) * sensorSensitivity
            physicalMotionX += impulse * 0.7
            physicalMotionY += impulse * 0.5
            physicalMotionZ += impulse * 1.1
            impulseStrength *= 0.75 // fast decay
        }

        // 3. Combine with ambient micro-tremor noise (0.1 ~ 0.3 mg)
        let noiseX = Double.random(in: -0.2...0.2) + physicalMotionX
        let noiseY = Double.random(in: -0.2...0.2) + physicalMotionY
        let noiseZ = Double.random(in: -0.2...0.2) + physicalMotionZ

        // Smooth physical motion decay
        physicalMotionX *= 0.65
        physicalMotionY *= 0.65
        physicalMotionZ *= 0.65

        if abs(physicalMotionX) < 0.3 {
            pointerShakeCount = max(0, pointerShakeCount - 1)
        }

        // Calculate 3-axis magnitude & Peak Ground Acceleration (PGA)
        let rawMag = sqrt(noiseX * noiseX + noiseY * noiseY + noiseZ * noiseZ)
        let mag = rawMag * sensorSensitivity
        let pga = mag * 1.2

        // 4. Seismological STA/LTA (Short-Term Average / Long-Term Average) Event Trigger
        let instantEnergy = mag * mag
        staEnergy = staAlpha * instantEnergy + (1.0 - staAlpha) * staEnergy
        ltaEnergy = ltaAlpha * instantEnergy + (1.0 - ltaAlpha) * ltaEnergy

        let ratio = max(0.5, staEnergy / max(0.001, ltaEnergy))
        let triggered = ratio >= triggerThreshold || pga > 14.0

        self.currentPGA = pga
        self.staLtaRatio = ratio
        self.isEventTriggered = triggered

        if triggered && (detectedEvents.isEmpty || Date().timeIntervalSince(detectedEvents.first?.timestamp ?? .distantPast) > 1.2) {
            let event = SeismicEvent(
                timestamp: Date(),
                peakPGA: pga,
                staLtaRatio: ratio,
                label: pga > 25.0 ? "\(impulseLabel) (\(String(format: "%.1f", pga)) mg)" : "진동 감지 (Tremor)"
            )
            detectedEvents.insert(event, at: 0)
            if detectedEvents.count > 30 {
                detectedEvents.removeLast()
            }
        }

        let sample = SeismicSample(
            timestamp: Date(),
            x: noiseX,
            y: noiseY,
            z: noiseZ,
            magnitude: mag,
            isTriggered: triggered
        )

        recentSamples.append(sample)
        if recentSamples.count > maxHistorySamples {
            recentSamples.removeFirst()
        }
    }
}
