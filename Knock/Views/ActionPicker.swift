import SwiftUI

struct ActionPicker: View {
    let pattern: KnockPattern
    let selected: KnockAction
    let onSelect: (KnockAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case search, action(KnockAction), cancel
    }

    private var results: [KnockAction] {
        ActionCategory.allCases.flatMap { $0.actions(matching: query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeading(eyebrow: "Choose an action", title: pattern.title,
                        subtitle: "Choose what happens with \(pattern.subtitle.lowercased()).")
                .padding(.bottom, 20)
            searchField
                .padding(.bottom, 16)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(ActionCategory.allCases) { category in
                            let actions = category.actions(matching: query)
                            if !actions.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(category.rawValue)
                                        .font(KnockTheme.TypeStyle.caption)
                                        .foregroundStyle(KnockTheme.secondary)
                                        .padding(.leading, 10)
                                        .accessibilityAddTraits(.isHeader)
                                    ForEach(actions) { action in
                                        actionRow(action)
                                            .id(action)
                                    }
                                }
                            }
                        }
                        if results.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 25))
                                    .accessibilityHidden(true)
                                Text("No matching actions")
                                    .font(KnockTheme.TypeStyle.heading)
                                Text("Try an action name or a category, like Media.")
                                    .font(KnockTheme.TypeStyle.body)
                            }
                            .foregroundStyle(KnockTheme.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 56)
                        }
                    }
                    .padding(4)
                }
                .onChange(of: focus) { _, newFocus in
                    if case let .action(action) = newFocus {
                        proxy.scrollTo(action, anchor: .center)
                    }
                }
                .onChange(of: query) { _, _ in
                    if let first = results.first { proxy.scrollTo(first, anchor: .top) }
                }
            }

            HStack {
                Text("Choose to save · ↑↓ to browse")
                    .font(KnockTheme.TypeStyle.caption)
                    .foregroundStyle(KnockTheme.muted)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .focusable()
                    .focused($focus, equals: .cancel)
                    .onKeyPress(.return) { dismiss(); return .handled }
                    .onKeyPress(.space) { dismiss(); return .handled }
                    .accessibilityHint("Close without changing the assigned action")
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 560, height: 560)
        .foregroundStyle(KnockTheme.primary)
        .background(KnockTheme.canvas)
        .onAppear { focus = .search }
        .onExitCommand { dismiss() }
        .onKeyPress(.downArrow) { moveFocus(by: 1); return .handled }
        .onKeyPress(.upArrow) { moveFocus(by: -1); return .handled }
        .background {
            Button("Search actions") { focus = .search }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(KnockTheme.secondary)
                .accessibilityHidden(true)
            TextField("Search actions", text: $query)
                .textFieldStyle(.plain)
                .font(KnockTheme.TypeStyle.body)
                .focused($focus, equals: .search)
                .accessibilityLabel("Search actions")
                .accessibilityHint("Filter by action name, description, or category. Press Down Arrow to browse results.")
                .onSubmit {
                    if let first = results.first { choose(first) }
                }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .panelSurface(radius: KnockTheme.Layout.controlRadius)
        .overlay {
            RoundedRectangle(cornerRadius: KnockTheme.Layout.controlRadius)
                .strokeBorder(focus == .search ? KnockTheme.focus : .clear, lineWidth: 2)
        }
    }

    private func actionRow(_ action: KnockAction) -> some View {
        Button { choose(action) } label: {
            HStack(spacing: 12) {
                Image(systemName: action.symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(KnockTheme.focus)
                    .frame(width: 34, height: 34)
                    .background(KnockTheme.raised, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title).font(KnockTheme.TypeStyle.control)
                    Text(action.subtitle)
                        .font(KnockTheme.TypeStyle.caption)
                        .foregroundStyle(KnockTheme.secondary)
                }
                Spacer()
                if action == selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(KnockTheme.focus)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(action == selected ? KnockTheme.selected : KnockTheme.surface,
                        in: RoundedRectangle(cornerRadius: KnockTheme.Layout.controlRadius))
        }
        .buttonStyle(KnockButtonStyle())
        .focusable()
        .focused($focus, equals: .action(action))
        .focusEffectDisabled()
        .onKeyPress(.return) { choose(action); return .handled }
        .onKeyPress(.space) { choose(action); return .handled }
        .overlay {
            RoundedRectangle(cornerRadius: KnockTheme.Layout.controlRadius)
                .strokeBorder(focus == .action(action) ? KnockTheme.focus : .clear, lineWidth: 2)
                .padding(-3)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(action.title)
        .accessibilityValue(action == selected ? "Currently assigned" : "")
        .accessibilityHint("\(action.subtitle). Assign to \(pattern.title).")
        .accessibilityAddTraits(action == selected ? .isSelected : [])
    }

    private func moveFocus(by offset: Int) {
        let visible = results
        guard !visible.isEmpty else { return }
        if case let .action(action) = focus, let index = visible.firstIndex(of: action) {
            let next = index + offset
            focus = next < 0 ? .search : .action(visible[min(next, visible.count - 1)])
        } else {
            focus = .action(offset > 0 ? visible[0] : visible[visible.count - 1])
        }
    }

    private func choose(_ action: KnockAction) {
        onSelect(action)
        dismiss()
    }
}
