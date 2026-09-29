import Foundation

/// Everything Bolo teaches: 56 phrases in 7 units, the two-speaker conversation scenes they are taught
/// in, and the per-word dictionaries used for tap-to-gloss and romanization. Loaded from content.json.
public struct Content: Codable, Sendable {
    public let version: Int
    public let units: [LearningUnit]
    public let speakers: [Speaker]
    public let phrases: [Phrase]
    public let scenes: [String: [SceneLine]]
    /// Gujarati word (punctuation stripped) to a short English meaning.
    public let gloss: [String: String]
    /// Gujarati word (punctuation stripped) to its romanization, lower case except proper nouns.
    public let roman: [String: String]

    public init(version: Int, units: [LearningUnit], speakers: [Speaker], phrases: [Phrase],
                scenes: [String: [SceneLine]], gloss: [String: String], roman: [String: String]) {
        self.version = version
        self.units = units
        self.speakers = speakers
        self.phrases = phrases
        self.scenes = scenes
        self.gloss = gloss
        self.roman = roman
    }

    public static func load(from data: Data) throws -> Content {
        try JSONDecoder().decode(Content.self, from: data)
    }

    /// The content that ships inside the package.
    public static func bundled() throws -> Content {
        guard let url = Bundle.module.url(forResource: "content", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try load(from: Data(contentsOf: url))
    }

    public func phrase(id: String) -> Phrase? { phrases.first { $0.id == id } }
    public func unit(id: Int) -> LearningUnit? { units.first { $0.id == id } }
    public func phrases(inUnit unit: Int) -> [Phrase] { phrases.filter { $0.unit == unit } }
    public func scene(for phrase: Phrase) -> [SceneLine] { scenes[phrase.scene] ?? [] }

    public func targetLine(for phrase: Phrase) -> SceneLine? {
        let lines = scene(for: phrase)
        return lines.indices.contains(phrase.line) ? lines[phrase.line] : nil
    }
}

public struct LearningUnit: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
}

public struct Speaker: Codable, Sendable, Hashable {
    public let name: String
    /// "male" or "female": picks the recorded voice for this speaker's lines.
    public let voice: String
}

public struct Phrase: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let unit: Int
    public let gu: String
    public let ro: String
    public let en: String
    /// Scene the phrase is taught in, and the index of the line that carries it.
    public let scene: String
    public let line: Int
    /// Illustration key (see `Motifs.all`), or nil when the phrase shows a Gujarati numeral instead.
    public let art: String?
    public let numeral: String?

    public init(id: String, unit: Int, gu: String, ro: String, en: String, scene: String, line: Int,
                art: String?, numeral: String?) {
        self.id = id
        self.unit = unit
        self.gu = gu
        self.ro = ro
        self.en = en
        self.scene = scene
        self.line = line
        self.art = art
        self.numeral = numeral
    }

    public var romanWordCount: Int { ro.split(whereSeparator: \.isWhitespace).count }
}

public struct SceneLine: Codable, Sendable, Hashable {
    /// 0 or 1: which of the two people says this line.
    public let speaker: Int
    public let gu: String
    public let en: String

    public init(speaker: Int, gu: String, en: String) {
        self.speaker = speaker
        self.gu = gu
        self.en = en
    }
}

/// The 38 hand-drawn block-print motifs. The app ships one vector image per key ("Motif/<key>").
public enum Motifs {
    public static let all: [String] = [
        "again", "ask", "coins", "compass", "cup", "drop", "ear", "elderF", "elderM", "empty", "female",
        "flower", "go", "home", "hungry", "like", "lotus", "male", "moon", "namaste", "name", "no",
        "other", "pair", "palm", "pot", "self", "sit", "slow", "sun", "thali", "thanks", "time", "toran",
        "want", "wave", "where", "yes",
    ]
}
