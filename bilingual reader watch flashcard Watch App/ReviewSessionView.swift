//
//  ReviewSessionView.swift
//  bilingual reader watch flashcard Watch App
//
//  Queues currently due words. Graded cards stay in the local cache with
//  their next due; they re-enter the queue when that time arrives.
//

import Combine
import FSRS
import SwiftUI

struct ReviewSessionView: View {
    let language: String
    let initialWords: [Word]
    var adhocSentenceIds: [String] = []
    var currentDueWords: () -> [Word] = { [] }
    var onBack: () -> Void = {}
    var onReviewed: (String, Card) -> Void = { _, _ in }
    var onDeleted: (String) -> Void = { _ in }

    @State private var queue: [Word] = []
    @State private var waiting: [Word] = []
    @State private var didInit = false

    private let duePoll = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let word = queue.first {
                FlashcardView(
                    word: word,
                    language: language,
                    remainingCount: queue.count,
                    adhocSentenceIds: adhocSentenceIds,
                    onBack: onBack,
                    onReviewed: { wordId, card in
                        parkReviewed(wordId: wordId, card: card)
                        onReviewed(wordId, card)
                    },
                    onDeleted: { wordId in
                        queue.removeAll { $0.id == wordId }
                        waiting.removeAll { $0.id == wordId }
                        onDeleted(wordId)
                    }
                )
            } else {
                VStack(spacing: 8) {
                    Text(queue.isEmpty && didInit ? "Done for now" : "No words due")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button("Back", action: onBack)
                        .font(.caption2)
                }
            }
        }
        .onAppear {
            guard !didInit else { return }
            queue = initialWords
            didInit = true
        }
        .onReceive(duePoll) { _ in
            enqueueNewlyDue()
        }
    }

    private func parkReviewed(wordId: String, card: Card) {
        if let current = queue.first(where: { $0.id == wordId }) {
            waiting.append(current.withCard(card))
        }
        queue.removeAll { $0.id == wordId }
        enqueueNewlyDue()
    }

    private func enqueueNewlyDue() {
        let now = Date()
        let inQueue = Set(queue.map(\.id))

        var ready: [Word] = []
        var stillWaiting: [Word] = []
        for word in waiting {
            if word.withFreshDue(now: now).isDue, !inQueue.contains(word.id) {
                ready.append(word)
            } else {
                stillWaiting.append(word)
            }
        }
        waiting = stillWaiting

        let heldIds = inQueue.union(ready.map(\.id)).union(Set(waiting.map(\.id)))
        let fromStore = currentDueWords().filter { !heldIds.contains($0.id) }

        let fresh = ready + fromStore
        guard !fresh.isEmpty else { return }
        queue.append(contentsOf: fresh)
        print("[review] re-queued \(fresh.count) due word(s)")
    }
}
