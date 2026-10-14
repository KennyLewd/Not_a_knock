import SwiftUI

enum SidebarDestination: String, CaseIterable, Identifiable {
    case knocks = "Knocks"
    case activity = "Activity"
    case settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .knocks: "hand.tap.fill"
        case .activity: "waveform.path.ecg"
        case .settings: "gearshape.fill"
        }
    }
    var shortcut: KeyEquivalent {
        switch self {
        case .knocks: "1"
        case .activity: "2"
        case .settings: "3"
        }
    }
    var shortcutLabel: String {
        switch self {
        case .knocks: "⌘1"
        case .activity: "⌘2"
        case .settings: "⌘3"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var engine: KnockEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var destination: SidebarDestination = .knocks

    var body: some View {
        ZStack {
            KnockTheme.canvas.ignoresSafeArea()
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(KnockTheme.border).frame(width: 1)
                Group {
                    switch destination {
                    case .knocks: DashboardView()
                    case .activity: ActivityView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let reaction = engine.reaction {
                ReactionOverlay(kind: reaction)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.94)))
                    .allowsHitTesting(false)
            }
        }
        .foregroundStyle(KnockTheme.primary)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: engine.reaction != nil)
        // Also suppress explicit animation inherited from the draft engine.
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 11) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 38, height: 38)
                    .background(KnockTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                Text("Knock")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 30)

            Text("WORKSPACE")
                .font(KnockTheme.TypeStyle.eyebrow)
                .tracking(1.4)
                .foregroundStyle(KnockTheme.muted)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            ForEach(SidebarDestination.allCases) { item in
                Button { destination = item } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon).frame(width: 18)
                        Text(item.rawValue)
                        Spacer(minLength: 4)
                        Text(item.shortcutLabel)
                            .font(KnockTheme.TypeStyle.caption)
                            .foregroundStyle(KnockTheme.muted)
                    }
                    .font(KnockTheme.TypeStyle.control)
                    .foregroundStyle(destination == item ? KnockTheme.primary : KnockTheme.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(destination == item ? KnockTheme.selected : .clear,
                                in: RoundedRectangle(cornerRadius: KnockTheme.Layout.controlRadius))
                }
                .buttonStyle(KnockButtonStyle())
                .knockFocus { destination = item }
                .keyboardShortcut(item.shortcut, modifiers: .command)
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(destination == item ? .isSelected : [])
                .help("Show \(item.rawValue) (\(item.shortcutLabel))")
            }
            Spacer(minLength: 24)
            StatusCard()
            Label("Made for your Mac", systemImage: "laptopcomputer")
                .font(KnockTheme.TypeStyle.caption)
                .foregroundStyle(KnockTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
        .padding(14)
        .padding(.top, 30)
        .padding(.bottom, 8)
        .frame(width: KnockTheme.Layout.sidebar)
        .background(KnockTheme.sidebar)
    }
}

struct StatusCard: View {
    @EnvironmentObject private var engine: KnockEngine

    var body: some View {
        Button { engine.toggleListening() } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(engine.isListening ? KnockTheme.success : KnockTheme.muted)
                        .frame(width: 7, height: 7)
                    Text(engine.isListening ? "Detecting taps" : "Detection paused")
                        .font(KnockTheme.TypeStyle.control)
                    Spacer(minLength: 0)
                }
                HStack {
                    Text(engine.isListening ? "Pause detection" : "Start detection")
                    Spacer(minLength: 0)
                    Image(systemName: engine.isListening ? "pause.fill" : "play.fill")
                }
                .font(KnockTheme.TypeStyle.caption)
                .foregroundStyle(KnockTheme.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelSurface(radius: 12)
        }
        .buttonStyle(KnockButtonStyle(radius: 12))
        .knockFocus(radius: 12) { engine.toggleListening() }
        .accessibilityLabel(engine.isListening ? "Pause tap detection" : "Start tap detection")
        .accessibilityValue(engine.isListening ? "Detecting taps" : "Paused")
    }
}

struct ReactionOverlay: View {
    let kind: ReactionKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            KnockTheme.scrim.ignoresSafeArea()
            switch kind {
            case .message:
                reactionPill(icon: "hand.tap.fill", text: "Knock knock!")
            case .shockwave:
                if reduceMotion {
                    reactionPill(icon: "hand.tap.fill", text: "Knock detected")
                } else {
                    ZStack {
                        ForEach(0..<3) { index in
                            Circle()
                                .stroke(KnockTheme.ring, lineWidth: 3)
                                .frame(width: animate ? CGFloat(260 + index * 105) : 42,
                                       height: animate ? CGFloat(260 + index * 105) : 42)
                                .opacity(animate ? 0 : 1)
                                .animation(.easeOut(duration: 1).delay(Double(index) * 0.08), value: animate)
                        }
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 40))
                            .padding(26)
                            .background(KnockTheme.raised, in: Circle())
                    }
                }
            case .sparkles:
                reactionPill(icon: "sparkles", text: "Magic!")
            case .shortcutHint:
                reactionPill(icon: "command", text: "Choose a shortcut in Settings")
            }
        }
        .onAppear { if !reduceMotion { animate = true } }
    }

    private func reactionPill(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(KnockTheme.raised, in: Capsule())
            .overlay(Capsule().stroke(KnockTheme.strongBorder))
            .shadow(color: KnockTheme.shadow, radius: 30, y: 14)
    }
}
