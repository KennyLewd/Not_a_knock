import AppKit
import CoreGraphics

@MainActor
final class ActionRunner {
    static let shared = ActionRunner()
    /// Virtual key for "5" on the standard layout, so the pair is Cmd+Shift+5.
    static let screenshotKey: CGKeyCode = 23
    /// Virtual key for "q", so the pair is Ctrl+Cmd+Q.
    static let lockScreenKey: CGKeyCode = 12
    private init() {}

    func run(_ action: KnockAction, reaction: @escaping (ReactionKind) -> Void) {
        switch action {
        case .none:
            return
        case .copy:
            pressKey(8, flags: .maskCommand)
        case .paste:
            pressKey(9, flags: .maskCommand)
        case .screenshot:
            // Cmd+Shift+5 opens the capture tool, matching this action's description.
            // Cmd+Shift+4 only armed the crosshair and saved nothing unless the user
            // then dragged a region, which is not possible mid-knock.
            pressKey(Self.screenshotKey, flags: [.maskCommand, .maskShift])
        case .lockScreen:
            // Ctrl+Cmd+Q is the system Lock Screen shortcut. The CGSession helper
            // this used to spawn lives in a Menu Extra that no longer ships — the
            // path is absent on macOS 27 — and `try? task.run()` swallowed the
            // failure, so the action did nothing at all and said nothing about it.
            pressKey(Self.lockScreenKey, flags: [.maskControl, .maskCommand])
        case .mute:
            runAppleScript("set volume output muted not (output muted of (get volume settings))")
        case .playPause:
            mediaKey(16)
        case .missionControl:
            pressKey(160)
        case .launchpad:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Launchpad.app"))
        case .showText:
            reaction(.message)
        case .shockwave:
            reaction(.shockwave)
        case .randomReaction:
            reaction(ReactionKind.allCases.randomElement() ?? .sparkles)
        case .openFinder:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        case .openMusic:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app"))
        case .runShortcut:
            reaction(.shortcutHint)
        }
    }

    private func pressKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func runAppleScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    private func mediaKey(_ key: Int32) {
        let flags = NSEvent.ModifierFlags(rawValue: 0xA00)
        let keyDown = Int((key << 16) | (0xA << 8))
        let keyUp = Int((key << 16) | (0xB << 8))
        NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                           timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                           data1: keyDown, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                           timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                           data1: keyUp, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
    }
}

enum ReactionKind: CaseIterable {
    case message, shockwave, sparkles, shortcutHint
}
