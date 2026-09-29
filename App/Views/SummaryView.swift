import BoloKit
import SwiftUI

/// The finished cloth. A session with no gaps is a clean panel, framed in gold.
struct SummaryView: View {
    @Environment(AppModel.self) private var app
    let summary: SessionSummary
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Wordmark()
                Spacer(minLength: 8)
                StatView(label: "Streak", value: "\(summary.streak)")
                StatView(label: "XP", value: "\(summary.xpTotal)")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(minHeight: 46)

            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Text("\(summary.accuracy)%")
                            .font(Typeface.eczar(58, .semibold, relativeTo: .largeTitle))
                            .foregroundStyle(Palette.gold)
                        Text(summary.headline)
                            .font(Typeface.eczar(24, relativeTo: .title2))
                            .foregroundStyle(Palette.cream)
                        Text("\(summary.hits) of \(summary.asked) right · longest run \(summary.longestRun) · +\(summary.xpEarned) XP")
                            .font(Typeface.hind(15, relativeTo: .subheadline))
                            .foregroundStyle(Palette.dim)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 28)

                    VStack(spacing: 10) {
                        BandView()
                        ClothStrip(marks: summary.marks, total: summary.marks.count)
                            .padding(.horizontal, 10)
                        BandView()
                    }
                    .padding(.vertical, 12)
                    .background(Palette.indigo.opacity(0.4))
                    .overlay(Rectangle().strokeBorder(summary.isClean ? Palette.gold : Palette.rule, lineWidth: summary.isClean ? 1.5 : 1))
                    .padding(.top, 20)

                    if !summary.recap.isEmpty {
                        TrackedLabel(text: summary.recapIsMissed ? "Worth another look" : "New today", size: 11.5, color: Palette.madder)
                            .padding(.top, 24)
                            .padding(.bottom, 6)
                        VStack(spacing: 0) {
                            ForEach(summary.recap) { phrase in
                                RecapRow(phrase: phrase)
                            }
                        }
                    }

                    Text("Come back tomorrow to keep the streak.")
                        .font(Typeface.hind(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.dim)
                        .padding(.top, 18)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 0) {
                Button("Another round") { app.anotherRound() }
                    .buttonStyle(PrintButtonStyle())
                    .accessibilityIdentifier("again")
                Button("Done for today") { app.goHome() }
                    .buttonStyle(QuietButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
        .onAppear { appeared = true }
        .sensoryFeedback(.success, trigger: appeared) { _, shown in shown && summary.isClean }
    }
}

private struct RecapRow: View {
    @Environment(AppModel.self) private var app
    let phrase: Phrase

    var body: some View {
        let request = app.content.audioRequest(for: phrase)
        Button {
            app.audio.play(request)
        } label: {
            HStack(spacing: 11) {
                MotifView(phrase: phrase, size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(phrase.gu)
                        .font(Typeface.gujarati(16.5, relativeTo: .body))
                        .foregroundStyle(Palette.cream)
                    Text(phrase.ro)
                        .font(Typeface.roman(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.gold)
                }
                Spacer(minLength: 8)
                Text(phrase.en)
                    .font(Typeface.hind(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.dim)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 9)
            .overlay(alignment: .top) { Rectangle().fill(Palette.rule.opacity(0.4)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Plays the phrase")
    }
}
