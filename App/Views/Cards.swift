import BoloKit
import SwiftUI

/// Scrolling card body with the action button pinned underneath. Scrolls `scrollTarget` into view
/// when it appears (the conversation revealed after a miss).
struct CardScaffold<Main: View, Footer: View>: View {
    var scrollTarget: String?
    @ViewBuilder var content: () -> Main
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    content()
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .task(id: scrollTarget) {
                    guard let target = scrollTarget else { return }
                    try? await Task.sleep(for: .milliseconds(280))
                    withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(target, anchor: .top) }
                }
            }
            footer()
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
    }
}

// MARK: - Teach

/// A new phrase: its illustration and meaning, then the conversation it lives in.
struct TeachCard: View {
    @Environment(AppModel.self) private var app
    let session: SessionModel
    let phrase: Phrase

    var body: some View {
        CardScaffold {
            ClothPanel {
                VStack(spacing: 16) {
                    TrackedLabel(text: "New phrase · \(app.content.unit(id: phrase.unit)?.name ?? "")", size: 11, tracking: 0.2)
                    HStack(alignment: .center, spacing: 16) {
                        MotifView(phrase: phrase, size: 76)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(phrase.gu)
                                .font(Typeface.gujarati(30))
                                .foregroundStyle(Palette.cream)
                            Text(phrase.ro)
                                .font(Typeface.roman(18))
                                .foregroundStyle(Palette.gold)
                            Text(phrase.en)
                                .font(Typeface.hind(18, .medium))
                                .foregroundStyle(Palette.cream)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        SpeakButton(request: app.content.audioRequest(for: phrase), label: "Play \(phrase.en)")
                    }
                    Rectangle().fill(Palette.rule.opacity(0.5)).frame(height: 1)
                    TrackedLabel(text: "In conversation", size: 10.5, tracking: 0.2, color: Palette.madder)
                    ConversationView(sceneID: phrase.scene, targetLine: phrase.line, initialOpenWord: app.demoOpenWord)
                }
            }
        } footer: {
            Button("Got it") { session.next() }
                .buttonStyle(PrintButtonStyle())
                .accessibilityIdentifier("next")
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            session.playPhrase()
        }
    }
}

// MARK: - Recognise, recall, listen

struct ChoiceCard: View {
    @Environment(AppModel.self) private var app
    let session: SessionModel
    let item: SessionItem

    private var phrase: Phrase { item.phrase }

    var body: some View {
        CardScaffold(scrollTarget: session.conversationRevealed ? Verdict.conversationID : nil) {
            VStack(spacing: 0) {
                ClothPanel {
                    VStack(spacing: 0) { stem }
                }
                VStack(spacing: 7) {
                    ForEach(session.options) { option in
                        OptionRow(option: option, mode: item.mode, state: state(of: option)) {
                            session.choose(option)
                        }
                    }
                }
                .padding(.top, 16)
                Verdict(session: session, phrase: phrase, correction: "\(phrase.gu) · \(phrase.ro) · \(phrase.en)")
            }
        } footer: {
            Button("Continue") { session.next() }
                .buttonStyle(PrintButtonStyle())
                .disabled(!session.isAnswered)
                .accessibilityIdentifier("next")
        }
        .task {
            // Recognition and listening play the phrase on arrival; recall would give the answer away.
            guard item.mode != .recall else { return }
            try? await Task.sleep(for: .milliseconds(item.mode == .listen ? 300 : 260))
            if !session.isAnswered { session.playPhrase() }
        }
    }

    @ViewBuilder
    private var stem: some View {
        switch item.mode {
        case .listen:
            TrackedLabel(text: "Listen", size: 11, tracking: 0.24).padding(.bottom, 16)
            Shirorekha(retracted: session.isAnswered).padding(.bottom, 18)
            Button { session.playPhrase() } label: {
                Label("Play again", systemImage: "play.fill")
                    .font(Typeface.eczar(14, .semibold))
            }
            .buttonStyle(OutlineButtonStyle(active: app.audio.playingKey != nil))
            .accessibilityIdentifier("play")
            if session.isAnswered {
                answerReveal.padding(.top, 16)
            }
        case .recall:
            TrackedLabel(text: "Say this in Gujarati", size: 11, tracking: 0.24).padding(.bottom, 16)
            MotifView(phrase: phrase).padding(.bottom, 8)
            Shirorekha(retracted: session.isAnswered).padding(.bottom, 14)
            Text(phrase.en)
                .font(Typeface.eczar(27, relativeTo: .title))
                .foregroundStyle(Palette.cream)
                .multilineTextAlignment(.center)
        default:
            TrackedLabel(text: "What does this mean?", size: 11, tracking: 0.24).padding(.bottom, 16)
            MotifView(phrase: phrase).padding(.bottom, 8)
            Shirorekha(retracted: session.isAnswered).padding(.bottom, 14)
            answerReveal
        }
    }

    private var answerReveal: some View {
        VStack(spacing: 4) {
            Text(phrase.gu)
                .font(Typeface.gujarati(36))
                .foregroundStyle(Palette.cream)
                .multilineTextAlignment(.center)
            Text(phrase.ro)
                .font(Typeface.roman(17.5))
                .foregroundStyle(Palette.gold)
            if item.mode != .listen {
                SpeakButton(request: app.content.audioRequest(for: phrase), label: "Play \(phrase.gu)")
                    .padding(.top, 8)
            }
        }
    }

    private func state(of option: Phrase) -> OptionRow.Status {
        guard session.isAnswered else { return .open }
        if option.id == phrase.id { return .right }
        if option.id == session.chosenID { return .wrong }
        return .muted
    }
}

struct OptionRow: View {
    enum Status { case open, right, wrong, muted }

