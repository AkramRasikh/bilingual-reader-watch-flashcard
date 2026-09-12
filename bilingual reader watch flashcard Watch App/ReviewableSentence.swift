//
//  ReviewableSentence.swift
//  bilingual reader watch flashcard Watch App
//
//  Content transcript sentences that already have reviewData.
//  Graded via updateSentence; trash is removeReview (not delete).
//

import Foundation
import FSRS

struct ReviewableSentence: Identifiable, Hashable, Codable {
    let id: String
    /// Content/topic id — `indexKey` for `updateSentence`.
    let contentId: String
    let targetLang: String
    let baseLang: String
    /// Optional gloss/paraphrase from content `meaning`. Missing on many sentences.
    let meaning: String?
    /// Neighbor transcript lines (not necessarily in review). Empty if first/last.
    let previousTargetLang: String
    let previousBaseLang: String
    let nextTargetLang: String
    let nextBaseLang: String
    /// Seconds into the topic MP3 (web transcript `time`).
    let time: TimeInterval?
    let card: Card?
    let isDue: Bool
    /// Topic title — Cloudflare / local audio basename.
    let audioFileName: String?

    var canPlayAudio: Bool {
        guard let audioFileName, !audioFileName.isEmpty else { return false }
        return true
    }

    var audioCue: TimeInterval { time ?? 0 }

    /// Non-empty `meaning` after trimming. Nil when the field is absent or blank.
    var displayedMeaning: String? {
        let trimmed = meaning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var hasPrevious: Bool {
        !previousTargetLang.isEmpty || !previousBaseLang.isEmpty
    }

    init?(
        dictionary: [String: Any],
        contentId: String,
        audioFileName: String?,
        previous: (targetLang: String, baseLang: String) = ("", ""),
        next: (targetLang: String, baseLang: String) = ("", ""),
        now: Date = Date()
    ) {
        guard let id = dictionary["id"] as? String, !id.isEmpty else { return nil }
        let card = ReviewDataParsing.card(from: dictionary["reviewData"] as? [String: Any])
        guard card != nil else { return nil }

        let targetLang = dictionary["targetLang"] as? String ?? ""
        let baseLang = dictionary["baseLang"] as? String ?? ""
        guard !targetLang.isEmpty || !baseLang.isEmpty else { return nil }
        let rawMeaning = (dictionary["meaning"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        self.id = id
        self.contentId = contentId
        self.targetLang = targetLang
        self.baseLang = baseLang
        self.meaning = rawMeaning?.isEmpty == false ? rawMeaning : nil
        self.previousTargetLang = previous.targetLang
        self.previousBaseLang = previous.baseLang
        self.nextTargetLang = next.targetLang
        self.nextBaseLang = next.baseLang
        self.time = Self.doubleValue(dictionary["time"])
        self.card = card
        self.isDue = card.map { $0.due < now } ?? false
        self.audioFileName = audioFileName
    }

    func withCard(_ card: Card, now: Date = Date()) -> ReviewableSentence {
        ReviewableSentence(
            id: id,
            contentId: contentId,
            targetLang: targetLang,
            baseLang: baseLang,
            meaning: meaning,
            previousTargetLang: previousTargetLang,
            previousBaseLang: previousBaseLang,
            nextTargetLang: nextTargetLang,
            nextBaseLang: nextBaseLang,
            time: time,
            card: card,
            isDue: card.due < now,
            audioFileName: audioFileName
        )
    }

    func withFreshDue(now: Date = Date()) -> ReviewableSentence {
        ReviewableSentence(
            id: id,
            contentId: contentId,
            targetLang: targetLang,
            baseLang: baseLang,
            meaning: meaning,
            previousTargetLang: previousTargetLang,
            previousBaseLang: previousBaseLang,
            nextTargetLang: nextTargetLang,
            nextBaseLang: nextBaseLang,
            time: time,
            card: card,
            isDue: card.map { $0.due < now } ?? false,
            audioFileName: audioFileName
        )
    }

    private init(
        id: String,
        contentId: String,
        targetLang: String,
        baseLang: String,
        meaning: String?,
        previousTargetLang: String,
        previousBaseLang: String,
        nextTargetLang: String,
        nextBaseLang: String,
        time: TimeInterval?,
        card: Card?,
        isDue: Bool,
        audioFileName: String?
    ) {
        self.id = id
        self.contentId = contentId
        self.targetLang = targetLang
        self.baseLang = baseLang
        self.meaning = meaning
        self.previousTargetLang = previousTargetLang
        self.previousBaseLang = previousBaseLang
        self.nextTargetLang = nextTargetLang
        self.nextBaseLang = nextBaseLang
        self.time = time
        self.card = card
        self.isDue = isDue
        self.audioFileName = audioFileName
    }

    enum CodingKeys: String, CodingKey {
        case id, contentId, targetLang, baseLang, meaning
        case previousTargetLang, previousBaseLang, nextTargetLang, nextBaseLang
        case time, card, isDue, audioFileName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        contentId = try container.decode(String.self, forKey: .contentId)
        targetLang = try container.decode(String.self, forKey: .targetLang)
        baseLang = try container.decode(String.self, forKey: .baseLang)
        meaning = try container.decodeIfPresent(String.self, forKey: .meaning)
        previousTargetLang = try container.decodeIfPresent(String.self, forKey: .previousTargetLang) ?? ""
        previousBaseLang = try container.decodeIfPresent(String.self, forKey: .previousBaseLang) ?? ""
        nextTargetLang = try container.decodeIfPresent(String.self, forKey: .nextTargetLang) ?? ""
        nextBaseLang = try container.decodeIfPresent(String.self, forKey: .nextBaseLang) ?? ""
        time = try container.decodeIfPresent(TimeInterval.self, forKey: .time)
        card = try container.decodeIfPresent(Card.self, forKey: .card)
        isDue = try container.decode(Bool.self, forKey: .isDue)
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(contentId, forKey: .contentId)
        try container.encode(targetLang, forKey: .targetLang)
        try container.encode(baseLang, forKey: .baseLang)
        try container.encodeIfPresent(meaning, forKey: .meaning)
        try container.encode(previousTargetLang, forKey: .previousTargetLang)
        try container.encode(previousBaseLang, forKey: .previousBaseLang)
        try container.encode(nextTargetLang, forKey: .nextTargetLang)
        try container.encode(nextBaseLang, forKey: .nextBaseLang)
        try container.encodeIfPresent(time, forKey: .time)
        try container.encodeIfPresent(card, forKey: .card)
        try container.encode(isDue, forKey: .isDue)
        try container.encodeIfPresent(audioFileName, forKey: .audioFileName)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
