//
//  ReviewSessionView.swift
//  bilingual reader watch flashcard Watch App
//
//  Queues due words for a language; after grade/delete advances like web due list shrinks.
//

import SwiftUI

struct ReviewSessionView: View {
    let language: String
    let initialWords: [Word]
    var onBack: () -> Void = {}
    var onQueueChanged: ([Word]) -> Void = { _ in }

    @State private var queue: [Word] = []
    @State private var didInit = false

    var body: some View {
        Group {
            if let word = queue.first {
                FlashcardView(
                    word: word,
                    language: language,
                    remainingCount: queue.count,
                    onBack: onBack,
                    onReviewed: { wordId in
                        removeFromQueue(wordId: wordId)
                    },
                    onDeleted: { wordId in
                        removeFromQueue(wordId: wordId)
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
    }

    private func removeFromQueue(wordId: String) {
        queue.removeAll { $0.id == wordId }
        onQueueChanged(queue)
        LocalWordStore.save(language: language, words: queue)
    }
}
