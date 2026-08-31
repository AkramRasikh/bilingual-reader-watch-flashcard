//
//  ImprovRecorder.swift
//  bilingual reader watch flashcard Watch App
//
//  System dictation on the watch. Dismissed on leave so the sheet cannot linger.
//

import Foundation
import WatchKit

@MainActor
final class ImprovRecorder: ObservableObject {
    enum Phase {
        case idle
        case dictating
        case ready
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript: String = ""
    @Published var errorMessage: String?

    let language: String

    init(language: String) {
        self.language = language
    }

    func start() {
        guard phase == .idle else { return }
        errorMessage = nil
        transcript = ""
        WordAudioPlayer.shared.stop()
        phase = .dictating
        presentDictation(remainingAttempts: 2)
    }

    func deleteClip() {
        transcript = ""
        errorMessage = nil
        phase = .idle
    }

    /// Dismiss dictation and reset. Safe to call repeatedly.
    func abandon() {
        Self.interfaceController()?.dismissTextInputController()
        transcript = ""
        errorMessage = nil
        phase = .idle
    }

    private func presentDictation(remainingAttempts: Int) {
        guard let controller = Self.interfaceController() else {
            if remainingAttempts > 0 {
                Task {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    presentDictation(remainingAttempts: remainingAttempts - 1)
                }
            } else {
                errorMessage = "Couldn’t open dictation"
                phase = .idle
            }
            return
        }

        controller.presentTextInputController(
            withSuggestions: nil,
            allowedInputMode: .plain
        ) { [weak self] result in
            Task { @MainActor in
                self?.handleDictation(result)
            }
        }
    }

    private func handleDictation(_ result: [Any]?) {
        let text = (result as? [String])?
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let text, !text.isEmpty else {
            phase = .idle
            return
        }

        transcript = text
        phase = .ready
    }

    private static func interfaceController() -> WKInterfaceController? {
        WKApplication.shared().visibleInterfaceController
            ?? WKApplication.shared().rootInterfaceController
    }
}
