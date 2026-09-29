import BoloKit
import Foundation

/// Canned states for the Simulator smoke test's screenshots (-BoloScreen <name>). Never used in a
/// normal launch, and never written to the real progress file.
@MainActor
enum Demo {
    static let screens = ["home", "teach", "gloss", "recognise", "recall", "listen", "assemble", "miss", "summary", "settings"]

    static func prepare(_ app: AppModel, screen: String?) {
        app.rng = SplitMix64(seed: 7)
        app.loadDemoState(learner(for: app.content, now: app.now))
        switch screen ?? "home" {
        case "teach": session(app, target: "b1", mode: .teach)
        case "gloss":
            app.demoOpenWord = ConversationView.WordID(line: 1, token: 1)
            session(app, target: "b1", mode: .teach)
        case "recognise": session(app, target: "e4", mode: .recognise)
        case "recall": session(app, target: "e1", mode: .recall)
        case "listen": session(app, target: "a1", mode: .listen)
        case "assemble": session(app, target: "c4", mode: .assemble)
        case "miss":
            session(app, target: "g6", mode: .recognise)
            if case .session(let model) = app.screen { model.debugMissAndReveal() }
        case "summary": summary(app)
        case "settings": app.showingSettings = true
        default: break
        }
    }

    /// Unit 1 printed, unit 2 half way, a few phrases from unit 3 started, some due today.
    static func learner(for content: Content, now: Date) -> LearnerState {
        var state = LearnerState()
        let later = now.addingTimeInterval(3 * Leitner.day)
        for phrase in content.phrases(inUnit: 1) {
            state.progress[phrase.id] = CardProgress(box: 4, seen: 6, due: later)
        }
        for (i, phrase) in content.phrases(inUnit: 2).enumerated() {
            state.progress[phrase.id] = CardProgress(box: i < 4 ? 3 : 1, seen: 3, due: i < 4 ? later : now.addingTimeInterval(-3600))
        }
        for phrase in content.phrases(inUnit: 3).prefix(2) {
            state.progress[phrase.id] = CardProgress(box: 1, seen: 1, due: now.addingTimeInterval(-3600))
        }
        state.xp = 1240
        state.bestRun = 9
        state.streak = 4
        state.lastDay = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: now))
        return state
    }

    /// A run a few cards in: one early miss, then four right in a row, and the target card up next.
    static func session(_ app: AppModel, target: String, mode: ExerciseMode) {
        let content = app.content
        guard let phrase = content.phrase(id: target) else { return }
        let warmup = ["b1", "b3", "c1", "c5", "b5"].compactMap(content.phrase(id:)).filter { $0.id != target }.prefix(5)
        var items = warmup.enumerated().map { SessionItem(id: $0.offset, phrase: $0.element, mode: .recognise) }
        items.append(SessionItem(id: items.count, phrase: phrase, mode: mode))
        for (i, extra) in ["g1", "g2", "e2", "f3"].compactMap(content.phrase(id:)).enumerated() {
            items.append(SessionItem(id: 100 + i, phrase: extra, mode: .recognise))
        }
        var run = SessionRun(items: items, newPhrases: mode == .teach ? [phrase] : [])
        var state = app.state
        for (i, _) in warmup.enumerated() {
            run.answer(correct: i != 0, state: &state, now: app.now)
            run.advance()
        }
        app.begin(run)
    }

    static func summary(_ app: AppModel) {
        let content = app.content
        let phrases = Array(content.phrases.prefix(12))
        var run = SessionRun(items: phrases.enumerated().map { SessionItem(id: $0.offset, phrase: $0.element, mode: .recognise) },
                             newPhrases: Array(phrases.prefix(5)))
        var state = app.state
        let answers = [true, true, true, false, true, true, true, true, true, true, false, true]
        for correct in answers {
            run.answer(correct: correct, state: &state, now: app.now)
            run.advance()
        }
        while !run.isFinished {
            run.answer(correct: true, state: &state, now: app.now)
            run.advance()
        }
        app.finish(run)
    }
}
