import Foundation
import Combine

public struct SeismicSample: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let x: Double
    public let y: Double
    public let z: Double
    public let magnitude: Double
    public let isTriggered: Bool
}

public struct SeismicEvent: Identifiable {
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
    @Published public var triggerThreshold: Double = 4.0
    @Published public var isSimulatedMode: Bool = true                  // Safe default for all Macs without root
    @Published public var sensorSensitivity: Double = 1.0

    private var timer: Timer?
    private var staEnergy: Double = 0.0
    private var ltaEnergy: Double = 0.0
    private let staAlpha: Double = 0.15     // Short term weight
    private let ltaAlpha: Double = 0.01     // Long term weight
    private let maxHistorySamples = 180

    public init() {}

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        staEnergy = 0.01
        ltaEnergy = 0.01

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleStep()
            }
        }
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        currentPGA = 0.0
        staLtaRatio = 1.0
        isEventTriggered = false
    }

    public func injectImpulse(type: String, strength: Double = 1.0) {
        impulseStrength = strength * 85.0
        impulseLabel = type
    }

    private var impulseStrength: Double = 0.0
    private var impulseLabel: String = "외력 충격"

    private func sampleStep() {
        // Base ambient noise floor (0.2 ~ 0.8 mg)
        var noiseX = Double.random(in: -0.4...0.4)
        var noiseY = Double.random(in: -0.4...0.4)
        var noiseZ = Double.random(in: -0.4...0.4)

        if impulseStrength > 0.01 {
            let impulse = impulseStrength * Double.random(in: 0.7...1.3)
            noiseX += impulse * 0.8
            noiseY += impulse * 0.5
            noiseZ += impulse * 1.2
            impulseStrength *= 0.82 // decay
        }

        let mag = sqrt(noiseX * noiseX + noiseY * noiseY + noiseZ * noiseZ) * sensorSensitivity
        let pga = mag * 1.2

        // STA/LTA calculation
        let instantEnergy = mag * mag
        staEnergy = staAlpha * instantEnergy + (1.0 - staAlpha) * staEnergy
        ltaEnergy = ltaAlpha * instantEnergy + (1.0 - ltaAlpha) * ltaEnergy

        let ratio = max(0.5, staEnergy / max(0.001, ltaEnergy))
        let triggered = ratio >= triggerThreshold

        self.currentPGA = pga
        self.staLtaRatio = ratio
        self.isEventTriggered = triggered

        if triggered && (detectedEvents.isEmpty || Date().timeIntervalSince(detectedEvents.first?.timestamp ?? .distantPast) > 2.0) {
            let event = SeismicEvent(
                timestamp: Date(),
                peakPGA: pga,
                staLtaRatio: ratio,
                label: impulseStrength > 1.0 ? impulseLabel : "진동 감지 (Tremor)"
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
