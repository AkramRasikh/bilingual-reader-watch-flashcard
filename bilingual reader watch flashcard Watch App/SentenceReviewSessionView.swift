//
//  SentenceReviewSessionView.swift
//  bilingual reader watch flashcard Watch App
//
//  Queues currently due sentences. Graded cards stay in the local cache with
//  their next due; they re-enter the queue when that time arrives.
//  Trash removes reviewData only.
//

import Combine
import FSRS
import SwiftUI

struct SentenceReviewSessionView: View {
    let language: String
    let initialSentences: [ReviewableSentence]
    var currentDueSentences: () -> [ReviewableSentence] = { [] }
    var totalInReview: () -> Int = { 0 }
    var onBack: () -> Void = {}
    var onReviewed: (String, Card) -> Void = { _, _ in }
    var onRemovedReview: (String) -> Void = { _ in }

    @State private var queue: [ReviewableSentence] = []
    @State private var waiting: [ReviewableSentence] = []
    @State private var didInit = false

    private let duePoll = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let sentence = queue.first {
                SentenceFlashcardView(
                    sentence: sentence,
                    language: language,
                    remainingDue: queue.count,
                    totalInReview: totalInReview(),
                    onBack: leaveSession,
                    onReviewed: { sentenceId, card in
                        parkReviewed(sentenceId: sentenceId, card: card)
                        onReviewed(sentenceId, card)
                    },
                    onRemovedReview: { sentenceId in
                        queue.removeAll { $0.id == sentenceId }
                        waiting.removeAll { $0.id == sentenceId }
                        onRemovedReview(sentenceId)
                    }
                )
            } else {
                VStack(spacing: 8) {
                    Text(queue.isEmpty && didInit ? "Done for now" : "No sentences due")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button("Back", action: leaveSession)
                        .font(.caption2)
                }
            }
        }
        .onAppear {
            guard !didInit else { return }
            queue = initialSentences
            didInit = true
        }
        .onDisappear {
            WordAudioPlayer.shared.stop()
        }
        .onReceive(duePoll) { _ in
            enqueueNewlyDue()
        }
    }

    private func leaveSession() {
        WordAudioPlayer.shared.stop()
        onBack()
    }

    private func parkReviewed(sentenceId: String, card: Card) {
        if let current = queue.first(where: { $0.id == sentenceId }) {
            waiting.append(current.withCard(card))
        }
        queue.removeAll { $0.id == sentenceId }
        enqueueNewlyDue()
    }

    private func enqueueNewlyDue() {
        let now = Date()
        let inQueue = Set(queue.map(\.id))

        var ready: [ReviewableSentence] = []
        var stillWaiting: [ReviewableSentence] = []
        for sentence in waiting {
            if sentence.withFreshDue(now: now).isDue, !inQueue.contains(sentence.id) {
                ready.append(sentence)
            } else {
                stillWaiting.append(sentence)
            }
        }
        waiting = stillWaiting

        let heldIds = inQueue.union(ready.map(\.id)).union(Set(waiting.map(\.id)))
        let fromStore = currentDueSentences().filter { !heldIds.contains($0.id) }

        let fresh = ready + fromStore
        guard !fresh.isEmpty else { return }
        queue.append(contentsOf: fresh)
        print("[sentence review] re-queued \(fresh.count) due sentence(s)")
    }
}
