import BoloKit
import SwiftUI

/// A phrase taught as a short exchange between two people, with the target line outlined in madder.
/// Every Gujarati word shows its romanization underneath; tap it to see its English meaning above.
struct ConversationView: View {
    @Environment(AppModel.self) private var app
    let sceneID: String
    let targetLine: Int?
    @State private var openWord: WordID?

    init(sceneID: String, targetLine: Int?, initialOpenWord: WordID? = nil) {
        self.sceneID = sceneID
        self.targetLine = targetLine
        _openWord = State(initialValue: initialOpenWord)
    }

    struct WordID: Hashable {
        let line: Int
        let token: Int
    }

    var body: some View {
        let lines = app.content.scenes[sceneID] ?? []
        VStack(spacing: 16) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                TurnView(line: line, lineIndex: index, isTarget: index == targetLine, openWord: $openWord)
                    .zIndex(openWord?.line == index ? 1 : 0)
            }
            Text("Tap any word for its meaning")
                .font(Typeface.hind(12.5, relativeTo: .caption))
                .italic()
                .foregroundStyle(Palette.dim)
                .padding(.top, 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { openWord = nil }
    }
}

private struct TurnView: View {
    @Environment(AppModel.self) private var app
    let line: SceneLine
    let lineIndex: Int
    let isTarget: Bool
    @Binding var openWord: ConversationView.WordID?

    var body: some View {
        let leading = line.speaker == 0
        HStack(alignment: .top, spacing: 10) {
            if leading { AvatarView(speaker: line.speaker) }
            VStack(alignment: leading ? .leading : .trailing, spacing: 5) {
                bubble(leading: leading)
                Text(line.en)
                    .font(Typeface.hind(14.5, relativeTo: .subheadline))
                    .italic()
                    .foregroundStyle(Palette.dim)
                    .multilineTextAlignment(leading ? .leading : .trailing)
            }
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
            if !leading { AvatarView(speaker: line.speaker) }
        }
    }

    private func bubble(leading: Bool) -> some View {
        let request = app.content.audioRequest(for: line)
        let playing = app.audio.playingKey == request.key
        let tokens = app.content.romanizedTokens(of: line.gu)
        return VStack(alignment: leading ? .leading : .trailing, spacing: 8) {
            FlowLayout(spacing: 7, lineSpacing: 8, alignment: leading ? .leading : .trailing) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { index, item in
                    WordButton(token: item.token, roman: item.roman,
                               gloss: app.content.gloss(for: item.token.word),
                               isOpen: openWord == .init(line: lineIndex, token: index)) {
                        let id = ConversationView.WordID(line: lineIndex, token: index)
                        withAnimation(.easeOut(duration: 0.15)) { openWord = openWord == id ? nil : id }
                    }
                }
            }
            if app.audio.canPlay {
                Button {
                    if playing { app.audio.stop() } else { app.audio.play(request) }
                } label: {
                    Label(playing ? "Playing" : "Play", systemImage: playing ? "speaker.wave.2.fill" : "play.fill")
                        .labelStyle(PlayLabelStyle())
                        .symbolEffect(.variableColor.iterative, isActive: playing)
                }
                .buttonStyle(OutlineButtonStyle(active: playing))
                .accessibilityLabel("Play \(line.en)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isTarget ? Palette.madder.opacity(0.16) : Palette.indigo.opacity(leading ? 0.75 : 0.5),
                    in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(isTarget ? Palette.madder : Palette.rule, lineWidth: 1))
        .background(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Palette.madder.opacity(isTarget ? 0.35 : 0), lineWidth: 1)
                .padding(-2)
        )
    }
}

private struct PlayLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 10, weight: .bold))
            configuration.title
        }
    }
}

/// One Gujarati word: the script, its romanization underneath, and (when tapped) its meaning above.
private struct WordButton: View {
    let token: Token
    let roman: String
    let gloss: String?
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(token.raw)
                    .font(Typeface.gujarati(22, relativeTo: .title3))
                    .foregroundStyle(isOpen ? Palette.gold : Palette.cream)
                Text(roman + token.trailing)
                    .font(Typeface.roman(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.gold.opacity(0.9))
            }
            .padding(.horizontal, 1)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isOpen ? Palette.gold : Palette.rule.opacity(0.8))
                    .frame(height: 1)
                    .offset(y: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if isOpen, let gloss {
                GlossChip(text: gloss)
                    .alignmentGuide(.top) { $0[.bottom] + 6 }
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
            }
        }
        .accessibilityLabel("\(token.word), \(roman)")
        .accessibilityHint(gloss.map { "Means \($0)" } ?? "")
    }
}

private struct GlossChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typeface.hind(12.5, .semibold, relativeTo: .caption))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Palette.gold, in: RoundedRectangle(cornerRadius: 2))
            .overlay(alignment: .bottom) {
                Triangle().fill(Palette.gold).frame(width: 8, height: 4).offset(y: 4)
            }
            .allowsHitTesting(false)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
