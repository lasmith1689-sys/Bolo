import BoloKit
import SwiftUI

/// A printing run: the cloth strip of blocks above the current card.
struct SessionView: View {
    @Bindable var session: SessionModel
    @State private var confirmingExit = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Wordmark()
                Spacer(minLength: 8)
                StatView(label: "Card", value: "\(session.cardNumber)")
                StatView(label: "of", value: "\(session.cardCount)")
                GlassIconButton(systemName: "xmark", label: "End session") {
                    if session.run.answeredCount > 0 { confirmingExit = true } else { session.endEarly() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            ClothStrip(marks: session.run.marks, total: session.run.gradedCount, live: true)
                .padding(.horizontal, 20)
                .padding(.top, 10)

            Text(session.runLabel?.uppercased() ?? " ")
                .font(Typeface.eczar(11.5, .semibold, relativeTo: .caption))
                .tracking(2.3)
                .foregroundStyle(Palette.gold)
                .frame(height: 18)
                .padding(.top, 2)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: session.runLabel)
                .accessibilityHidden(session.runLabel == nil)

            if let item = session.item {
                card(for: item)
                    .id(item.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.9), trigger: session.stamps)
        .sensoryFeedback(.warning, trigger: session.misses)
        .confirmationDialog("End this printing run?", isPresented: $confirmingExit, titleVisibility: .visible) {
            Button("End and see the cloth") { session.endEarly() }
            Button("Keep printing", role: .cancel) {}
        } message: {
            Text("Answers so far are already saved.")
        }
    }

    @ViewBuilder
    private func card(for item: SessionItem) -> some View {
        switch item.mode {
        case .teach: TeachCard(session: session, phrase: item.phrase)
        case .recognise, .recall, .listen: ChoiceCard(session: session, item: item)
        case .assemble: AssembleCard(session: session, phrase: item.phrase)
        }
    }
}

/// The cloth: one block per graded card. Right answers stamp madder (gold from three in a row,
/// double ink from five), misses leave a hatched gap.
struct ClothStrip: View {
    let marks: [Mark]
    let total: Int
    var live = false

    var body: some View {
        FlowLayout(spacing: 5, lineSpacing: 5) {
            ForEach(0..<max(total, marks.count), id: \.self) { index in
                ClothBlock(mark: index < marks.count ? marks[index] : nil,
                           pressing: live && index == marks.count - 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(marks.filter(\.isHit).count) blocks printed, \(marks.filter { !$0.isHit }.count) gaps, of \(total)")
    }
}

struct ClothBlock: View {
    let mark: Mark?
    var pressing = false
    var size: CGFloat = 16

    private struct Press {
        var scale: CGFloat = 1
        var opacity: Double = 1
    }

    var body: some View {
        ZStack {
            switch mark {
            case nil:
                Rectangle().fill(Color.black.opacity(0.2))
                Rectangle().strokeBorder(Palette.rule, lineWidth: 1)
            case .stamped?:
                Rectangle().fill(Palette.madder)
                diamond.stroke(Palette.cream.opacity(0.55), lineWidth: 1)
            case .gold?:
                Rectangle().fill(Palette.gold)
            case .doubleInk?:
                Rectangle().fill(Palette.gold)
                diamond.fill(Palette.madder)
                diamond.stroke(Palette.cream.opacity(0.6), lineWidth: 0.8)
            case .miss?:
                Hatch(spacing: 4).stroke(Palette.madderLo.opacity(0.75), lineWidth: 1.5).clipped()
                Rectangle().strokeBorder(Palette.madderLo, lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
        // The press: the block lands big and faint, overshoots, and settles, like a block on cloth.
        .keyframeAnimator(initialValue: Press(), trigger: mark) { content, value in
            content.scaleEffect(value.scale).opacity(value.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                LinearKeyframe(1.9, duration: 0.001)
                CubicKeyframe(0.9, duration: 0.19)
                CubicKeyframe(1.0, duration: 0.15)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(0.15, duration: 0.001)
                LinearKeyframe(1.0, duration: 0.19)
            }
        }
    }

    private var diamond: some Shape {
        Rectangle().inset(by: 2.5).rotation(.degrees(45))
    }
}
