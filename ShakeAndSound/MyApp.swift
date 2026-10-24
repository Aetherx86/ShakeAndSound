import SwiftUI
import AppKit

@main
struct MyApp: App {
    init() {
        // Guarantee dock and window app icon is wave-sound.png
        if let iconImage = NSImage(named: "WaveSound") ?? NSImage(contentsOfFile: "/Users/sushikim/Downloads/wave-sound.png") {
            NSApplication.shared.applicationIconImage = iconImage
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
