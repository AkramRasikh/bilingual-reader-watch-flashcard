//
//  ReviewOutbox.swift
//  bilingual reader watch flashcard Watch App
//
//  One pending word grade or delete per word. The session applies the card
//  locally first; this file is what later reaches updateWord / deleteWord.
//

import Foundation
import FSRS

@MainActor
final class ReviewOutbox: ObservableObject {
    static let shared = ReviewOutbox()

    @Published private(set) var counts: [String: Int] = [:]

    private var flushing: Set<String> = []
    private var flushAgain: Set<String> = []

    private init() {
        var initial: [String: Int] = [:]
        for language in OnLoadDataClient.knownLanguages {
            initial[language] = Self.loadOps(language: language).count
        }
        counts = initial
    }

    func count(for language: String) -> Int {
        counts[language] ?? 0
    }

    /// Latest card wins. A grade replaces any earlier grade or delete for this word.
    func enqueueGrade(language: String, wordId: String, card: Card) {
        guard !language.isEmpty, !wordId.isEmpty else { return }
        var ops = Self.loadOps(language: language)
        ops[wordId] = .grade(card)
        Self.store(ops, language: language)
        counts[language] = Self.loadOps(language: language).count
        print("[ReviewOutbox] queued grade \(wordId) (\(counts[language] ?? 0) pending)")
    }

    /// Delete replaces any pending grade for this word.
    func enqueueDelete(language: String, wordId: String, additionalContext: [String]) {
        guard !language.isEmpty, !wordId.isEmpty else { return }
        var ops = Self.loadOps(language: language)
        ops[wordId] = .delete(additionalContext: additionalContext)
        Self.store(ops, language: language)
        counts[language] = Self.loadOps(language: language).count
        print("[ReviewOutbox] queued delete \(wordId) (\(counts[language] ?? 0) pending)")
    }

    /// Overlay unsynced word cards and removals. Sentence rows are left as given.
    func apply(language: String, to bundle: LanguageBundle) -> LanguageBundle {
        let ops = Self.loadOps(language: language)
        guard !ops.isEmpty else { return bundle }
        var merged = bundle
        for (wordId, op) in ops {
            switch op {
            case .grade(let card):
                merged = merged.updatingCard(wordId: wordId, card: card)
            case .delete:
                merged = merged.removingWord(id: wordId)
            }
        }
        return merged
    }

    func flushAll() async {
        let pending = counts.filter { $0.value > 0 }.map(\.key).sorted()
        for language in pending {
            await flush(language: language)
        }
    }

    /// Posts queued word ops through the existing endpoints. A failed post stays queued.
    /// A transport failure stops the rest of this pass so an offline radio is not retried per card.
    func flush(language: String) async {
        guard !language.isEmpty else { return }
        if flushing.contains(language) {
            flushAgain.insert(language)
            return
        }
        flushing.insert(language)
        defer {
            flushing.remove(language)
            if flushAgain.remove(language) != nil {
                Task { await self.flush(language: language) }
            }
        }

        let ids = Self.loadOps(language: language).keys.sorted()
        for wordId in ids {
            guard let op = Self.loadOps(language: language)[wordId] else { continue }
            do {
                try await send(language: language, wordId: wordId, op: op)
                drop(language: language, wordId: wordId, matching: op)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code != .badServerResponse {
                print("[ReviewOutbox] flush stopped \(language): \(error)")
                return
            } catch {
                print("[ReviewOutbox] kept \(wordId): \(error)")
            }
        }
    }

    private func send(language: String, wordId: String, op: PendingWordOp) async throws {
        switch op {
        case .grade(let card):
            try await WordReviewClient.updateReviewData(
                wordId: wordId,
                language: language,
                card: card,
                timeout: Self.flushTimeout
            )
        case .delete(let additionalContext):
            try await WordReviewClient.deleteWord(
                wordId: wordId,
                language: language,
                additionalContext: additionalContext,
                timeout: Self.flushTimeout
            )
        }
    }

    /// Drop the op only if a newer grade or delete has not replaced it while the request was in flight.
    private func drop(language: String, wordId: String, matching sent: PendingWordOp) {
        var ops = Self.loadOps(language: language)
        guard ops[wordId] == sent else { return }
        ops.removeValue(forKey: wordId)
        Self.store(ops, language: language)
        counts[language] = ops.count
        print("[ReviewOutbox] uploaded \(wordId) (\(ops.count) pending)")
    }

    private static let flushTimeout: TimeInterval = 20

    private static func loadOps(language: String) -> [String: PendingWordOp] {
        guard let url = fileURL(for: language),
              let data = try? Data(contentsOf: url)
        else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: PendingWordOp].self, from: data)
        } catch {
            print("[ReviewOutbox] decode \(language) failed: \(error)")
            return [:]
        }
    }

    private static func store(_ ops: [String: PendingWordOp], language: String) {
        guard let url = fileURL(for: language) else { return }
        do {
            if ops.isEmpty {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                return
            }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(ops)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[ReviewOutbox] save \(language) failed: \(error)")
        }
    }

    private static func fileURL(for language: String) -> URL? {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return root
            .appendingPathComponent("word-cache", isDirectory: true)
            .appendingPathComponent("\(language)-outbox.json", isDirectory: false)
    }
}

private enum PendingWordOp: Codable, Equatable {
    case grade(Card)
    case delete(additionalContext: [String])
}
