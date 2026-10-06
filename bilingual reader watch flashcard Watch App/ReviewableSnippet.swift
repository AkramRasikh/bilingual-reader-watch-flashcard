//
//  ReviewableSnippet.swift
//  bilingual reader watch flashcard Watch App
//
//  A content snippet that already has FSRS reviewData.
//

import Foundation
import FSRS

struct BreakdownWord: Hashable, Codable {
    var surfaceForm: String
    var meaning: String
    /// Transcript sentence this meaning came from. Required by addWord.
    var sentenceId: String
    var sentenceText: String
    var sentenceTime: TimeInterval

    init(
        surfaceForm: String,
        meaning: String,
        sentenceId: String = "",
        sentenceText: String = "",
        sentenceTime: TimeInterval = 0
    ) {
        self.surfaceForm = surfaceForm
        self.meaning = meaning
        self.sentenceId = sentenceId
        self.sentenceText = sentenceText
        self.sentenceTime = sentenceTime
    }

    enum CodingKeys: String, CodingKey {
        case surfaceForm, meaning, sentenceId, sentenceText, sentenceTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        surfaceForm = try container.decode(String.self, forKey: .surfaceForm)
        meaning = try container.decode(String.self, forKey: .meaning)
        sentenceId = try container.decodeIfPresent(String.self, forKey: .sentenceId) ?? ""
        sentenceText = try container.decodeIfPresent(String.self, forKey: .sentenceText) ?? ""
        sentenceTime = try container.decodeIfPresent(TimeInterval.self, forKey: .sentenceTime) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(surfaceForm, forKey: .surfaceForm)
        try container.encode(meaning, forKey: .meaning)
        try container.encode(sentenceId, forKey: .sentenceId)
        try container.encode(sentenceText, forKey: .sentenceText)
        try container.encode(sentenceTime, forKey: .sentenceTime)
    }
}

/// One transcript sentence's breakdown, in web vocab order.
struct SnippetBreakdownGroup: Hashable, Codable, Identifiable {
    var id: String
    var targetLang: String
    var words: [BreakdownWord]
}

/// One transcript sentence on the snippet's sentence swipe.
struct SnippetSentenceLine: Hashable, Codable, Identifiable {
    var id: String
    var targetLang: String
    var baseLang: String
    /// AI translation of the whole sentence. Empty when the transcript has none.
    var meaning: String
    var isCurrent: Bool
}

/// Transcript lines around a snippet, in sentence-review order.
struct SnippetSentenceContext: Hashable, Codable {
    var previousTarget: String = ""
    /// Overlapping transcript lines joined in order.
    var currentTarget: String = ""
    var currentBase: String = ""
    var nextTarget: String = ""
    /// Breakdowns for the previous, overlapping, and next sentences, when vocab exists.
    var breakdowns: [SnippetBreakdownGroup] = []
    /// Previous, overlapping, and next sentences, each with target, base, and meaning.
    var lines: [SnippetSentenceLine] = []

    init(
        previousTarget: String = "",
        currentTarget: String = "",
        currentBase: String = "",
        nextTarget: String = "",
        breakdowns: [SnippetBreakdownGroup] = [],
        lines: [SnippetSentenceLine] = []
    ) {
        self.previousTarget = previousTarget
        self.currentTarget = currentTarget
        self.currentBase = currentBase
        self.nextTarget = nextTarget
        self.breakdowns = breakdowns
        self.lines = lines
    }

