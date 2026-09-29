import Foundation

public enum ExerciseMode: String, Codable, Sendable, CaseIterable {
    /// A new phrase, taught as a two-person conversation. Not graded.
    case teach
    /// See the Gujarati (and romanization), pick the English.
    case recognise
    /// See the English, pick the Gujarati.
    case recall
    /// Hear it, pick the English.
    case listen
    /// See the English, tap the romanized words into order.
    case assemble

    public var isGraded: Bool { self != .teach }
}

public struct SessionItem: Identifiable, Sendable, Equatable {
    public let id: Int
    public let phrase: Phrase
    public let mode: ExerciseMode

    public init(id: Int, phrase: Phrase, mode: ExerciseMode) {
        self.id = id
        self.phrase = phrase
        self.mode = mode
    }
}

/// Builds a session the way the prototype does: up to five new phrases, each taught and then
/// immediately quizzed, then the due reviews in random order. At most 14 graded cards to start with.
public enum SessionBuilder {
    public static let newPerSession = 5
    public static let gradedCap = 14

    public static func build<R: RandomNumberGenerator>(
        content: Content, state: LearnerState, now: Date, canListen: Bool, rng: inout R
    ) -> (items: [SessionItem], newPhrases: [Phrase]) {
        let due = state.due(in: content, now: now).shuffled(using: &rng)
        // Stable sort by unit, so new phrases arrive in deck order within a unit.
        let fresh = state.unseen(in: content).enumerated()
            .sorted { $0.element.unit == $1.element.unit ? $0.offset < $1.offset : $0.element.unit < $1.element.unit }
            .prefix(newPerSession).map(\.element)

        var queue: [(Phrase, ExerciseMode)] = []
        for phrase in fresh {
            queue.append((phrase, .teach))
            queue.append((phrase, .recognise))
        }
        for phrase in due {
            let box = state.progress[phrase.id]?.box ?? 0
            let mode = reviewMode(box: box, wordCount: phrase.romanWordCount, canListen: canListen) {
                Double.random(in: 0..<1, using: &rng)
            }
            queue.append((phrase, mode))
        }
        let items = queue.prefix(gradedCap + fresh.count).enumerated().map { index, entry in
            SessionItem(id: index, phrase: entry.0, mode: entry.1)
        }
        return (items, fresh)
    }

    /// Harder exercises as a card climbs the boxes: listening from box 3 (30%), word order for
    /// phrases of three or more words from box 2 (55%), otherwise recall from box 2.
    public static func reviewMode(box: Int, wordCount: Int, canListen: Bool, roll: () -> Double) -> ExerciseMode {
        if box >= 3 && canListen && roll() < 0.3 { return .listen }
        if box >= 2 && wordCount >= 3 && roll() < 0.55 { return .assemble }
        if box >= 2 { return .recall }
        return .recognise
    }
}

/// How a graded card prints on the cloth strip.
public enum Mark: String, Sendable, Equatable, Codable {
    case stamped
    /// Three or more right in a row.
    case gold
    /// Five or more right in a row.
    case doubleInk
    case miss

    public var isHit: Bool { self != .miss }
}

public struct AnswerResult: Sendable, Equatable {
    public let correct: Bool
    public let mark: Mark
    public let run: Int
    public let xp: Int
}

/// The printing run: a session in progress. Right answers stamp blocks and build a run
/// (10 XP, 15 from three in a row, 25 from five in a row); a miss resets the run, leaves a gap,
/// and puts the phrase back at the end of the session.
public struct SessionRun: Sendable {
    public private(set) var items: [SessionItem]
    public private(set) var index = 0
    public private(set) var marks: [Mark] = []
    /// Phrase id for each mark, in order.
    public private(set) var markedPhraseIDs: [String] = []
    public private(set) var hits = 0
    public private(set) var run = 0
    public private(set) var longestRun = 0
    public private(set) var xpEarned = 0
    public let newPhrases: [Phrase]

    public init(items: [SessionItem], newPhrases: [Phrase]) {
        self.items = items
        self.newPhrases = newPhrases
    }

