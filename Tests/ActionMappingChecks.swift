import Foundation

/// Standalone checks compiled with the production model and engine (no hardware input).
@main
struct ActionMappingChecks {
    @MainActor static func main() {
        let suite = "dev.local.Knock.MappingChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = KnockEngine(defaults: defaults)
        precondition(engine.action(for: .single) == .playPause)
        precondition(engine.action(for: .double) == .screenshot)
        precondition(engine.action(for: .triple) == .shockwave)

        // Every assignment round-trips, while the other two patterns stay intact.
        for pattern in KnockPattern.allCases {
            for action in KnockAction.allCases {
                let before = engine.actions
                engine.setAction(action, for: pattern)
                let reopened = KnockEngine(defaults: defaults)
                precondition(reopened.action(for: pattern) == action)
                for other in KnockPattern.allCases where other != pattern {
                    precondition(reopened.action(for: other) == before[other])
                }
            }
        }
        defaults.set(["1": "copy", "2": 42, "3": "futureAction", "99": "paste"], forKey: "knock.actions")
        let recovered = KnockEngine(defaults: defaults)
        precondition(recovered.action(for: .single) == .copy)
        precondition(recovered.action(for: .double) == .screenshot)
        precondition(recovered.action(for: .triple) == .shockwave)
        defaults.set("invalid", forKey: "knock.actions")
        precondition(KnockEngine(defaults: defaults).action(for: .single) == .playPause)

        let catalog = ActionCategory.allCases.flatMap(\.actions)
        precondition(catalog.count == KnockAction.allCases.count)
        precondition(Set(catalog) == Set(KnockAction.allCases))
        precondition(ActionCategory.essentials.actions(matching: " SCREEN shot ") == [.screenshot])
        precondition(ActionCategory.media.actions(matching: "MEDIA") == [.mute, .playPause])
        precondition(ActionCategory.allCases.flatMap { $0.actions(matching: " MEDIA ") } == [.mute, .playPause])
        precondition(ActionCategory.automation.actions(matching: "named Apple") == [.runShortcut])
        precondition(ActionCategory.reactions.actions(matching: "   ") == ActionCategory.reactions.actions)
        precondition(ActionCategory.allCases.flatMap { $0.actions(matching: "zzzzmissing") }.isEmpty)
        print("PASS: 45 assignment round-trips, independent patterns, defaults/recovery, catalog coverage, and search.")
    }
}
