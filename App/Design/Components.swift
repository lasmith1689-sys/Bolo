import SwiftUI

/// The madder print button: flat, square-cornered, set in Eczar capitals.
struct PrintButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.eczar(17, .semibold, relativeTo: .headline))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(Palette.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Palette.madder, in: RoundedRectangle(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.cream.opacity(0.22), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.3)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.hind(14, .semibold))
            .foregroundStyle(Palette.dim)
            .frame(maxWidth: .infinity)
            .padding(11)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// The small outlined "Play" control.
struct OutlineButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.eczar(12.5, .semibold, relativeTo: .caption))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(active ? Palette.gold : Palette.cream)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(active ? Palette.gold : Palette.rule, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// "Bolo." with the full stop in madder.
struct Wordmark: View {
    var body: some View {
        (Text("Bolo").foregroundStyle(Palette.cream) + Text(".").foregroundStyle(Palette.madder))
            .font(Typeface.eczar(22, .semibold, relativeTo: .title3))
            .accessibilityLabel("Bolo")
    }
}

/// A stat in the top bar: a small tracked label and a gold number.
struct StatView: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label.uppercased())
                .font(Typeface.hind(11.5, .semibold, relativeTo: .caption))
                .tracking(1.1)
                .foregroundStyle(Palette.dim)
            Text(value)
                .font(Typeface.eczar(16, .semibold, relativeTo: .callout))
                .monospacedDigit()
                .foregroundStyle(Palette.gold)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }
}

/// Wraps its children into centred (or leading/trailing) rows, like CSS flex-wrap.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    var alignment: HorizontalAlignment = .center

    struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(for: maxWidth, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: bounds.width, subviews: subviews) {
            var x: CGFloat
            switch alignment {
            case .leading: x = bounds.minX
            case .trailing: x = bounds.maxX - row.width
            default: x = bounds.minX + (bounds.width - row.width) / 2
            }
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height)),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }
}

/// A round Liquid Glass icon button for the top bar.
struct GlassIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.cream)
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}
