import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var engine: KnockEngine
    @State private var editingPattern: KnockPattern?
    @State private var showingAccelerometerSetup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "Your Mac. A tap away.",
                            title: "Small gesture.\nSomething useful.",
                            subtitle: "Give every knock a purpose. Choose an action for each pattern.")
                modeBar
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Your knock actions").font(KnockTheme.TypeStyle.heading)
                        Spacer()
                        Text("3 patterns")
                            .font(KnockTheme.TypeStyle.caption)
                            .foregroundStyle(KnockTheme.muted)
                    }
                    HStack(spacing: KnockTheme.Layout.gap) {
                        ForEach(KnockPattern.allCases) { pattern in
                            ActionCard(pattern: pattern, action: engine.action(for: pattern)) {
                                editingPattern = pattern
                            }
                        }
                    }
                }
                TestPanel()
            }
            .padding(KnockTheme.Layout.page)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingAccelerometerSetup) { AccelerometerSetupView() }
        .sheet(item: $editingPattern) { pattern in
            ActionPicker(pattern: pattern, selected: engine.action(for: pattern)) { action in
                engine.setAction(action, for: pattern)
                editingPattern = nil
            }
        }
    }

    private var modeBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(DetectionMode.allCases) { mode in
                    Button { engine.mode = mode } label: {
                        HStack(spacing: 8) {
                            Image(systemName: mode.icon).font(.system(size: 17))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.rawValue).font(KnockTheme.TypeStyle.control)
                                Text(mode == .macBook ? "Physical taps" : "Control + click")
                                    .font(KnockTheme.TypeStyle.caption)
                                    .foregroundStyle(KnockTheme.secondary)
                            }
                            if engine.mode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(KnockTheme.focus)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 48)
                        .background(engine.mode == mode ? KnockTheme.selected : KnockTheme.surface,
                                    in: RoundedRectangle(cornerRadius: KnockTheme.Layout.controlRadius))
                    }
                    .buttonStyle(KnockButtonStyle())
                    .knockFocus { engine.mode = mode }
                    .accessibilityLabel("\(mode.rawValue) mode")
                    .accessibilityAddTraits(engine.mode == mode ? .isSelected : [])
                }
                Spacer(minLength: 8)
                LiveKnockIndicator()
            }
            if engine.mode == .macBook {
                HStack {
                    Text("Accelerometer tap detection")
                        .font(KnockTheme.TypeStyle.caption).foregroundStyle(KnockTheme.secondary)
                    Spacer()
                    Button("Calibrate & test…") { showingAccelerometerSetup = true }
                        .buttonStyle(.bordered)
                        .knockFocus { showingAccelerometerSetup = true }
                }
            }
            if let message = engine.permissionMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(KnockTheme.TypeStyle.caption)
                    .foregroundStyle(KnockTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct LiveKnockIndicator: View {
    @EnvironmentObject private var engine: KnockEngine

    private var status: String {
        engine.pendingKnocks > 0 ? "Knock detected" : (engine.isListening ? "Ready for a knock" : "Ready to test")
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(index < engine.pendingKnocks ? KnockTheme.success : KnockTheme.strongBorder)
                        .frame(width: 6, height: 6)
                }
            }
            Text(status)
                .font(KnockTheme.TypeStyle.caption)
                .foregroundStyle(KnockTheme.secondary)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status)
        .accessibilityValue("\(engine.pendingKnocks) taps")
    }
}

struct ActionCard: View {
    let pattern: KnockPattern
    let action: KnockAction
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(pattern.shortTitle.uppercased())
                        .font(KnockTheme.TypeStyle.eyebrow)
                        .tracking(1.5)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(0..<pattern.rawValue, id: \.self) { _ in
                            Circle().fill(KnockTheme.onGradientSecondary).frame(width: 5, height: 5)
                        }
                    }
                    .accessibilityHidden(true)
                }
                .foregroundStyle(KnockTheme.onGradientSecondary)
                Image(systemName: action.symbol)
                    .font(.system(size: 25, weight: .medium))
                    .frame(width: 52, height: 52)
                    .background(KnockTheme.iconSurface, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 22)
                    .padding(.bottom, 20)
                Text(action.title)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(action.subtitle)
                    .font(KnockTheme.TypeStyle.caption)
                    .foregroundStyle(KnockTheme.onGradientSecondary)
                    .lineLimit(2)
                    .frame(height: 30, alignment: .topLeading)
                    .padding(.top, 5)
                HStack {
                    Text("Change action")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(KnockTheme.TypeStyle.caption)
                .foregroundStyle(KnockTheme.onGradientSecondary)
                .padding(.top, 16)
            }
            .foregroundStyle(KnockTheme.onGradient)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: KnockTheme.gradient(for: pattern),
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: KnockTheme.Layout.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: KnockTheme.Layout.cardRadius).strokeBorder(KnockTheme.strongBorder))
            .shadow(color: KnockTheme.shadow, radius: 12, y: 6)
        }
        .buttonStyle(KnockButtonStyle(radius: KnockTheme.Layout.cardRadius, lifts: true))
        .knockFocus(radius: KnockTheme.Layout.cardRadius, action: edit)
        .keyboardShortcut(KeyEquivalent(Character(String(pattern.rawValue))), modifiers: [.command, .option])
        .accessibilityLabel("\(pattern.title): \(action.title)")
        .accessibilityHint("Change the assigned action")
        .help("Change \(pattern.shortTitle.lowercased()) knock action (⌥⌘\(pattern.rawValue))")
    }
}

struct TestPanel: View {
    @EnvironmentObject private var engine: KnockEngine

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                heading
                Spacer(minLength: 16)
                controls
            }
            VStack(alignment: .leading, spacing: 16) {
                heading
                controls
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelSurface()
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Take it for a tap").font(KnockTheme.TypeStyle.heading)
            Text(engine.lastPattern.map { "Last recognized: \($0.shortTitle) knock" }
                 ?? "Try a pattern. No tapping required.")
                .font(KnockTheme.TypeStyle.caption)
                .foregroundStyle(KnockTheme.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            ForEach(KnockPattern.allCases) { pattern in
                Button { engine.simulate(knocks: pattern.rawValue) } label: {
                    Label(pattern.shortTitle, systemImage: "hand.tap")
                        .font(KnockTheme.TypeStyle.control)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(KnockTheme.raised, in: RoundedRectangle(cornerRadius: KnockTheme.Layout.controlRadius))
                }
                .buttonStyle(KnockButtonStyle())
                .knockFocus { engine.simulate(knocks: pattern.rawValue) }
                .keyboardShortcut(KeyEquivalent(Character(String(pattern.rawValue))), modifiers: [.command, .control])
                .accessibilityLabel("Test \(pattern.shortTitle.lowercased()) knock")
                .help("Test \(pattern.shortTitle.lowercased()) knock (⌃⌘\(pattern.rawValue))")
            }
        }
        .fixedSize()
    }
}
