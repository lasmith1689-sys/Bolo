import BoloKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Wordmark()
                Spacer(minLength: 8)
                StatView(label: "Streak", value: "\(app.streak)")
                StatView(label: "Best", value: "\(app.state.bestRun)")
                StatView(label: "XP", value: "\(app.state.xp)")
                GlassIconButton(systemName: "slider.horizontal.3", label: "Settings") { app.showingSettings = true }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 0) {
                    hero
                    BandView().padding(.horizontal, -20)
                    TrackedLabel(text: "The Blocks", size: 11.5, color: Palette.madder)
                        .padding(.top, 18)
                        .padding(.bottom, 8)
                    VStack(spacing: 0) {
                        ForEach(Array(app.content.units.enumerated()), id: \.element.id) { index, unit in
                            UnitRow(unit: unit, stat: app.unitStat(unit))
                            if index < app.content.units.count - 1 {
                                Rectangle().fill(Palette.rule.opacity(0.4)).frame(height: 1)
                            }
                        }
                    }
                    hint
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            Button(beginTitle) { app.startSession() }
                .buttonStyle(PrintButtonStyle())
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .accessibilityIdentifier("begin")
        }
    }

    private var beginTitle: String {
        let cards = app.sessionSize
        return cards > 0 ? "Begin · \(cards) card\(cards == 1 ? "" : "s")" : "Practise anyway"
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Text("બોલો")
                .font(Typeface.gujarati(46, relativeTo: .largeTitle))
                .foregroundStyle(Palette.cream)
                .accessibilityLabel("Bolo, speak")
            headline
                .font(Typeface.eczar(24, relativeTo: .title2))
                .foregroundStyle(Palette.cream)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Text(subline)
                .font(Typeface.hind(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.dim)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 22)
        .padding(.bottom, 20)
    }

    private var headline: Text {
        let due = app.dueCount
        if due > 0 {
            return Text("\(Text("\(due)").foregroundStyle(Palette.gold).font(Typeface.eczar(24, .semibold, relativeTo: .title2))) to bring back today")
        }
        return Text("Everyday Gujarati,\n\(Text("five minutes").foregroundStyle(Palette.gold).font(Typeface.eczar(24, .semibold, relativeTo: .title2))) a day")
    }

    private var subline: String {
        if app.startedCount == 0 { return "Learn it the way it is actually spoken" }
        let cloths = app.state.finishedUnits(in: app.content)
        return "\(app.startedCount) of \(app.content.phrases.count) phrases · \(cloths)/\(app.content.units.count) cloths finished"
    }

    private var hint: some View {
        hintText
            .font(Typeface.hind(13, relativeTo: .footnote))
            .foregroundStyle(Palette.dim)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .padding(.top, 16)
            .padding(.horizontal, 4)
    }

    private var hintText: Text {
        func gold(_ s: String) -> Text { Text(s).foregroundStyle(Palette.gold).font(Typeface.hind(13, .semibold, relativeTo: .footnote)) }
        switch app.audio.effectiveSource {
        case .recorded?:
            return Text("Every line has a \(gold("recorded voice")). Tap any word in a conversation to see what it means.")
        case .system?:
            return Text("Lines are read by the \(gold("iPhone's Gujarati voice")). Tap any word in a conversation to see what it means.")
        case nil:
            return Text("No Gujarati voice on this iPhone yet. \(gold("Settings › Accessibility › Read & Speak › Voices")) adds one.")
        }
    }
}

/// A unit as a printing block that fills with madder from the bottom as its phrases get strong.
struct UnitRow: View {
    let unit: LearningUnit
    let stat: UnitStat
    @State private var shown: Double = 0

    var body: some View {
        HStack(spacing: 15) {
            ZStack(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.18))
                Rectangle()
                    .fill(Palette.madder.opacity(0.62))
                    .frame(height: 36 * shown)
                BlockMotif().stroke(Palette.cream.opacity(0.45), lineWidth: 1)
            }
            .frame(width: 36, height: 36)
            .clipped()
            .overlay(Rectangle().strokeBorder(stat.isFinished ? Palette.gold : Palette.rule, lineWidth: 1))

            Text(unit.name)
                .font(Typeface.hind(16.5, .medium))
                .foregroundStyle(Palette.cream)
            Spacer()
            Text("\(stat.strong)/\(stat.total)")
                .font(Typeface.eczar(13.5))
                .monospacedDigit()
                .foregroundStyle(Palette.dim)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(unit.name), \(stat.strong) of \(stat.total) strong")
        .onAppear {
            withAnimation(.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.6).delay(0.1)) { shown = stat.fraction }
        }
        .onChange(of: stat.fraction) { _, value in
            withAnimation(.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.6)) { shown = value }
        }
    }
}
