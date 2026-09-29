import XCTest
@testable import BoloKit

final class LearnerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let day = Leitner.day
    var content: Content!

    override func setUpWithError() throws {
        content = try Content.bundled()
    }

    func testIntervals() {
        XCTAssertEqual(Leitner.intervalsInDays, [0, 1, 3, 7, 21])
    }

    func testRightAnswerClimbsOneBoxAndWrongAnswerFallsToZero() {
        let first = Leitner.grade(nil, correct: true, now: now)
        XCTAssertEqual(first, CardProgress(box: 1, seen: 1, due: now.addingTimeInterval(day)))

        let second = Leitner.grade(first, correct: true, now: now)
        XCTAssertEqual(second.box, 2)
        XCTAssertEqual(second.due, now.addingTimeInterval(3 * day))

        let missed = Leitner.grade(second, correct: false, now: now)
        XCTAssertEqual(missed, CardProgress(box: 0, seen: 3, due: now))

        let firstMiss = Leitner.grade(nil, correct: false, now: now)
        XCTAssertEqual(firstMiss, CardProgress(box: 0, seen: 1, due: now))
    }

    func testTopBoxIsFourAtTwentyOneDays() {
        var p: CardProgress?
        for _ in 0..<8 { p = Leitner.grade(p, correct: true, now: now) }
        XCTAssertEqual(p?.box, 4)
        XCTAssertEqual(p?.due, now.addingTimeInterval(21 * day))
    }

    func testDueAndUnseen() {
        var state = LearnerState()
        XCTAssertEqual(state.unseen(in: content).count, 56)
        XCTAssertEqual(state.due(in: content, now: now).count, 0)
        XCTAssertEqual(state.readyCount(in: content, now: now), 5)

        state.progress["a1"] = CardProgress(box: 1, seen: 1, due: now)
        state.progress["a2"] = CardProgress(box: 1, seen: 1, due: now.addingTimeInterval(1))
        XCTAssertEqual(state.due(in: content, now: now).map(\.id), ["a1"])
        XCTAssertEqual(state.unseen(in: content).count, 54)
        XCTAssertEqual(state.readyCount(in: content, now: now), 6)
    }

    func testUnitBlockFillsWithStrongPhrases() {
        var state = LearnerState()
        XCTAssertEqual(state.unitStat(1, in: content), UnitStat(total: 8, strong: 0))
        for id in ["a1", "a2", "a3"] { state.progress[id] = CardProgress(box: 3, seen: 3, due: now) }
        state.progress["a4"] = CardProgress(box: 2, seen: 2, due: now)
        let stat = state.unitStat(1, in: content)
        XCTAssertEqual(stat.strong, 3)
        XCTAssertEqual(stat.fraction, 3.0 / 8.0, accuracy: 1e-9)
        XCTAssertFalse(stat.isFinished)
        for phrase in content.phrases(inUnit: 1) { state.progress[phrase.id] = CardProgress(box: 4, seen: 5, due: now) }
        XCTAssertTrue(state.unitStat(1, in: content).isFinished)
        XCTAssertEqual(state.finishedUnits(in: content), 1)
    }

    func testStreakCountsConsecutiveDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var state = LearnerState()
        state.closeSession(longestRun: 4, now: now, calendar: calendar)
        XCTAssertEqual(state.streak, 1)
        XCTAssertEqual(state.bestRun, 4)

        state.closeSession(longestRun: 2, now: now.addingTimeInterval(3600), calendar: calendar)
        XCTAssertEqual(state.streak, 1, "a second session on the same day doesn't add to the streak")
        XCTAssertEqual(state.bestRun, 4, "the personal best only goes up")

        state.closeSession(longestRun: 7, now: now.addingTimeInterval(day), calendar: calendar)
        XCTAssertEqual(state.streak, 2)
        XCTAssertEqual(state.bestRun, 7)
        XCTAssertEqual(state.currentStreak(now: now.addingTimeInterval(2 * day), calendar: calendar), 2)
        XCTAssertEqual(state.currentStreak(now: now.addingTimeInterval(3 * day), calendar: calendar), 0)

        state.closeSession(longestRun: 1, now: now.addingTimeInterval(4 * day), calendar: calendar)
        XCTAssertEqual(state.streak, 1, "missing a day starts the streak again")
    }

    func testRecordAddsXPAndGrades() {
        var state = LearnerState()
        let phrase = content.phrases[0]
        state.record(phrase, correct: true, xp: 15, now: now)
        XCTAssertEqual(state.xp, 15)
        XCTAssertEqual(state.progress[phrase.id]?.box, 1)
    }

    func testPullForwardMakesTheWeakestSeenPhrasesDue() {
        var state = LearnerState()
        let later = now.addingTimeInterval(10 * day)
        for (i, phrase) in content.phrases.enumerated() {
            state.progress[phrase.id] = CardProgress(box: i < 3 ? 1 : 4, seen: 3, due: later)
        }
        state.pullForward(8, in: content, now: now)
        let due = state.due(in: content, now: now)
        XCTAssertEqual(due.count, 8)
        XCTAssertEqual(Array(due.prefix(3)).map(\.id), ["a1", "a2", "a3"])
    }

    func testStoreRoundTripAndBadFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = StateStore(url: dir.appendingPathComponent("p.json"))
        XCTAssertEqual(store.load(), LearnerState())

        var state = LearnerState()
        state.record(content.phrases[3], correct: true, xp: 10, now: now)
        state.closeSession(longestRun: 3, now: now)
        try store.save(state)
        XCTAssertEqual(store.load(), state)

        try Data("not json".utf8).write(to: store.url)
        XCTAssertEqual(store.load(), LearnerState())
        try store.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }
}
