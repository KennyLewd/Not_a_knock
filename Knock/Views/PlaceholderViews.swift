import SwiftUI

// Activity and Settings implementation belongs to T08.
struct ActivityView: View {
    var body: some View {
        PlaceholderPage(title: "Activity", subtitle: "A little history of what happens with every tap.",
                        symbol: "waveform.path.ecg", message: "Your knocks, at a glance",
                        detail: "Activity history is coming in a later build.")
    }
}

struct SettingsView: View {
    var body: some View {
        PlaceholderPage(title: "Settings", subtitle: "Make Knock feel at home on your Mac.",
                        symbol: "slider.horizontal.3", message: "Make it yours",
                        detail: "Detection and app preferences are coming in a later build.")
    }
}

private struct PlaceholderPage: View {
    let title: String
    let subtitle: String
    let symbol: String
    let message: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PageHeading(eyebrow: "Your workspace", title: title, subtitle: subtitle)
            VStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 27, weight: .light))
                    .foregroundStyle(KnockTheme.secondary)
                    .frame(width: 64, height: 64)
                    .background(KnockTheme.raised, in: RoundedRectangle(cornerRadius: 18))
                Text(message).font(KnockTheme.TypeStyle.heading)
                Text(detail)
                    .font(KnockTheme.TypeStyle.body)
                    .foregroundStyle(KnockTheme.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity, minHeight: 260)
            .panelSurface()
            Spacer(minLength: 0)
        }
        .padding(KnockTheme.Layout.page)
        .frame(maxWidth: 1100, maxHeight: .infinity, alignment: .topLeading)
    }
}
