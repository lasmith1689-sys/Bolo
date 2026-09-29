import BoloKit
import Observation
import SwiftUI

/// App-wide state: the content, the learner's saved progress, audio, and which screen is showing.
@MainActor
@Observable
final class AppModel {
    enum Screen {
        case home
        case session(SessionModel)
        case summary(SessionSummary)
    }

    let content: Content
    let audio: AudioService
    private(set) var state: LearnerState
    var screen: Screen = .home
    var showingSettings = false
    /// Screenshot runs only: a word to show with its meaning open.
    var demoOpenWord: ConversationView.WordID?

    private let store: StateStore
    @ObservationIgnored var rng = SplitMix64(seed: UInt64.random(in: 0...UInt64.max))
    /// Screenshot and demo runs never touch the real progress file.
    let isDemo: Bool

    init(content: Content, store: StateStore, audio: AudioService, isDemo: Bool = false) {
        self.content = content
        self.store = store
        self.audio = audio
        self.isDemo = isDemo
        state = store.load()
    }

    var now: Date { Date() }

    // MARK: Home

    var dueCount: Int { state.due(in: content, now: now).count }
    var unseenCount: Int { state.unseen(in: content).count }
    var readyCount: Int { state.readyCount(in: content, now: now) }
    var startedCount: Int { content.phrases.count - unseenCount }
    var streak: Int { state.currentStreak(now: now) }

    func unitStat(_ unit: LearningUnit) -> UnitStat { state.unitStat(unit.id, in: content) }

    // MARK: Sessions

    func startSession() {
        if dueCount == 0 && unseenCount == 0 {
            state.pullForward(8, in: content, now: now)
        }
        let plan = SessionBuilder.build(content: content, state: state, now: now, canListen: audio.canPlay, rng: &rng)
        guard !plan.items.isEmpty else { return }
        begin(SessionRun(items: plan.items, newPhrases: plan.newPhrases))
    }

    func begin(_ run: SessionRun) {
        withAnimation(.easeInOut(duration: 0.3)) {
            screen = .session(SessionModel(run: run, app: self))
        }
    }

    /// Grades the current card of a session and saves right away, as the prototype did.
    func record(_ correct: Bool, in run: inout SessionRun) -> AnswerResult? {
        let result = run.answer(correct: correct, state: &state, now: now)
        save()
        return result
    }

    func finish(_ run: SessionRun) {
        audio.stop()
        state.closeSession(longestRun: run.longestRun, now: now)
        save()
        let summary = SessionSummary(run: run, content: content, xpTotal: state.xp, streak: streak)
        withAnimation(.easeInOut(duration: 0.3)) { screen = .summary(summary) }
    }

    func endEarly(_ run: SessionRun) {
        if run.answeredCount > 0 {
            finish(run)
        } else {
            audio.stop()
            withAnimation(.easeInOut(duration: 0.3)) { screen = .home }
        }
    }

    func anotherRound() {
        state.pullForward(6, in: content, now: now)
        startSession()
    }

    func goHome() {
        audio.stop()
        withAnimation(.easeInOut(duration: 0.3)) { screen = .home }
    }

    func resetProgress() {
        state = LearnerState()
        try? store.reset()
        save()
    }

    private func save() {
        try? store.save(state)
    }

    /// Replaces the saved state (demo and screenshot runs only).
    func loadDemoState(_ demo: LearnerState) {
        state = demo
        save()
    }
}

/// What the summary screen shows once a printing run is finished.
struct SessionSummary {
    let marks: [Mark]
    let hits: Int
    let asked: Int
    let accuracy: Int
    let longestRun: Int
    let isClean: Bool
    let xpEarned: Int
    let xpTotal: Int
    let streak: Int
    /// Phrases missed this session, or the new phrases when nothing was missed.
    let recap: [Phrase]
    let recapIsMissed: Bool

    init(run: SessionRun, content: Content, xpTotal: Int, streak: Int) {
        marks = run.marks
        hits = run.hits
        asked = run.answeredCount
        accuracy = run.accuracyPercent
        longestRun = run.longestRun
        isClean = run.isClean
        xpEarned = run.xpEarned
        self.xpTotal = xpTotal
        self.streak = streak
        let missed = run.missedPhrases(in: content)
        recapIsMissed = !missed.isEmpty
        recap = missed.isEmpty ? run.newPhrases : missed
    }

    var headline: String {
        isClean ? "A clean panel." : accuracy >= 70 ? "Solid run." : "Repetition does the rest."
    }
}
