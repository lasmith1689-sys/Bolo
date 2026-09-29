import Foundation

/// One whitespace-separated token of a Gujarati line, split into the word itself and the
/// punctuation around it. Glossing is per word and global, so "છે" reads "is" everywhere.
public struct Token: Hashable, Sendable {
    public let raw: String
    public let leading: String
    public let word: String
    public let trailing: String

    static let punctuation: Set<Character> = ["?", "!", ".", ","]

    init(_ raw: String) {
        self.raw = raw
        let lead = raw.prefix { Token.punctuation.contains($0) }
        let rest = raw.dropFirst(lead.count)
        let trail = rest.reversed().prefix { Token.punctuation.contains($0) }
        leading = String(lead)
        trailing = String(trail.reversed())
        word = String(rest.dropLast(trail.count))
    }

    /// True when a sentence ends after this token, so the next word starts with a capital.
    var endsSentence: Bool { trailing.contains { $0 == "." || $0 == "?" || $0 == "!" } }
}

public enum Words {
    public static func tokens(in text: String) -> [Token] {
        text.split(whereSeparator: \.isWhitespace).map { Token(String($0)) }.filter { !$0.word.isEmpty }
    }

    /// The words of a line with punctuation stripped, in order.
    public static func words(in text: String) -> [String] { tokens(in: text).map(\.word) }

    /// Whether `phrase` occurs in `line`: as a contiguous run of words, or, for a one-word phrase,
    /// as the stem of an inflected word (ઘર inside ઘરે).
    public static func line(_ line: String, contains phrase: String) -> Bool {
        let p = words(in: phrase), l = words(in: line)
        guard !p.isEmpty, p.count <= l.count else { return false }
        for start in 0...(l.count - p.count) where Array(l[start..<start + p.count]) == p {
            return true
        }
        if p.count == 1 {
            return l.contains { $0.hasPrefix(p[0]) }
        }
        return false
    }
}

extension Content {
    public func gloss(for word: String) -> String? { gloss[word] }

    /// Romanization of any Gujarati line, built word by word from the `roman` dictionary with the
    /// line's own punctuation and sentence case. A line that is exactly one of the phrases uses that
    /// phrase's romanization, so a scene never disagrees with the card ("Kem cho?", not "Kem chho?").
    public func romanization(of text: String) -> String {
        let tokens = Words.tokens(in: text)
        guard !tokens.isEmpty else { return "" }
        let lineWords = tokens.map(\.word)
        if let phrase = phrases.first(where: { Words.words(in: $0.gu) == lineWords }) {
            var ro = phrase.ro
            while let last = ro.last, Token.punctuation.contains(last) { ro.removeLast() }
            return Self.capitalizedFirst(ro + tokens[tokens.count - 1].trailing)
        }
        return composedRomanization(of: text)
    }

    /// Word-by-word romanization from the dictionary alone, with punctuation and sentence case.
    func composedRomanization(of text: String) -> String {
        dictionaryTokens(of: text)
            .map { $0.token.leading + $0.roman + $0.token.trailing }
            .joined(separator: " ")
    }

    /// Romanization of each token of a line, for showing under the Gujarati word by word. Uses the
    /// phrase's own spelling when the line is a phrase with one romanized word per Gujarati word.
    public func romanizedTokens(of text: String) -> [(token: Token, roman: String)] {
        let tokens = Words.tokens(in: text)
        let lineWords = tokens.map(\.word)
        if let phrase = phrases.first(where: { Words.words(in: $0.gu) == lineWords }) {
            let roWords = Words.words(in: phrase.ro)
            if roWords.count == tokens.count {
                return zip(tokens, roWords).map { (token: $0, roman: $1) }
            }
        }
        return dictionaryTokens(of: text)
    }

    func dictionaryTokens(of text: String) -> [(token: Token, roman: String)] {
        let tokens = Words.tokens(in: text)
        var capitalizeNext = true
        return tokens.map { token in
            var word = roman[token.word] ?? token.word
            if capitalizeNext { word = Self.capitalizedFirst(word) }
            capitalizeNext = token.endsSentence
            return (token: token, roman: word)
        }
    }

    static func capitalizedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    /// Every distinct Gujarati word in the scenes and phrases.
    public var allWords: Set<String> {
        var set = Set<String>()
        for lines in scenes.values { for line in lines { set.formUnion(Words.words(in: line.gu)) } }
        for phrase in phrases { set.formUnion(Words.words(in: phrase.gu)) }
        return set
    }

    /// Content problems that would show up as a broken card; empty when the content is sound.
    public func validationIssues() -> [String] {
        var issues: [String] = []
        let unitIDs = Set(units.map(\.id))
        var seenIDs = Set<String>()
        for phrase in phrases {
            if !seenIDs.insert(phrase.id).inserted { issues.append("\(phrase.id): duplicate id") }
            if !unitIDs.contains(phrase.unit) { issues.append("\(phrase.id): unknown unit \(phrase.unit)") }
            if (phrase.art == nil) == (phrase.numeral == nil) {
                issues.append("\(phrase.id): needs exactly one of art or numeral")
            }
            if let art = phrase.art, !Motifs.all.contains(art) { issues.append("\(phrase.id): unknown art \(art)") }
            guard let line = targetLine(for: phrase) else {
                issues.append("\(phrase.id): scene \(phrase.scene) has no line \(phrase.line)")
                continue
            }
            if !Words.line(line.gu, contains: phrase.gu) {
                issues.append("\(phrase.id): target line \"\(line.gu)\" does not contain \"\(phrase.gu)\"")
            }
        }
        for (id, lines) in scenes {
            if lines.isEmpty { issues.append("\(id): empty scene") }
            for line in lines where !speakers.indices.contains(line.speaker) {
                issues.append("\(id): unknown speaker \(line.speaker)")
            }
        }
        for word in allWords.sorted() {
            if gloss[word] == nil { issues.append("no gloss for \(word)") }
            if roman[word] == nil { issues.append("no romanization for \(word)") }
        }
        return issues
    }
}
