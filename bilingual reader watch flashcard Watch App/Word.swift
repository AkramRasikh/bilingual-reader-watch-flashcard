//
//  Word.swift
//  bilingual reader watch flashcard Watch App
//

import Foundation
import FSRS

struct SentenceContext: Hashable {
    let targetLang: String
    let baseLang: String
}

struct Word: Identifiable, Hashable {
    let id: String
    let definition: String
    let baseForm: String
    let surfaceForm: String
    let transliteration: String
    let mnemonic: String?
    /// First entry is the sentence id used to look up content (same as web `contexts[0]`).
    let contexts: [String]
    /// Sentence resolved from `contexts[0]` via content data.
    let sentence: SentenceContext?
    /// Parsed FSRS card from `reviewData` (includes `due`).
    let card: Card?
    /// Mirrors web `initWords` / `isDueCheck`: due exists and is strictly before now.
    let isDue: Bool

    var dueDate: Date? { card?.due }

    init?(dictionary: [String: Any], sentence: SentenceContext? = nil, now: Date = Date()) {
        let id = dictionary["id"] as? String ?? UUID().uuidString
        let definition = dictionary["definition"] as? String ?? ""
        let baseForm = dictionary["baseForm"] as? String ?? ""
        let surfaceForm = dictionary["surfaceForm"] as? String ?? ""
        let transliteration = (dictionary["transliteration"] as? String)
            ?? (dictionary["phonetic"] as? String)
            ?? ""
        let mnemonic = dictionary["mnemonic"] as? String
        let contexts = dictionary["contexts"] as? [String] ?? []
        let card = Self.parseCard(from: dictionary["reviewData"] as? [String: Any])

        guard !definition.isEmpty || !baseForm.isEmpty || !surfaceForm.isEmpty else {
            return nil
        }

        self.id = id
        self.definition = definition.isEmpty ? "(no definition)" : definition
        self.baseForm = baseForm
        self.surfaceForm = surfaceForm
        self.transliteration = transliteration
        self.mnemonic = mnemonic?.isEmpty == false ? mnemonic : nil
        self.contexts = contexts
        self.sentence = sentence
        self.card = card
        // Same as web isDueCheck: missing due => false; due < now => true
        self.isDue = card.map { $0.due < now } ?? false
    }

    func withSentence(_ sentence: SentenceContext?) -> Word {
        Word(
            id: id,
            definition: definition,
            baseForm: baseForm,
            surfaceForm: surfaceForm,
            transliteration: transliteration,
            mnemonic: mnemonic,
            contexts: contexts,
            sentence: sentence,
            card: card,
            isDue: isDue
        )
    }

    private static func parseCard(from reviewData: [String: Any]?) -> Card? {
        guard let reviewData, let due = parseDate(reviewData["due"]) else {
            return nil
        }

        let stateValue = intValue(reviewData["state"]) ?? 0
        let state = CardState(rawValue: stateValue) ?? .new

        return Card(
            due: due,
            stability: doubleValue(reviewData["stability"]) ?? 0,
            difficulty: doubleValue(reviewData["difficulty"]) ?? 0,
            elapsedDays: doubleValue(reviewData["elapsed_days"]) ?? 0,
            scheduledDays: doubleValue(reviewData["scheduled_days"]) ?? 0,
            reps: intValue(reviewData["reps"]) ?? 0,
            lapses: intValue(reviewData["lapses"]) ?? 0,
            state: state,
            lastReview: parseDate(reviewData["last_review"])
        )
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return dueDateParsers.lazy.compactMap { $0.date(from: string) }.first
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? Double { return Int(number) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static let dueDateParsers: [ISO8601DateFormatter] = {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let withoutFractional = ISO8601DateFormatter()
        withoutFractional.formatOptions = [.withInternetDateTime]

        return [withFractional, withoutFractional]
    }()

    private init(
        id: String,
        definition: String,
        baseForm: String,
        surfaceForm: String,
        transliteration: String,
        mnemonic: String?,
        contexts: [String],
        sentence: SentenceContext?,
        card: Card?,
        isDue: Bool
    ) {
        self.id = id
        self.definition = definition
        self.baseForm = baseForm
        self.surfaceForm = surfaceForm
        self.transliteration = transliteration
        self.mnemonic = mnemonic
        self.contexts = contexts
        self.sentence = sentence
        self.card = card
        self.isDue = isDue
    }
}
