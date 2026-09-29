import Foundation

/// Saves the learner's progress as a small JSON file (Application Support on iOS).
public struct StateStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// The app's default location: Application Support/Bolo/progress-v1.json.
    public static func standard() -> StateStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return StateStore(url: base.appendingPathComponent("Bolo", isDirectory: true)
            .appendingPathComponent("progress-v\(LearnerState.schemaVersion).json"))
    }

    /// The saved state, or a fresh one when there is none or it cannot be read.
    public func load() -> LearnerState {
        guard let data = try? Data(contentsOf: url),
              let state = try? Self.makeDecoder().decode(LearnerState.self, from: data),
              state.schema == LearnerState.schemaVersion else {
            return LearnerState()
        }
        return state
    }

    public func save(_ state: LearnerState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.makeEncoder().encode(state).write(to: url, options: .atomic)
    }

    public func reset() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        return d
    }
}
