import Foundation

/// Where one phrase sits in the Leitner system.
public struct CardProgress: Codable, Sendable, Equatable {
    /// 0 to 4. A right answer moves the card up one box, a wrong one sends it back to box 0.
    public var box: Int
    public var seen: Int
    public var due: Date

    public init(box: Int, seen: Int, due: Date) {
        self.box = box
        self.seen = seen
        self.due = due
    }
}

/// Five-box Leitner spaced repetition, as in the prototype: intervals of 0, 1, 3, 7 and 21 days.
public enum Leitner {
    public static let intervalsInDays = [0, 1, 3, 7, 21]
    public static let day: TimeInterval = 86_400
    /// A phrase in this box or higher counts as "strong" and fills its unit's printing block.
    public static let strongBox = 3

    public static func grade(_ progress: CardProgress?, correct: Bool, now: Date) -> CardProgress {
        var p = progress ?? CardProgress(box: 0, seen: 0, due: now)
        p.seen += 1
        p.box = correct ? min(intervalsInDays.count - 1, p.box + 1) : 0
        p.due = now.addingTimeInterval(TimeInterval(intervalsInDays[p.box]) * day)
        return p
    }
}

public struct UnitStat: Sendable, Equatable {
    public let total: Int
    public let strong: Int
    public var fraction: Double { total == 0 ? 0 : Double(strong) / Double(total) }
    public var isFinished: Bool { total > 0 && strong == total }
}

/// Everything Bolo remembers about the learner. Saved as JSON after every answer.
public struct LearnerState: Codable, Sendable, Equatable {
    public static let schemaVersion = 1

    public var schema: Int = LearnerState.schemaVersion
    public var progress: [String: CardProgress] = [:]
    public var streak: Int = 0
    /// Start of the last day a session was finished, in the learner's calendar.
    public var lastDay: Date?
    public var xp: Int = 0
    /// Longest run of right answers ever, across sessions.
    public var bestRun: Int = 0

    public init() {}

    public func due(in content: Content, now: Date) -> [Phrase] {
        content.phrases.filter { progress[$0.id].map { $0.due <= now } ?? false }
    }

    public func unseen(in content: Content) -> [Phrase] {
        content.phrases.filter { progress[$0.id] == nil }
    }

    public func unitStat(_ unit: Int, in content: Content) -> UnitStat {
        let phrases = content.phrases(inUnit: unit)
        let strong = phrases.filter { (progress[$0.id]?.box ?? -1) >= Leitner.strongBox }.count
        return UnitStat(total: phrases.count, strong: strong)
    }

    public func finishedUnits(in content: Content) -> Int {
        content.units.filter { unitStat($0.id, in: content).isFinished }.count
    }

    /// Cards the home screen offers: everything due plus up to five new phrases.
    public func readyCount(in content: Content, now: Date) -> Int {
        due(in: content, now: now).count + min(unseen(in: content).count, SessionBuilder.newPerSession)
    }

    /// How many cards the next session will start with (teach cards included), as SessionBuilder builds it.
    public func sessionSize(in content: Content, now: Date) -> Int {
        let fresh = min(unseen(in: content).count, SessionBuilder.newPerSession)
        let dueCount = due(in: content, now: now).count
        return min(2 * fresh + dueCount, SessionBuilder.gradedCap + fresh)
    }

    /// Records one answer: moves the card between boxes and adds the XP it earned.
    public mutating func record(_ phrase: Phrase, correct: Bool, xp earned: Int, now: Date) {
        progress[phrase.id] = Leitner.grade(progress[phrase.id], correct: correct, now: now)
        xp += earned
    }

    /// Called when a session ends: keeps the daily streak and the personal-best run.
    public mutating func closeSession(longestRun: Int, now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        if lastDay != today {
            if let last = lastDay, let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
               calendar.isDate(last, inSameDayAs: yesterday) {
                streak += 1
            } else {
                streak = 1
            }
            lastDay = today
        }
        bestRun = max(bestRun, longestRun)
    }

    /// The streak as it should read today: a streak whose last day is before yesterday has lapsed.
    public func currentStreak(now: Date, calendar: Calendar = .current) -> Int {
        guard let last = lastDay else { return 0 }
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return streak }
        return last >= yesterday ? streak : 0
    }

    /// "Practise anyway" and "Another round": makes the weakest `count` seen phrases due now.
    public mutating func pullForward(_ count: Int, in content: Content, now: Date) {
        let order = content.phrases.enumerated().sorted { a, b in
            let boxA = progress[a.element.id]?.box ?? -1, boxB = progress[b.element.id]?.box ?? -1
            return boxA == boxB ? a.offset < b.offset : boxA < boxB
        }
        for (_, phrase) in order.prefix(count) {
            progress[phrase.id]?.due = now
        }
    }
}
