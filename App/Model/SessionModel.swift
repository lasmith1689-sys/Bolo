import BoloKit
import Observation
import SwiftUI

/// The card on screen during a printing run, and the answer state around it.
@MainActor
@Observable
final class SessionModel {
    private(set) var run: SessionRun
    /// Set once the current card is answered.
    private(set) var answer: AnswerResult?
    private(set) var chosenID: String?
    private(set) var options: [Phrase] = []
    private(set) var assemble: AssembleChallenge?
    /// Indices into `assemble.bank`, in the order tapped.
    private(set) var placed: [Int] = []
    var conversationRevealed = false
    /// Haptic triggers.
    private(set) var stamps = 0
    private(set) var misses = 0

    unowned let app: AppModel

    init(run: SessionRun, app: AppModel) {
        self.run = run
        self.app = app
        prepare()
    }

    var content: Content { app.content }
    var item: SessionItem? { run.current }
    var isAnswered: Bool { answer != nil }
    var cardNumber: Int { min(run.index + 1, run.items.count) }
    var cardCount: Int { run.items.count }
    var runLabel: String? { SessionRun.runLabel(run.run) }

    private func prepare() {
        answer = nil
        chosenID = nil
        placed = []
        assemble = nil
        options = []
        conversationRevealed = false
        guard let item else { return }
        switch item.mode {
        case .recognise, .recall, .listen:
            options = OptionPicker.options(for: item.phrase, mode: item.mode, in: content, rng: &app.rng)
        case .assemble:
            assemble = AssembleChallenge.make(for: item.phrase, in: content, rng: &app.rng)
        case .teach:
            break
        }
    }

    // MARK: Answering

    func choose(_ option: Phrase) {
        guard answer == nil, let item else { return }
        chosenID = option.id
        grade(option.id == item.phrase.id)
    }

    func place(_ bankIndex: Int) {
        guard answer == nil, !placed.contains(bankIndex) else { return }
        placed.append(bankIndex)
    }

    func unplace(at position: Int) {
        guard answer == nil, placed.indices.contains(position) else { return }
        placed.remove(at: position)
    }

    var placedWords: [String] { placed.compactMap { assemble?.bank[$0] } }
    var assemblyComplete: Bool { assemble.map { placed.count == $0.bank.count } ?? false }

    func checkAssembly() {
        guard answer == nil, let assemble, assemblyComplete else { return }
        grade(assemble.isCorrect(placedWords))
    }

    private func grade(_ correct: Bool) {
        answer = app.record(correct, in: &run)
        if correct { stamps += 1 } else { misses += 1 }
        playPhrase()
    }

    func next() {
        app.audio.stop()
        run.advance()
        if run.isFinished {
            app.finish(run)
        } else {
            withAnimation(.easeInOut(duration: 0.22)) { prepare() }
        }
    }

    func endEarly() { app.endEarly(run) }

    // MARK: Audio

    func playPhrase() {
        guard let item else { return }
        app.audio.play(content.audioRequest(for: item.phrase))
    }

    // MARK: Screenshots

    /// Answers the current card wrong and opens its conversation (demo and screenshot runs only).
    func debugMissAndReveal() {
        guard let item else { return }
        if item.mode == .assemble, let assemble {
            placed = Array(assemble.bank.indices.reversed())
            grade(false)
        } else if let wrong = options.first(where: { $0.id != item.phrase.id }) {
            choose(wrong)
        }
        conversationRevealed = true
    }
}
