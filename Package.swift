// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShakeAndSound",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ShakeAndSoundCore",
            targets: ["ShakeAndSoundCore"]
        ),
        .executable(
            name: "shakeandsound-cli",
            targets: ["ShakeAndSoundCLI"]
        )
    ],
    targets: [
        .target(
            name: "ShakeAndSoundCore",
            path: "ShakeAndSound",
            exclude: [
                "Assets.xcassets",
                "Resources",
                "AudioClassifierService.swift",
                "AudioWaveformEngine.swift",
                "ContentView.swift",
                "MyApp.swift",
                "SeismoView.swift",
                "SeismographService.swift",
                "SoundVisualizerView.swift",
                "SpeechTranscriptionService.swift",
                "SummarizationService.swift"
            ],
            sources: [
                "MotionKinematicsEngine.swift",
                "ProceduralAudioSynthesizer.swift",
                "TempoHapticCurveEngine.swift",
                "ShakeAndSoundTelemetry.swift"
            ]
        ),
        .executableTarget(
            name: "ShakeAndSoundCLI",
            dependencies: ["ShakeAndSoundCore"],
            path: "Sources/ShakeAndSoundCLI"
        ),
        .testTarget(
            name: "ShakeAndSoundTests",
            dependencies: ["ShakeAndSoundCore"],
            path: "Tests/ShakeAndSoundTests"
        )
    ]
)
