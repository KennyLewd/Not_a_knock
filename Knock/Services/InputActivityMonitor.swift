import Foundation
import CoreGraphics

/// Reports only how long ago the keyboard or pointer was last used. CGEventSource
/// timing needs no Input Monitoring grant and never reveals which keys were
/// pressed, so suppressing taps during typing cannot become a keystroke log.
@MainActor
protocol InputActivityMonitor: AnyObject {
    func secondsSinceKeyboard() -> Double
    func secondsSincePointer() -> Double
}

@MainActor
final class SystemInputActivityMonitor: InputActivityMonitor {
    private static let keyboard: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
    /// `mouseMoved` is included because physical testing showed bare trackpad
    /// contact registering as taps: a finger landing and sliding disturbs the
    /// chassis even with no click. The cost is that an external mouse, which
    /// cannot shake the chassis, still blocks taps while it moves.
    private static let pointer: [CGEventType] = [.leftMouseDown, .leftMouseUp,
                                                 .rightMouseDown, .rightMouseUp,
                                                 .otherMouseDown, .otherMouseUp,
                                                 .leftMouseDragged, .rightMouseDragged,
                                                 .mouseMoved, .scrollWheel]

    func secondsSinceKeyboard() -> Double { Self.elapsed(Self.keyboard) }
    func secondsSincePointer() -> Double { Self.elapsed(Self.pointer) }

    /// `hidSystemState` counts physical hardware input only, so events Knock's own
    /// actions post do not read back as the user touching the keyboard.
    private static func elapsed(_ types: [CGEventType]) -> Double {
        types.reduce(Double.infinity) { shortest, type in
            let seconds = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: type)
            guard seconds.isFinite, seconds >= 0 else { return shortest }
            return min(shortest, seconds)
        }
    }
}
