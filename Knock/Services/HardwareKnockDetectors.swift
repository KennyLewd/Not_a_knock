import AppKit

/// Existing Control+click input, isolated for permission work in T06.
@MainActor
final class TrackpadKnockDetector: KnockDetectorSource {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    override func start() {
        guard status != .running && status != .starting else { return }
        super.start()
        let expected = generation
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .otherMouseDown]) { [weak self] event in
            guard event.modifierFlags.contains(.control) else { return }
            DispatchQueue.main.async {
                guard let self, self.generation == expected else { return }
                self.emitImpulse()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .otherMouseDown]) { [weak self] event in
            if event.modifierFlags.contains(.control), let self, self.generation == expected {
                self.emitImpulse()
            }
            return event
        }
        setStatus(.running)
    }

    override func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        super.stop()
    }
}
