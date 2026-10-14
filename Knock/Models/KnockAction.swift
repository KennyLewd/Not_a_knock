import SwiftUI

enum KnockPattern: Int, CaseIterable, Identifiable, Codable {
    case single = 1
    case double = 2
    case triple = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .single: "Single Knock"
        case .double: "Double Knock"
        case .triple: "Triple Knock"
        }
    }

    var shortTitle: String {
        switch self {
        case .single: "Single"
        case .double: "Double"
        case .triple: "Triple"
        }
    }

    var subtitle: String {
        switch self {
        case .single: "One quick tap"
        case .double: "Two quick taps"
        case .triple: "Three quick taps"
        }
    }


}

enum KnockAction: String, CaseIterable, Identifiable, Codable {
    case none
    case copy
    case paste
    case screenshot
    case lockScreen
    case mute
    case playPause
    case missionControl
    case launchpad
    case showText
    case shockwave
    case randomReaction
    case openFinder
    case openMusic
    case runShortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "No Action"
        case .copy: "Copy"
        case .paste: "Paste"
        case .screenshot: "Screenshot"
        case .lockScreen: "Lock Screen"
        case .mute: "Mute"
        case .playPause: "Play / Pause"
        case .missionControl: "Mission Control"
        case .launchpad: "Launchpad"
        case .showText: "Show Text"
        case .shockwave: "Shockwave"
        case .randomReaction: "Random Reaction"
        case .openFinder: "Open Finder"
        case .openMusic: "Open Music"
        case .runShortcut: "Run Shortcut"
        }
    }

    var subtitle: String {
        switch self {
        case .none: "Do nothing for this knock"
        case .copy: "Copy the current selection"
        case .paste: "Paste from the clipboard"
        case .screenshot: "Open the macOS screenshot tool"
        case .lockScreen: "Secure your Mac immediately"
        case .mute: "Toggle system audio"
        case .playPause: "Control the current media app"
        case .missionControl: "See every open window"
        case .launchpad: "Open your apps"
        case .showText: "Display a bold on-screen message"
        case .shockwave: "Send a ripple across the screen"
        case .randomReaction: "Pick a playful visual reaction"
        case .openFinder: "Bring Finder to the front"
        case .openMusic: "Open the Music app"
        case .runShortcut: "Run your named Apple Shortcut"
        }
    }

    var symbol: String {
        switch self {
        case .none: "nosign"
        case .copy: "doc.on.doc"
        case .paste: "clipboard"
        case .screenshot: "viewfinder"
        case .lockScreen: "lock.fill"
        case .mute: "speaker.slash.fill"
        case .playPause: "playpause.fill"
        case .missionControl: "rectangle.3.group"
        case .launchpad: "square.grid.3x3.fill"
        case .showText: "text.bubble.fill"
        case .shockwave: "dot.radiowaves.left.and.right"
        case .randomReaction: "sparkles"
        case .openFinder: "folder.fill"
        case .openMusic: "music.note"
        case .runShortcut: "command"
        }
    }

}

enum ActionCategory: String, CaseIterable, Identifiable {
    case noAction = "No Action"
    case essentials = "Essentials"
    case media = "Media"
    case reactions = "Reactions"
    case automation = "Automation"

    var id: String { rawValue }

    var actions: [KnockAction] {
        switch self {
        case .noAction: [.none]
        case .essentials: [.copy, .paste, .screenshot, .lockScreen, .missionControl, .launchpad]
        case .media: [.mute, .playPause]
        case .reactions: [.showText, .shockwave, .randomReaction]
        case .automation: [.openFinder, .openMusic, .runShortcut]
        }
    }

    func actions(matching query: String) -> [KnockAction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let category = Self.allCases.first(where: {
            $0.rawValue.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return self == category ? actions : []
        }
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return actions.filter { action in
            let searchable = "\(rawValue) \(action.title) \(action.subtitle)"
            return terms.allSatisfy { searchable.localizedStandardContains($0) }
        }
    }
}

enum DetectionMode: String, CaseIterable, Identifiable {
    case macBook = "MacBook"
    case trackpad = "Trackpad"

    var id: String { rawValue }
    var icon: String { self == .macBook ? "laptopcomputer" : "cursorarrow.motionlines" }
}

struct ActivityItem: Identifiable {
    let id = UUID()
    let pattern: KnockPattern
    let action: KnockAction
    let date: Date
}
