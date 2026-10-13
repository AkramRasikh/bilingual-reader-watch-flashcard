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
    var contentTitle: (Word) -> String? = { _ in nil }
    var totalInReview: () -> Int = { 0 }
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
                    totalInReview: totalInReview(),
                    adhocSentenceIds: adhocSentenceIds,
                    contentTitle: contentTitle(word),
                    onBack: leaveSession,
                    onReviewed: { wordId, card in
                        parkReviewed(wordId: wordId, card: card)
                        onReviewed(wordId, card)
                        enqueueNewlyDue()
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
                    Button("Back", action: leaveSession)
                        .font(.caption2)
                }
            }
        }
        .onDisappear {
            WordAudioPlayer.shared.stop()
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

    private func leaveSession() {
        WordAudioPlayer.shared.stop()
        onBack()
    }

    private func parkReviewed(wordId: String, card: Card) {
        if let current = queue.first(where: { $0.id == wordId }) {
            waiting.append(current.withCard(card))
        }
        queue.removeAll { $0.id == wordId }
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
        let orderedDue = currentDueWords()
        let fromStore = orderedDue.filter { !heldIds.contains($0.id) }

        let fresh = ready + fromStore
        guard !fresh.isEmpty else { return }

        let merged = queue + fresh
        var rank: [String: Int] = [:]
        for (index, word) in orderedDue.enumerated() where rank[word.id] == nil {
            rank[word.id] = index
        }
        var position: [String: Int] = [:]
        for (index, word) in merged.enumerated() where position[word.id] == nil {
            position[word.id] = index
        }
        queue = merged.sorted { lhs, rhs in
            let left = rank[lhs.id] ?? Int.max
            let right = rank[rhs.id] ?? Int.max
            if left != right { return left < right }
            return (position[lhs.id] ?? 0) < (position[rhs.id] ?? 0)
        }
        print("[review] re-queued \(fresh.count) due word(s)")
    }
}
