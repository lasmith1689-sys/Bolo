import XCTest
@testable import BoloKit

final class SessionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var content: Content!

    override func setUpWithError() throws {
        content = try Content.bundled()
    }

    func testFirstSessionTeachesFivePhrasesThenQuizzesEach() {
        var rng = SplitMix64(seed: 1)
        let plan = SessionBuilder.build(content: content, state: LearnerState(), now: now, canListen: true, rng: &rng)
        XCTAssertEqual(plan.newPhrases.map(\.id), ["a1", "a2", "a3", "a4", "a5"])
        XCTAssertEqual(plan.items.count, 10)
        XCTAssertEqual(plan.items.map(\.mode), Array(repeating: [ExerciseMode.teach, .recognise], count: 5).flatMap { $0 })
        XCTAssertEqual(plan.items.map(\.phrase.id), ["a1", "a1", "a2", "a2", "a3", "a3", "a4", "a4", "a5", "a5"])
    }

    func testNewPhrasesComeInUnitOrder() {
        var state = LearnerState()
        for phrase in content.phrases(inUnit: 1) { state.progress[phrase.id] = CardProgress(box: 4, seen: 4, due: now.addingTimeInterval(9e6)) }
        state.progress["b1"] = CardProgress(box: 4, seen: 4, due: now.addingTimeInterval(9e6))
        var rng = SplitMix64(seed: 2)
        let plan = SessionBuilder.build(content: content, state: state, now: now, canListen: true, rng: &rng)
        XCTAssertEqual(plan.newPhrases.map(\.id), ["b2", "b3", "b4", "b5", "b6"])
    }

    func testReviewsAreCappedAtFourteenGradedCards() {
        var state = LearnerState()
        for phrase in content.phrases { state.progress[phrase.id] = CardProgress(box: 1, seen: 1, due: now) }
        var rng = SplitMix64(seed: 3)
        let plan = SessionBuilder.build(content: content, state: state, now: now, canListen: true, rng: &rng)
        XCTAssertEqual(plan.items.count, 14)
        XCTAssertTrue(plan.newPhrases.isEmpty)
        XCTAssertEqual(Set(plan.items.map(\.phrase.id)).count, 14, "no phrase twice")
        XCTAssertTrue(plan.items.allSatisfy { $0.mode == .recognise }, "box 1 cards are recognition only")
    }

    func testNewAndDueTogetherStillMakeFourteenGradedCards() {
        var state = LearnerState()
        for phrase in content.phrases.prefix(30) { state.progress[phrase.id] = CardProgress(box: 2, seen: 2, due: now) }
        var rng = SplitMix64(seed: 4)
        let plan = SessionBuilder.build(content: content, state: state, now: now, canListen: true, rng: &rng)
        XCTAssertEqual(plan.newPhrases.count, 5)
        XCTAssertEqual(plan.items.count, 19)
        XCTAssertEqual(plan.items.filter { $0.mode.isGraded }.count, 14)
        XCTAssertEqual(Array(plan.items.prefix(10)).filter { $0.mode == .teach }.count, 5)
    }

    func testSessionSizeMatchesTheBuiltSession() {
        var rng = SplitMix64(seed: 9)
        var states: [LearnerState] = [LearnerState()]
        var some = LearnerState()
        for phrase in content.phrases.prefix(12) { some.progress[phrase.id] = CardProgress(box: 1, seen: 1, due: now) }
        states.append(some)
        var all = LearnerState()
        for phrase in content.phrases { all.progress[phrase.id] = CardProgress(box: 2, seen: 2, due: now) }
        states.append(all)
        var none = all
        for id in none.progress.keys { none.progress[id]?.due = now.addingTimeInterval(9e6) }
        states.append(none)
        for state in states {
            let plan = SessionBuilder.build(content: content, state: state, now: now, canListen: true, rng: &rng)
            XCTAssertEqual(state.sessionSize(in: content, now: now), plan.items.count)
        }
    }

    func testReviewModeRules() {
        func mode(_ box: Int, words: Int, listen: Bool = true, rolls: [Double]) -> ExerciseMode {
            var queue = rolls
            return SessionBuilder.reviewMode(box: box, wordCount: words, canListen: listen) { queue.removeFirst() }
        }
        XCTAssertEqual(mode(1, words: 4, rolls: []), .recognise)
        XCTAssertEqual(mode(2, words: 1, rolls: []), .recall)
        XCTAssertEqual(mode(2, words: 3, rolls: [0.5]), .assemble)
        XCTAssertEqual(mode(2, words: 3, rolls: [0.6]), .recall)
        XCTAssertEqual(mode(3, words: 1, rolls: [0.2]), .listen)
        XCTAssertEqual(mode(3, words: 4, rolls: [0.9, 0.1]), .assemble)
        XCTAssertEqual(mode(4, words: 1, rolls: [0.9]), .recall)
        XCTAssertEqual(mode(4, words: 1, listen: false, rolls: []), .recall, "no listening without audio")
    }

    func testRunsPrintGoldAtThreeAndDoubleInkAtFive() {
        var state = LearnerState()
        let items = content.phrases.prefix(7).enumerated().map { SessionItem(id: $0.offset, phrase: $0.element, mode: .recognise) }
        var run = SessionRun(items: items, newPhrases: [])
        var xp: [Int] = []
        for _ in 0..<6 {
            xp.append(run.answer(correct: true, state: &state, now: now)!.xp)
            run.advance()
        }
        XCTAssertEqual(xp, [10, 10, 15, 15, 25, 25])
        XCTAssertEqual(run.marks, [.stamped, .stamped, .gold, .gold, .doubleInk, .doubleInk])
        XCTAssertEqual(SessionRun.runLabel(3), "3 in a row · gold")
        XCTAssertEqual(SessionRun.runLabel(5), "5 in a row · double ink")
        XCTAssertNil(SessionRun.runLabel(2))
        XCTAssertEqual(state.xp, 100)

        let miss = run.answer(correct: false, state: &state, now: now)!
        XCTAssertEqual(miss, AnswerResult(correct: false, mark: .miss, run: 0, xp: 0))
        XCTAssertEqual(run.longestRun, 6)
        XCTAssertFalse(run.isClean)
        XCTAssertEqual(run.accuracyPercent, 86)
    }

    func testMissIsRequeuedAsRecognitionAtTheEnd() {
        var state = LearnerState()
        let phrases = Array(content.phrases.prefix(3))
        let items = [SessionItem(id: 0, phrase: phrases[0], mode: .teach),
                     SessionItem(id: 1, phrase: phrases[0], mode: .recall),
                     SessionItem(id: 2, phrase: phrases[1], mode: .recognise)]
        var run = SessionRun(items: items, newPhrases: [phrases[0]])
        XCTAssertNil(run.answer(correct: true, state: &state, now: now), "teach cards aren't graded")
        XCTAssertEqual(run.gradedCount, 2)
        run.advance()
        run.answer(correct: false, state: &state, now: now)
        XCTAssertEqual(run.items.count, 4)
        XCTAssertEqual(run.items.last?.phrase, phrases[0])
        XCTAssertEqual(run.items.last?.mode, .recognise)
        XCTAssertEqual(Set(run.items.map(\.id)).count, 4, "item ids stay unique")
        XCTAssertEqual(run.gradedCount, 3)
        XCTAssertEqual(state.progress[phrases[0].id]?.box, 0)
        run.advance()
        run.answer(correct: true, state: &state, now: now)
        run.advance()
        run.answer(correct: true, state: &state, now: now)
        run.advance()
        XCTAssertTrue(run.isFinished)
        XCTAssertEqual(run.missedPhrases(in: content).map(\.id), [phrases[0].id])
        XCTAssertEqual(run.hits, 2)
        XCTAssertEqual(run.marks, [.miss, .stamped, .stamped])
    }

    func testCleanPanel() {
        var state = LearnerState()
        var run = SessionRun(items: [SessionItem(id: 0, phrase: content.phrases[0], mode: .recognise)], newPhrases: [])
        XCTAssertFalse(run.isClean, "an empty cloth isn't a clean panel")
        run.answer(correct: true, state: &state, now: now)
        XCTAssertTrue(run.isClean)
        XCTAssertEqual(run.accuracyPercent, 100)
    }

    func testOptionsAreFourDistinctAndIncludeTheAnswer() {
        var rng = SplitMix64(seed: 5)
        for phrase in content.phrases {
            for mode in [ExerciseMode.recognise, .recall, .listen] {
                let options = OptionPicker.options(for: phrase, mode: mode, in: content, rng: &rng)
                XCTAssertEqual(options.count, 4)
                XCTAssertEqual(Set(options.map(\.id)).count, 4)
                XCTAssertTrue(options.contains(phrase))
                XCTAssertEqual(Set(options.map(mode == .recall ? \.gu : \.en)).count, 4, "no two options read the same")
                if content.phrases(inUnit: phrase.unit).count >= 4 {
                    XCTAssertTrue(options.allSatisfy { $0.unit == phrase.unit }, "distractors come from the same unit")
                }
            }
        }
    }

    func testAssembleChipsHideTheOrderButKeepProperNouns() throws {
        var rng = SplitMix64(seed: 6)
        let name = try XCTUnwrap(content.phrase(id: "b1"))
        let challenge = AssembleChallenge.make(for: name, in: content, rng: &rng)
        XCTAssertEqual(challenge.answer, ["tamaaru", "naam", "shu", "chhe"])
        XCTAssertEqual(challenge.bank.sorted(), challenge.answer.sorted())
        XCTAssertNotEqual(challenge.bank, challenge.answer)
        XCTAssertTrue(challenge.isCorrect(["Tamaaru", "naam", "shu", "chhe"]))
        XCTAssertFalse(challenge.isCorrect(["naam", "tamaaru", "shu", "chhe"]))

        let gujarati = try XCTUnwrap(content.phrase(id: "c4"))
        let c4 = AssembleChallenge.make(for: gujarati, in: content, rng: &rng)
        XCTAssertEqual(c4.answer, ["mane", "Gujarati", "thodu", "aavde", "chhe"])
    }

    func testSeededSessionsAreReproducible() {
        var state = LearnerState()
        for phrase in content.phrases { state.progress[phrase.id] = CardProgress(box: 3, seen: 5, due: now) }
        var a = SplitMix64(seed: 42), b = SplitMix64(seed: 42)
        let first = SessionBuilder.build(content: content, state: state, now: now, canListen: true, rng: &a)
        let second = SessionBuilder.build(content: content, state: state, now: now, canListen: true, rng: &b)
        XCTAssertEqual(first.items, second.items)
        XCTAssertTrue(first.items.contains { $0.mode == .listen })
    }
}
