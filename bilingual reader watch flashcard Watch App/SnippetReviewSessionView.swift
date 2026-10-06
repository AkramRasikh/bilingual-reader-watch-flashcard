//
//  SnippetReviewSessionView.swift
//  bilingual reader watch flashcard Watch App
//
//  Queues currently due snippets. Graded cards stay in the local cache with
//  their next due; they re-enter the queue when that time arrives.
//  Trash deletes the snippet.
//

import FSRS
import SwiftUI
import WatchKit

struct SnippetReviewSessionView: View {
    let language: String
    let initialSnippets: [ReviewableSnippet]
    var currentDueSnippets: () -> [ReviewableSnippet] = { [] }
    var totalInReview: () -> Int = { 0 }
    var onBack: () -> Void = {}
    var savedWordForms: Set<String> = []
    var onReviewed: (String, Card) -> Void = { _, _ in }
    var onDeleted: (String) -> Void = { _ in }
    var onWordSaved: (Word) -> Void = { _ in }

    @State private var queue: [ReviewableSnippet] = []
    @State private var waiting: [ReviewableSnippet] = []
    @State private var didInit = false

    private let duePoll = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let snippet = queue.first {
                SnippetFlashcardView(
                    snippet: snippet,
                    language: language,
                    remainingDue: queue.count,
                    totalInReview: totalInReview(),
                    onBack: onBack,
                    savedWordForms: savedWordForms,
                    onReviewed: { snippetId, card in
                        parkReviewed(snippetId: snippetId, card: card)
                        onReviewed(snippetId, card)
                    },
                    onDeleted: { snippetId in
                        queue.removeAll { $0.id == snippetId }
                        waiting.removeAll { $0.id == snippetId }
                        onDeleted(snippetId)
                    },
                    onWordSaved: onWordSaved
                )
            } else {
                VStack(spacing: 8) {
                    Text(queue.isEmpty && didInit ? "Done for now" : "No snippets due")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button("Back", action: onBack)
                        .font(.caption2)
                }
            }
        }
        .onAppear {
            guard !didInit else { return }
            queue = initialSnippets
            didInit = true
        }
        .onDisappear {
            WordAudioPlayer.shared.stop()
        }
        .onChange(of: queue.first?.id) { oldId, newId in
            guard didInit, oldId != nil, newId != nil, oldId != newId else { return }
            WKInterfaceDevice.current().play(.click)
        }
        .onReceive(duePoll) { _ in
            enqueueNewlyDue()
        }
    }

    private func parkReviewed(snippetId: String, card: Card) {
        if let current = queue.first(where: { $0.id == snippetId }) {
            waiting.append(current.withCard(card))
        }
        queue.removeAll { $0.id == snippetId }
        enqueueNewlyDue()
    }

    private func enqueueNewlyDue() {
        let now = Date()
        let inQueue = Set(queue.map(\.id))

        var ready: [ReviewableSnippet] = []
        var stillWaiting: [ReviewableSnippet] = []
        for snippet in waiting {
            if snippet.withFreshDue(now: now).isDue, !inQueue.contains(snippet.id) {
                ready.append(snippet)
            } else {
                stillWaiting.append(snippet)
            }
        }
        waiting = stillWaiting

        let heldIds = inQueue.union(ready.map(\.id)).union(Set(waiting.map(\.id)))
        let fromStore = currentDueSnippets().filter { !heldIds.contains($0.id) }

        let fresh = ready + fromStore
        guard !fresh.isEmpty else { return }
        queue.append(contentsOf: fresh)
        print("[snippet review] re-queued \(fresh.count) due snippet(s)")
    }
}
