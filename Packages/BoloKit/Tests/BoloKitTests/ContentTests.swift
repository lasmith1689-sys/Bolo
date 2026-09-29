import XCTest
@testable import BoloKit

final class ContentTests: XCTestCase {
    var content: Content!

    override func setUpWithError() throws {
        content = try Content.bundled()
    }

    func testBundledContentShape() {
        XCTAssertEqual(content.phrases.count, 56)
        XCTAssertEqual(content.units.map(\.id), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(content.units.first?.name, "First words")
        XCTAssertEqual(content.scenes.count, 26)
        XCTAssertEqual(content.speakers.map(\.voice), ["male", "female"])
        for unit in content.units {
            XCTAssertFalse(content.phrases(inUnit: unit.id).isEmpty, "unit \(unit.id) has no phrases")
        }
    }

    func testContentHasNoValidationIssues() {
        XCTAssertEqual(content.validationIssues(), [])
    }

    func testEveryPhraseIsTaughtInItsTargetLine() throws {
        for phrase in content.phrases {
            let line = try XCTUnwrap(content.targetLine(for: phrase), phrase.id)
            XCTAssertTrue(Words.line(line.gu, contains: phrase.gu), "\(phrase.id) not in \(line.gu)")
        }
    }

    func testEveryWordHasAGlossAndARomanization() {
        for word in content.allWords {
            XCTAssertNotNil(content.gloss(for: word), "no gloss for \(word)")
            XCTAssertNotNil(content.roman[word], "no romanization for \(word)")
        }
        XCTAssertEqual(content.gloss(for: "છે"), "is")
        XCTAssertEqual(content.gloss(for: "કેમ"), "how")
    }

    func testTokensStripPunctuation() {
        let tokens = Words.tokens(in: "મજામાં, આભાર. તમે?")
        XCTAssertEqual(tokens.map(\.word), ["મજામાં", "આભાર", "તમે"])
        XCTAssertEqual(tokens.map(\.trailing), [",", ".", "?"])
        XCTAssertEqual(Words.words(in: "  હા!  "), ["હા"])
    }

    func testLineContainsHandlesRunsAndInflection() {
        XCTAssertTrue(Words.line("મમ્મી પપ્પા ઘરે છે?", contains: "ઘર"))
        XCTAssertTrue(Words.line("હા, ફરીથી કહો.", contains: "ફરીથી કહો"))
        XCTAssertFalse(Words.line("હા, ફરીથી કહો.", contains: "કહો ફરીથી"))
        XCTAssertFalse(Words.line("ના.", contains: "ના ના"))
    }

    func testRomanizationOfSceneLines() {
        XCTAssertEqual(content.romanization(of: "મજામાં, આભાર. તમે?"), "Majaa maa, aabhaar. Tame?")
        XCTAssertEqual(content.romanization(of: "મારું નામ મીરા છે. તમે?"), "Maaru naam Meera chhe. Tame?")
        XCTAssertEqual(content.romanization(of: "હું અમેરિકાથી છું."), "Hu Amerikaathi chhu.")
        // A line that is a phrase keeps the phrase's spelling and the line's punctuation.
        XCTAssertEqual(content.romanization(of: "કેમ છો?"), "Kem cho?")
        XCTAssertEqual(content.romanization(of: "આવજો."), "Aavjo.")
    }

    func testRomanizedTokensLineUpWithTheGujarati() {
        let tokens = content.romanizedTokens(of: "કેમ છો?")
        XCTAssertEqual(tokens.map(\.roman), ["Kem", "cho"])
        let scene = content.romanizedTokens(of: "હા, ફરીથી કહો.")
        XCTAssertEqual(scene.map(\.roman), ["Haa", "farithi", "kaho"])
        XCTAssertEqual(scene.map(\.token.trailing), [",", "", "."])
    }

    /// The word dictionary must spell every phrase the way its card does, so scenes and cards agree.
    func testDictionaryAgreesWithPhraseRomanization() {
        func key(_ s: String) -> String { Words.words(in: s).map { $0.lowercased() }.joined(separator: " ") }
        let exceptions: Set<String> = ["a1"] // "Kem cho?" is the familiar spelling of "Kem chho?"
        for phrase in content.phrases where !exceptions.contains(phrase.id) {
            XCTAssertEqual(key(content.composedRomanization(of: phrase.gu)), key(phrase.ro), phrase.id)
        }
    }

    func testNumbersUnitShowsGujaratiNumerals() {
        let numbers = content.phrases(inUnit: 4)
        XCTAssertEqual(numbers.count, 10)
        XCTAssertEqual(numbers.compactMap(\.numeral), ["૧", "૨", "૩", "૪", "૫", "૬", "૭", "૮", "૯", "૧૦"])
        XCTAssertTrue(numbers.allSatisfy { $0.art == nil })
    }

    func testEveryPhraseOutsideNumbersHasAKnownMotif() {
        for phrase in content.phrases where phrase.unit != 4 {
            XCTAssertTrue(Motifs.all.contains(phrase.art ?? ""), phrase.id)
        }
        XCTAssertEqual(Motifs.all.count, 38)
    }
}
