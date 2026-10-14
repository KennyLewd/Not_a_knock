import SwiftUI

@main
struct KnockApp: App {
    @StateObject private var engine = KnockEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
                .frame(minWidth: KnockTheme.Layout.minimum.width, minHeight: KnockTheme.Layout.minimum.height)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(KnockTheme.Layout.standard)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .windowSize) {
                Button("Compact Size") {
                    NSApplication.shared.keyWindow?.setContentSize(KnockTheme.Layout.minimum)
                }
                Button("Default Size") {
                    if let window = NSApplication.shared.keyWindow {
                        var frame = window.frame
                        frame.size = KnockTheme.Layout.standard
                        window.setFrame(frame, display: true)
                    }
                }
            }
        }

        MenuBarExtra("Knock", systemImage: engine.isListening ? "hand.tap.fill" : "hand.tap") {
            Button(engine.isListening ? "Pause Detection" : "Start Detection") {
                engine.toggleListening()
            }
            Divider()
            Button("Test Single Knock") { engine.simulate(knocks: 1) }
            Button("Test Double Knock") { engine.simulate(knocks: 2) }
            Button("Test Triple Knock") { engine.simulate(knocks: 3) }
            Divider()
            Button("Quit Knock") { NSApplication.shared.terminate(nil) }
        }
    }
}