    let option: Phrase
    let mode: ExerciseMode
    let state: Status
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                if mode == .recall {
                    Text(option.gu)
                        .font(Typeface.gujarati(19, relativeTo: .body))
                        .foregroundStyle(Palette.cream)
                    Text(option.ro)
                        .font(Typeface.roman(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.gold)
                } else {
                    Text(option.en)
                        .font(Typeface.hind(16.5, .medium))
                        .foregroundStyle(Palette.cream)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .background(background, in: RoundedRectangle(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(border, lineWidth: 1))
            .overlay(alignment: .leading) { Rectangle().fill(edge).frame(width: 3) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(state != .open)
        .opacity(state == .muted ? 0.3 : 1)
        .animation(.easeOut(duration: 0.15), value: state)
        .accessibilityAddTraits(state == .right ? .isSelected : [])
    }

    private var background: Color {
        switch state {
        case .right: return Palette.green.opacity(0.2)
        case .wrong: return Palette.madderLo.opacity(0.22)
        default: return Palette.indigo.opacity(0.5)
        }
    }

    private var border: Color {
        switch state {
        case .right: return Palette.green
        case .wrong: return Palette.madderLo
        default: return Palette.rule
        }
    }

    private var edge: Color {
        switch state {
        case .right: return Palette.green
        case .wrong: return Palette.madder
        default: return Palette.rule
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// "Right · 4 in a row" or "Not quite" with the correction, and on a miss the way back into the
/// conversation, so the phrase is met again in context rather than just corrected.
struct Verdict: View {
    static let conversationID = "conversation"
    @Bindable var session: SessionModel
    let phrase: Phrase
    let correction: String

    var body: some View {
        VStack(spacing: 0) {
            if let answer = session.answer {
                VStack(spacing: 4) {
                    Text(answer.correct ? (answer.run >= 3 ? "Right · \(answer.run) in a row" : "Right") : "Not quite")
                        .font(Typeface.eczar(13.5, .semibold, relativeTo: .callout))
                        .tracking(1.35)
                        .textCase(.uppercase)
                        .foregroundStyle(answer.correct ? Palette.green : Palette.madder)
                    if !answer.correct {
                        Text(correction)
                            .font(Typeface.hind(15, .medium, relativeTo: .subheadline))
                            .foregroundStyle(Palette.dim)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                }
                .padding(.top, 16)
                .transition(.opacity)

                if !answer.correct {
                    if session.conversationRevealed {
                        ClothPanel {
                            ConversationView(sceneID: phrase.scene, targetLine: phrase.line)
                        }
                        .padding(.top, 14)
                        .id(Verdict.conversationID)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) { session.conversationRevealed = true }
                        } label: {
                            Label("See it in conversation", systemImage: "bubble.left.and.bubble.right")
                                .font(Typeface.eczar(13.5, .semibold))
                                .foregroundStyle(Palette.gold)
                                .padding(10)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                        .accessibilityIdentifier("seeConversation")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.2), value: session.isAnswered)
    }
}

// MARK: - Assemble

/// "Build the phrase": tap the romanized words into order.
struct AssembleCard: View {
    let session: SessionModel
    let phrase: Phrase

    var body: some View {
        CardScaffold(scrollTarget: session.conversationRevealed ? Verdict.conversationID : nil) {
            VStack(spacing: 0) {
                ClothPanel {
                    VStack(spacing: 0) {
                        TrackedLabel(text: "Build the phrase", size: 11, tracking: 0.24).padding(.bottom, 16)
                        MotifView(phrase: phrase).padding(.bottom, 8)
                        Shirorekha(retracted: session.isAnswered).padding(.bottom, 14)
                        Text(phrase.en)
                            .font(Typeface.eczar(27, relativeTo: .title))
                            .foregroundStyle(Palette.cream)
                            .multilineTextAlignment(.center)
                    }
                }
                slotLine.padding(.top, 14)
                bank.padding(.top, 12)
                Verdict(session: session, phrase: phrase, correction: "\(phrase.ro) · \(phrase.gu)")
            }
        } footer: {
            Button(session.isAnswered ? "Continue" : "Check") {
                if session.isAnswered { session.next() } else { session.checkAssembly() }
            }
            .buttonStyle(PrintButtonStyle())
            .disabled(!session.isAnswered && !session.assemblyComplete)
            .accessibilityIdentifier("next")
        }
    }

    private var slotLine: some View {
        let tint: Color = session.answer.map { $0.correct ? Palette.green : Palette.madder } ?? Palette.gold
        return ZStack {
            if session.placed.isEmpty {
                Text("Tap the words in order")
                    .font(Typeface.hind(14))
                    .italic()
                    .foregroundStyle(Palette.dim)
            }
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array(session.placedWords.enumerated()), id: \.offset) { position, word in
                    Chip(word: word, tint: tint, placed: true) { session.unplace(at: position) }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .padding(9)
        .overlay(Rectangle().strokeBorder(Palette.rule, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: session.placed)
    }

    private var bank: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array((session.assemble?.bank ?? []).enumerated()), id: \.offset) { index, word in
                Chip(word: word, tint: nil, placed: false) { session.place(index) }
                    .opacity(session.placed.contains(index) ? 0.22 : 1)
                    .allowsHitTesting(!session.placed.contains(index) && !session.isAnswered)
            }
        }
        .frame(minHeight: 40)
    }
}

private struct Chip: View {
    let word: String
    let tint: Color?
    let placed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(word)
                .font(Typeface.roman(16))
                .foregroundStyle(tint ?? Palette.cream)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Palette.indigo.opacity(0.75), in: RoundedRectangle(cornerRadius: 2))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(tint ?? Palette.rule, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}
