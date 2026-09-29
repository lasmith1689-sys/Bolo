import Foundation

/// One recording the app needs: a Gujarati line in one of the two voices.
public struct AudioRequest: Hashable, Sendable, Comparable {
    public let text: String
    /// "male" or "female".
    public let voice: String

    public init(text: String, voice: String) {
        self.text = text
        self.voice = voice
    }

    /// The key the audio workflow writes into Audio/manifest.json for this clip.
    public var key: String { "\(voice)|\(text)" }

    public static func < (a: AudioRequest, b: AudioRequest) -> Bool { a.key < b.key }
}

/// The bundled clip index written by tools/tts/synthesize.py.
public struct AudioManifest: Codable, Sendable {
    public struct Clip: Codable, Sendable {
        public let file: String
        public let duration: Double
    }
    public let model: String
    public let clips: [String: Clip]

    public init(model: String, clips: [String: Clip]) {
        self.model = model
        self.clips = clips
    }

    public func clip(for request: AudioRequest) -> Clip? { clips[request.key] }
}

extension Content {
    public func voice(forSpeaker speaker: Int) -> String {
        speakers.indices.contains(speaker) ? speakers[speaker].voice : "female"
    }

    public func audioRequest(for line: SceneLine) -> AudioRequest {
        AudioRequest(text: line.gu, voice: voice(forSpeaker: line.speaker))
    }

    /// The phrase on its own, in the voice of the person who says it in its scene. When the phrase
    /// is the whole target line (give or take punctuation) the scene's recording is reused.
    public func audioRequest(for phrase: Phrase) -> AudioRequest {
        guard let line = targetLine(for: phrase) else { return AudioRequest(text: phrase.gu, voice: "female") }
        if Words.words(in: line.gu) == Words.words(in: phrase.gu) {
            return audioRequest(for: line)
        }
        return AudioRequest(text: phrase.gu, voice: voice(forSpeaker: line.speaker))
    }

    /// Every clip the app can ask for, without duplicates, in a stable order.
    public var allAudioRequests: [AudioRequest] {
        var set = Set<AudioRequest>()
        for lines in scenes.values { for line in lines { set.insert(audioRequest(for: line)) } }
        for phrase in phrases { set.insert(audioRequest(for: phrase)) }
        return set.sorted()
    }
}