    public var current: SessionItem? { items.indices.contains(index) ? items[index] : nil }
    public var isFinished: Bool { index >= items.count }
    /// Blocks on the cloth: one per graded card, including re-queued misses.
    public var gradedCount: Int { items.filter { $0.mode.isGraded }.count }
    public var answeredCount: Int { marks.count }
    public var isClean: Bool { !marks.isEmpty && !marks.contains(.miss) }
    public var accuracyPercent: Int {
        marks.isEmpty ? 0 : Int((Double(hits) / Double(marks.count) * 100).rounded())
    }

    public static func xp(forRun run: Int) -> Int { run >= 5 ? 25 : run >= 3 ? 15 : 10 }

    public static func runLabel(_ run: Int) -> String? {
        run >= 5 ? "\(run) in a row · double ink" : run >= 3 ? "\(run) in a row · gold" : nil
    }

    /// Grades the current card and updates the learner's boxes and XP.
    @discardableResult
    public mutating func answer(correct: Bool, state: inout LearnerState, now: Date) -> AnswerResult? {
        guard let item = current, item.mode.isGraded else { return nil }
        let mark: Mark
        var xp = 0
        if correct {
            hits += 1
            run += 1
            longestRun = max(longestRun, run)
            xp = Self.xp(forRun: run)
            mark = run >= 5 ? .doubleInk : run >= 3 ? .gold : .stamped
        } else {
            run = 0
            mark = .miss
            items.append(SessionItem(id: (items.map(\.id).max() ?? 0) + 1, phrase: item.phrase, mode: .recognise))
        }
        xpEarned += xp
        marks.append(mark)
        markedPhraseIDs.append(item.phrase.id)
        state.record(item.phrase, correct: correct, xp: xp, now: now)
        return AnswerResult(correct: correct, mark: mark, run: run, xp: xp)
    }

    public mutating func advance() {
        if index < items.count { index += 1 }
    }

    /// Phrases missed at least once this session, in the order they were missed.
    public func missedPhrases(in content: Content) -> [Phrase] {
        var seen = Set<String>()
        var result: [Phrase] = []
        for (mark, id) in zip(marks, markedPhraseIDs) where mark == .miss && seen.insert(id).inserted {
            if let phrase = content.phrase(id: id) { result.append(phrase) }
        }
        return result
    }
}

/// Multiple-choice options: the answer plus three others, preferably from the same unit.
public enum OptionPicker {
    public static func options<R: RandomNumberGenerator>(
        for phrase: Phrase, mode: ExerciseMode, in content: Content, rng: inout R
    ) -> [Phrase] {
        func label(_ p: Phrase) -> String { mode == .recall ? p.gu : p.en }
        let answerLabel = label(phrase)
        var pool = content.phrases(inUnit: phrase.unit)
            .filter { $0.id != phrase.id && label($0) != answerLabel }
            .shuffled(using: &rng)
        pool = Array(pool.prefix(3))
        var others = content.phrases
            .filter { candidate in
                candidate.id != phrase.id && label(candidate) != answerLabel && !pool.contains { $0.id == candidate.id }
            }
            .shuffled(using: &rng)
        while pool.count < 3, !others.isEmpty {
            pool.append(others.removeFirst())
        }
        return ([phrase] + pool).shuffled(using: &rng)
    }
}

/// "Build the phrase": the romanized words of a phrase, shuffled into a word bank.
public struct AssembleChallenge: Sendable, Equatable {
    public let answer: [String]
    public let bank: [String]

    public func isCorrect(_ placed: [String]) -> Bool {
        placed.map { $0.lowercased() } == answer.map { $0.lowercased() }
    }

    /// Chips drop punctuation and the sentence capital (so neither gives the order away), but keep
    /// proper nouns such as Gujarati and Meera capitalised.
    public static func make<R: RandomNumberGenerator>(for phrase: Phrase, in content: Content, rng: inout R) -> AssembleChallenge {
        let properNouns = Set(content.roman.values.filter { $0.first?.isUppercase == true })
        let answer = Words.tokens(in: phrase.ro).map { token -> String in
            properNouns.contains(token.word) ? token.word : token.word.lowercased()
        }
        var bank = answer.shuffled(using: &rng)
        var attempts = 0
        while bank == answer && Set(answer).count > 1 && attempts < 10 {
            bank.shuffle(using: &rng)
            attempts += 1
        }
        return AssembleChallenge(answer: answer, bank: bank)
    }
}

/// A small, fast, seedable random number generator for reproducible sessions in tests and demos.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
