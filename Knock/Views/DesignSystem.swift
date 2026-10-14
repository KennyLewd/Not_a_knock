import SwiftUI

/// Shared visual tokens for the intentionally dark control panel.
enum KnockTheme {
    static let canvas = Color(red: 0.045, green: 0.049, blue: 0.063)
    static let sidebar = Color(red: 0.035, green: 0.038, blue: 0.049)
    static let surface = Color(red: 0.074, green: 0.079, blue: 0.096)
    static let raised = Color(red: 0.105, green: 0.112, blue: 0.135)
    static let selected = Color(red: 0.15, green: 0.165, blue: 0.21)
    static let primary = Color.white.opacity(0.96)
    static let secondary = Color(red: 0.69, green: 0.72, blue: 0.78)
    static let muted = Color(red: 0.54, green: 0.58, blue: 0.66)
    static let border = Color.white.opacity(0.09)
    static let strongBorder = Color.white.opacity(0.20)
    static let hover = Color.white.opacity(0.055)
    static let pressed = Color.black.opacity(0.13)
    static let iconSurface = Color.white.opacity(0.15)
    static let onGradient = Color.white
    static let onGradientSecondary = Color.white.opacity(0.85)
    static let shadow = Color.black.opacity(0.24)
    static let scrim = Color.black.opacity(0.25)
    static let ring = Color.white.opacity(0.4)
    static let focus = Color(red: 0.53, green: 0.69, blue: 1)
    static let success = Color(red: 0.35, green: 0.88, blue: 0.63)
    static let warning = Color.orange

    static func gradient(for pattern: KnockPattern) -> [Color] {
        switch pattern {
        case .single:
            [Color(red: 0.13, green: 0.33, blue: 0.85), Color(red: 0.29, green: 0.22, blue: 0.70)]
        case .double:
            [Color(red: 0.75, green: 0.25, blue: 0.12), Color(red: 0.60, green: 0.20, blue: 0.09)]
        case .triple:
            [Color(red: 0.49, green: 0.22, blue: 0.76), Color(red: 0.66, green: 0.18, blue: 0.48)]
        }
    }

    enum Layout {
        static let minimum = CGSize(width: 900, height: 620)
        static let standard = CGSize(width: 1020, height: 700)
        static let sidebar: CGFloat = 190
        static let page: CGFloat = 28
        static let gap: CGFloat = 16
        static let cardRadius: CGFloat = 18
        static let controlRadius: CGFloat = 10
    }

    enum TypeStyle {
        static let title = Font.system(size: 29, weight: .bold, design: .rounded)
        static let heading = Font.system(size: 16, weight: .semibold)
        static let body = Font.system(size: 13)
        static let control = Font.system(size: 12, weight: .medium)
        static let caption = Font.system(size: 11)
        static let eyebrow = Font.system(size: 10, weight: .semibold)
    }
}

struct PanelSurface: ViewModifier {
    var radius: CGFloat = KnockTheme.Layout.cardRadius

    func body(content: Content) -> some View {
        content
            .background(KnockTheme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(KnockTheme.border))
    }
}

/// Native button focus, with a visible ring independent of the selected state.
struct KnockFocus: ViewModifier {
    var radius: CGFloat
    var action: () -> Void
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(.space) { action(); return .handled }
            .onKeyPress(.return) { action(); return .handled }
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(isFocused ? KnockTheme.focus : .clear, lineWidth: 2)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func panelSurface(radius: CGFloat = KnockTheme.Layout.cardRadius) -> some View {
        modifier(PanelSurface(radius: radius))
    }

    func knockFocus(radius: CGFloat = KnockTheme.Layout.controlRadius, action: @escaping () -> Void) -> some View {
        modifier(KnockFocus(radius: radius, action: action))
    }
}

struct KnockButtonStyle: ButtonStyle {
    var radius: CGFloat = KnockTheme.Layout.controlRadius
    var lifts = false

    func makeBody(configuration: Configuration) -> some View {
        InteractiveLabel(configuration: configuration, radius: radius, lifts: lifts)
    }

    private struct InteractiveLabel: View {
        let configuration: ButtonStyle.Configuration
        let radius: CGFloat
        let lifts: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .contentShape(RoundedRectangle(cornerRadius: radius))
                .overlay {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(configuration.isPressed ? KnockTheme.pressed : (isHovered ? KnockTheme.hover : .clear))
                        .allowsHitTesting(false)
                }
                .scaleEffect(lifts && configuration.isPressed && !reduceMotion ? 0.985 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

struct PageHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(eyebrow.uppercased())
                .font(KnockTheme.TypeStyle.eyebrow)
                .tracking(1.8)
                .foregroundStyle(KnockTheme.muted)
            Text(title)
                .font(KnockTheme.TypeStyle.title)
                .foregroundStyle(KnockTheme.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(KnockTheme.TypeStyle.body)
                .foregroundStyle(KnockTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
