import BoloKit
import SwiftUI

/// The octagonal printing-block frame every illustration sits in (drawn on a 100 x 100 grid).
struct Octagon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        let o = CGPoint(x: rect.midX - 50 * s, y: rect.midY - 50 * s)
        let points: [(CGFloat, CGFloat)] = [(32, 3), (68, 3), (97, 32), (97, 68), (68, 97), (32, 97), (3, 68), (3, 32)]
        var path = Path()
        for (i, p) in points.enumerated() {
            let pt = CGPoint(x: o.x + p.0 * s, y: o.y + p.1 * s)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

/// A phrase's illustration: one of the 38 block-print motifs, or its Gujarati numeral.
struct MotifView: View {
    let art: String?
    let numeral: String?
    var size: CGFloat = 62

    init(phrase: Phrase, size: CGFloat = 62) {
        art = phrase.art
        numeral = phrase.numeral
        self.size = size
    }

    var body: some View {
        ZStack {
            Octagon().stroke(Palette.rule, lineWidth: max(1, 1.6 * size / 100))
            if let art {
                Image("Motif/\(art)")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else if let numeral {
                Text(numeral)
                    .font(.system(size: size * (numeral.count > 1 ? 0.42 : 0.52), weight: .semibold))
                    .foregroundStyle(Palette.cream)
                    .minimumScaleFactor(0.5)
                    .offset(y: size * 0.02)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One of the two people in a conversation.
struct AvatarView: View {
    let speaker: Int
    var size: CGFloat = 40

    var body: some View {
        let tint = speaker == 0 ? Palette.madder : Palette.gold
        ZStack {
            Octagon().fill(tint.opacity(speaker == 0 ? 0.18 : 0.15))
            Octagon().stroke(tint, lineWidth: max(1, 2 * size / 100))
            Image("Motif/avatar\(speaker == 0 ? 0 : 1)").resizable().scaledToFit()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The border band: a repeating diamond-and-dot block print. Real Ajrakh cloth always frames its field.
struct BandView: View {
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 36
            let count = Int(ceil(size.width / tile)) + 1
            let x0 = (size.width - CGFloat(count) * tile) / 2
            let cy = size.height / 2
            for i in 0..<count {
                let ox = x0 + CGFloat(i) * tile
                var outer = Path()
                outer.move(to: CGPoint(x: ox + 18, y: cy - 5.5))
                outer.addLine(to: CGPoint(x: ox + 24, y: cy))
                outer.addLine(to: CGPoint(x: ox + 18, y: cy + 5.5))
                outer.addLine(to: CGPoint(x: ox + 12, y: cy))
                outer.closeSubpath()
                ctx.fill(outer, with: .color(Palette.madder))
                var inner = Path()
                inner.move(to: CGPoint(x: ox + 18, y: cy - 2.3))
                inner.addLine(to: CGPoint(x: ox + 20.4, y: cy))
                inner.addLine(to: CGPoint(x: ox + 18, y: cy + 2.3))
                inner.addLine(to: CGPoint(x: ox + 15.6, y: cy))
                inner.closeSubpath()
                ctx.fill(inner, with: .color(Palette.gold))
                for dx in [4.0, 32.0] {
                    ctx.fill(Path(ellipseIn: CGRect(x: ox + dx - 1.7, y: cy - 1.7, width: 3.4, height: 3.4)),
                             with: .color(Palette.gold))
                }
            }
        }
        .frame(height: 15)
        .accessibilityHidden(true)
    }
}

/// The faint block-print ground behind every screen.
struct ClothBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 56
            let stroke = GraphicsContext.Shading.color(Palette.cream.opacity(0.05))
            let dot = GraphicsContext.Shading.color(Palette.cream.opacity(0.045))
            var y: CGFloat = 0
            while y < size.height + tile {
                var x: CGFloat = 0
                while x < size.width + tile {
                    let square = CGRect(x: x + 14, y: y + 14, width: 28, height: 28)
                    ctx.stroke(Path(square), with: stroke, lineWidth: 1)
                    var diamond = Path()
                    let c = CGPoint(x: x + 28, y: y + 28), r: CGFloat = 14 * 1.4142
                    diamond.move(to: CGPoint(x: c.x, y: c.y - r))
                    diamond.addLine(to: CGPoint(x: c.x + r, y: c.y))
                    diamond.addLine(to: CGPoint(x: c.x, y: c.y + r))
                    diamond.addLine(to: CGPoint(x: c.x - r, y: c.y))
                    diamond.closeSubpath()
                    ctx.stroke(diamond, with: stroke, lineWidth: 1)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.2, y: c.y - 2.2, width: 4.4, height: 4.4)), with: dot)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.8, y: y - 1.8, width: 3.6, height: 3.6)), with: dot)
                    x += tile
                }
                y += tile
            }
        }
        .background(Palette.night)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The retracting shirorekha: a gold rule above the target that withdraws on reveal. Gujarati is
/// the script that dropped Devanagari's horizontal top bar, and the animation states that.
struct Shirorekha: View {
    let retracted: Bool

    var body: some View {
        GeometryReader { geo in
            let full = min(200, geo.size.width * 0.54)
            Rectangle()
                .fill(Palette.gold)
                .frame(width: retracted ? 0 : full, height: 2)
                .opacity(retracted ? 0 : 1)
                .frame(maxWidth: .infinity)
                .animation(.timingCurve(0.5, 0, 0.1, 1, duration: 0.55), value: retracted)
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

/// Square-in-rotated-square outline used on the unit blocks.
struct BlockMotif: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let inset = rect.width * 0.25
        let square = rect.insetBy(dx: inset, dy: inset)
        p.addRect(square)
        let c = CGPoint(x: rect.midX, y: rect.midY), r = square.width / 2 * 1.4142
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addLine(to: CGPoint(x: c.x + r, y: c.y))
        p.addLine(to: CGPoint(x: c.x, y: c.y + r))
        p.addLine(to: CGPoint(x: c.x - r, y: c.y))
        p.closeSubpath()
        return p
    }
}

/// Diagonal hatching for a missed block: the gap stays visible for the rest of the session.
struct Hatch: Shape {
    var spacing: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return p
    }
}

/// A panel of printed cloth: the field framed top and bottom by the border band.
struct ClothPanel<Field: View>: View {
    var highlighted = false
    @ViewBuilder var content: () -> Field

    var body: some View {
        VStack(spacing: 0) {
            BandView()
            content()
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            BandView()
        }
        .background(Palette.indigo.opacity(0.5))
        .overlay(Rectangle().strokeBorder(highlighted ? Palette.gold : Palette.rule, lineWidth: 1))
    }
}
