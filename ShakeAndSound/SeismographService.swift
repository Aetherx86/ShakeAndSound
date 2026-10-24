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
    @Published public var triggerThreshold: Double = 3.5
    @Published public var isSimulatedMode: Bool = false                  // Real Sensor Fusion Active
    @Published public var sensorSensitivity: Double = 2.0                // Responsive default

    // Real-Time Physical Sensor Inputs
    private var physicalMotionX: Double = 0.0
    private var physicalMotionY: Double = 0.0
    private var physicalMotionZ: Double = 0.0
    private var impulseStrength: Double = 0.0
    private var impulseLabel: String = "외력 충격"
    private var lastDeltaSignX: Double = 0.0
    private var directionChangeCount: Int = 0

    private var eventMonitor: Any?
    private var timer: Timer?
    private var staEnergy: Double = 0.0
    private var ltaEnergy: Double = 0.0
    private let staAlpha: Double = 0.20     // Fast short term window
    private let ltaAlpha: Double = 0.015    // Long term background window
    private let maxHistorySamples = 180

    public init() {}

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        staEnergy = 0.01
        ltaEnergy = 0.01

        // 1. Ensure audio engine is capturing acoustic chassis vibration (seismometer diaphragm)
        if !AudioWaveformEngine.shared.isRunning {
            try? AudioWaveformEngine.shared.start()
        }

        // 2. Install local mouse/trackpad shake and velocity event monitor
        setupPhysicalMotionEventMonitor()

        // 3. High-frequency 50ms sampling loop
        timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleStep()
            }
        }
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
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

    // MARK: - Physical Shake & Motion Event Listener
    private func setupPhysicalMotionEventMonitor() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel]
        ) { [weak self] event in
            guard let self = self, self.isMonitoring else { return event }

            let dx = Double(event.deltaX)
            let dy = Double(event.deltaY)
            let speed = sqrt(dx * dx + dy * dy)

            // Detect rapid back-and-forth direction reversals (Physical Shaking)
            let currentSignX = dx > 0 ? 1.0 : (dx < 0 ? -1.0 : 0.0)
            if currentSignX != 0 && self.lastDeltaSignX != 0 && currentSignX != self.lastDeltaSignX {
                self.directionChangeCount = min(8, self.directionChangeCount + 1)
            }
            self.lastDeltaSignX = currentSignX

            // Inject physical acceleration proportional to shake speed & reversals
            if speed > 4.0 {
                let shakeFactor = 1.0 + Double(self.directionChangeCount) * 1.2
                self.physicalMotionX += dx * 0.35 * shakeFactor
                self.physicalMotionY += dy * 0.35 * shakeFactor
                self.physicalMotionZ += (speed * 0.25) * shakeFactor
            }

            return event
        }
    }

    // MARK: - Direct Impulses
    public func injectDirectShake(intensity: Double) {
        let boosted = intensity * 45.0 * sensorSensitivity
        physicalMotionX += Double.random(in: -boosted...boosted)
        physicalMotionY += Double.random(in: -boosted...boosted)
        physicalMotionZ += boosted
        impulseLabel = "직접 흔들기 (Shake)"
    }

    public func injectImpulse(type: String, strength: Double = 1.0) {
        impulseStrength = strength * 90.0
        impulseLabel = type
    }

    // MARK: - Sensor Fusion Sample Step
    private func sampleStep() {
        // 1. Acoustic chassis & structural vibration via microphone diaphragm
        let audioLevel = Double(AudioWaveformEngine.shared.rawLevel)
        if audioLevel > 0.035 {
            let acousticChassisShock = pow(audioLevel, 1.3) * 60.0 * sensorSensitivity
            physicalMotionZ += acousticChassisShock
            physicalMotionX += acousticChassisShock * Double.random(in: -0.6...0.6)
            physicalMotionY += acousticChassisShock * Double.random(in: -0.6...0.6)
        }

        // 2. Hardware Test Impulse decay
        if impulseStrength > 0.01 {
            let impulse = impulseStrength * Double.random(in: 0.8...1.2) * sensorSensitivity
            physicalMotionX += impulse * 0.7
            physicalMotionY += impulse * 0.5
            physicalMotionZ += impulse * 1.1
            impulseStrength *= 0.78 // fast decay
        }

        // 3. Base ambient micro-tremor noise (0.1 ~ 0.4 mg)
        let noiseX = Double.random(in: -0.25...0.25) + physicalMotionX
        let noiseY = Double.random(in: -0.25...0.25) + physicalMotionY
        let noiseZ = Double.random(in: -0.25...0.25) + physicalMotionZ

        // Smooth physical motion decay
        physicalMotionX *= 0.68
        physicalMotionY *= 0.68
        physicalMotionZ *= 0.68

        if abs(physicalMotionX) < 0.5 {
            directionChangeCount = max(0, directionChangeCount - 1)
        }

        // Calculate 3-axis magnitude & Peak Ground Acceleration (PGA)
        let rawMag = sqrt(noiseX * noiseX + noiseY * noiseY + noiseZ * noiseZ)
        let mag = rawMag * sensorSensitivity
        let pga = mag * 1.25

        // 4. Seismological STA/LTA (Short-Term Average / Long-Term Average) Event Trigger
        let instantEnergy = mag * mag
        staEnergy = staAlpha * instantEnergy + (1.0 - staAlpha) * staEnergy
        ltaEnergy = ltaAlpha * instantEnergy + (1.0 - ltaAlpha) * ltaEnergy

        let ratio = max(0.5, staEnergy / max(0.001, ltaEnergy))
        let triggered = ratio >= triggerThreshold || pga > 15.0

        self.currentPGA = pga
        self.staLtaRatio = ratio
        self.isEventTriggered = triggered

        if triggered && (detectedEvents.isEmpty || Date().timeIntervalSince(detectedEvents.first?.timestamp ?? .distantPast) > 1.8) {
            let event = SeismicEvent(
                timestamp: Date(),
                peakPGA: pga,
                staLtaRatio: ratio,
                label: pga > 30.0 ? "강한 진동/흔들림 감지 (Strong Shake)" : "진동 감지 (Tremor)"
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
