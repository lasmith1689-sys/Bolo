import XCTest
@testable import BoloKit

final class AudioTests: XCTestCase {
    var content: Content!

    override func setUpWithError() throws {
        content = try Content.bundled()
    }

    func testSpeakersHaveDistinctVoices() {
        XCTAssertEqual(content.voice(forSpeaker: 0), "male")
        XCTAssertEqual(content.voice(forSpeaker: 1), "female")
    }

    func testPhraseAudioReusesTheSceneLineWhenItIsTheWholeLine() throws {
        let goodbye = try XCTUnwrap(content.phrase(id: "a8"))
        XCTAssertEqual(content.audioRequest(for: goodbye), AudioRequest(text: "આવજો.", voice: "male"))
        let well = try XCTUnwrap(content.phrase(id: "a2"))
        XCTAssertEqual(content.audioRequest(for: well), AudioRequest(text: "મજામાં", voice: "female"))
    }

    func testEveryLineAndPhraseHasExactlyOneClip() {
        let requests = content.allAudioRequests
        XCTAssertEqual(Set(requests).count, requests.count)
        XCTAssertEqual(requests.count, 95)
        for lines in content.scenes.values {
            for line in lines { XCTAssertTrue(requests.contains(content.audioRequest(for: line))) }
        }
        for phrase in content.phrases { XCTAssertTrue(requests.contains(content.audioRequest(for: phrase))) }
    }

    /// The audio workflow must have recorded every clip the app can ask for.
    func testBundledManifestCoversEveryClip() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let audio = repo.appendingPathComponent("App/Resources/Audio")
        let manifestURL = audio.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw XCTSkip("No recorded clips yet at \(manifestURL.path)")
        }
        let manifest = try JSONDecoder().decode(AudioManifest.self, from: Data(contentsOf: manifestURL))
        for request in content.allAudioRequests {
            guard let clip = manifest.clip(for: request) else {
                XCTFail("no clip for \(request.key)")
                continue
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: audio.appendingPathComponent(clip.file).path), clip.file)
            XCTAssertGreaterThan(clip.duration, 0.2, request.key)
        }
    }
}