    enum CodingKeys: String, CodingKey {
        case previousTarget, currentTarget, currentBase, nextTarget, breakdowns, lines
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        previousTarget = try container.decodeIfPresent(String.self, forKey: .previousTarget) ?? ""
        currentTarget = try container.decodeIfPresent(String.self, forKey: .currentTarget) ?? ""
        currentBase = try container.decodeIfPresent(String.self, forKey: .currentBase) ?? ""
        nextTarget = try container.decodeIfPresent(String.self, forKey: .nextTarget) ?? ""
        breakdowns = try container.decodeIfPresent([SnippetBreakdownGroup].self, forKey: .breakdowns) ?? []
        lines = try container.decodeIfPresent([SnippetSentenceLine].self, forKey: .lines) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(previousTarget, forKey: .previousTarget)
        try container.encode(currentTarget, forKey: .currentTarget)
        try container.encode(currentBase, forKey: .currentBase)
        try container.encode(nextTarget, forKey: .nextTarget)
        try container.encode(breakdowns, forKey: .breakdowns)
        try container.encode(lines, forKey: .lines)
    }
}

struct ReviewableSnippet: Identifiable, Hashable {
    let id: String
    let contentId: String
    var targetLang: String
    var baseLang: String
    var focusedText: String?
    var suggestedFocusText: String?
    var time: TimeInterval
    var isContracted: Bool
    var isPreSnippet: Bool
    var card: Card?
    var isDue: Bool
    /// Topic title — Cloudflare / local audio basename.
    var audioFileName: String?
    /// Words from transcript sentences that overlap this snippet's time window.
    var vocab: [BreakdownWord]
    /// Full sentences overlapping the snippet window, plus the lines before and after.
    var sentenceContext: SnippetSentenceContext

    /// Saved focus, otherwise the suggested pre-snippet span.
    var focusQuery: String {
        let focused = focusedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !focused.isEmpty { return focused }
        return suggestedFocusText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var canPlayAudio: Bool {
        guard let audioFileName, !audioFileName.isEmpty else { return false }
        return true
    }

    /// Same window as web SnippetReview: `time ± 1.5s`, or `± 0.75s` when contracted.
    func loopWindow(fileDuration: TimeInterval? = nil) -> (start: TimeInterval, end: TimeInterval) {
        let padding: TimeInterval = isContracted ? 0.75 : 1.5
        let start = max(0, time - padding)
        var end = time + padding
        if let fileDuration, fileDuration > start {
            end = min(fileDuration, end)
        }
        return (start, max(start, end))
    }

    init?(contentId: String, snippet: ContentSnippet, audioFileName: String? = nil, now: Date = Date()) {
        guard !snippet.id.isEmpty, let card = snippet.card else { return nil }
        self.id = snippet.id
        self.contentId = contentId
        self.targetLang = snippet.targetLang
        self.baseLang = snippet.baseLang
        self.focusedText = snippet.focusedText
        self.suggestedFocusText = snippet.suggestedFocusText
        self.time = snippet.time
        self.isContracted = snippet.isContracted
        self.isPreSnippet = snippet.isPreSnippet
        self.card = card
        self.isDue = card.due < now
        self.audioFileName = audioFileName
        self.vocab = snippet.vocab
        self.sentenceContext = snippet.sentenceContext
    }

    func withCard(_ card: Card, now: Date = Date()) -> ReviewableSnippet {
        var copy = self
        copy.card = card
        copy.isDue = card.due < now
        return copy
    }

    func withFreshDue(now: Date = Date()) -> ReviewableSnippet {
        var copy = self
        copy.isDue = card.map { $0.due < now } ?? false
        return copy
    }

    /// Body field `snippetData` for `/api/saveSnippet`. Omits vocab, same as the web.
    func snippetDataDictionary(reviewCard: Card?) -> [String: Any] {
        var data: [String: Any] = [
            "id": id,
            "targetLang": targetLang,
            "baseLang": baseLang,
            "time": time,
            "isContracted": isContracted,
            "isPreSnippet": isPreSnippet,
        ]
        if let focusedText {
            data["focusedText"] = focusedText
        }
        if let suggestedFocusText {
            data["suggestedFocusText"] = suggestedFocusText
        }
        if let reviewCard {
            let persisted = VocabSRS.cardForPersist(reviewCard)
            data["reviewData"] = VocabSRS.reviewDataDictionary(from: persisted)
        }
        return data
    }
}
