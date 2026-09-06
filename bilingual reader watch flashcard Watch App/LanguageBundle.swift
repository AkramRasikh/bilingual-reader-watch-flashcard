//
//  LanguageBundle.swift
//  bilingual reader watch flashcard Watch App
//
//  Per-language due words + content topics (web landing grouping).
//

import Foundation
import FSRS

struct ContentSnippet: Hashable, Codable {
    let focusedText: String?
    let suggestedFocusText: String?
    let time: TimeInterval
    let isContracted: Bool
    let isPreSnippet: Bool
}

struct ContentTopic: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    /// Sentence ids from `content[].content[].id` — words join via `contexts[0]`.
    let sentenceIds: [String]
    let snippets: [ContentSnippet]
}

struct LanguageBundle: Hashable, Codable {
    /// Sentinel `contentId` for the derived Adhoc words queue.
    static let adhocContentId = "adhoc"

    var words: [Word]
    var topics: [ContentTopic]
    /// Sentence ids from `{language}/sentences` with `topic == sentence-helper`.
    var adhocSentenceIds: [String]

    var dueCount: Int {
        words.reduce(0) { $0 + ($1.withFreshDue().isDue ? 1 : 0) }
    }

    var adhocDueCount: Int { words(forContentId: Self.adhocContentId).count }

    init(words: [Word], topics: [ContentTopic], adhocSentenceIds: [String] = []) {
        self.words = words
        self.topics = topics
        self.adhocSentenceIds = adhocSentenceIds
    }

    /// All due words, Adhoc (`adhocContentId`), or a content topic.
    func words(forContentId contentId: String?) -> [Word] {
        let filtered: [Word]
        if contentId == Self.adhocContentId {
            let sentenceIds = Set(adhocSentenceIds)
            filtered = words.filter { word in
                guard let context = word.contexts.first else { return false }
                return sentenceIds.contains(context)
            }
        } else if let contentId {
            guard let topic = topics.first(where: { $0.id == contentId }) else { return [] }
            let sentenceIds = Set(topic.sentenceIds)
            filtered = words.filter { word in
                guard let context = word.contexts.first else { return false }
                return sentenceIds.contains(context)
            }
        } else {
            filtered = words
        }
        return filtered
            .map { withStandaloneAudioIfNeeded($0).withFreshDue() }
            .filter(\.isDue)
    }

    /// Cached bundles may predate audio attachment; clip is `{sentenceId}.mp3`.
    func withStandaloneAudioIfNeeded(_ word: Word) -> Word {
        if word.canPlayAudio { return word }
        guard let sentenceId = word.contexts.first,
              adhocSentenceIds.contains(sentenceId)
        else { return word }
        return word.withAudio(fileName: sentenceId, playAt: 0)
    }

    /// All topics, sorted by due count (desc). Zero-due topics stay in the list.
    var topicsByDueCount: [(topic: ContentTopic, count: Int)] {
        topics
            .map { topic in (topic: topic, count: words(forContentId: topic.id).count) }
            .sorted { $0.count > $1.count }
    }

    /// Merge a newly uploaded Adhoc word. Non-due cards still register their sentence id.
    func insertingAdhocWord(_ word: Word) -> LanguageBundle {
        var copy = self
        if let sentenceId = word.contexts.first,
           !copy.adhocSentenceIds.contains(sentenceId)
        {
            copy.adhocSentenceIds.append(sentenceId)
        }
        let hydrated = copy.withStandaloneAudioIfNeeded(word)
        if !copy.words.contains(where: { $0.id == hydrated.id }) {
            copy.words.insert(hydrated, at: 0)
        }
        return copy
    }

    func updatingCard(wordId: String, card: Card) -> LanguageBundle {
        var copy = self
        copy.words = copy.words.map { word in
            word.id == wordId ? word.withCard(card) : word
        }
        return copy
    }

    func removingWord(id wordId: String) -> LanguageBundle {
        var copy = self
        if let word = words.first(where: { $0.id == wordId }),
           let sentenceId = word.contexts.first,
           adhocSentenceIds.contains(sentenceId)
        {
            copy.adhocSentenceIds.removeAll { $0 == sentenceId }
        }
        copy.words.removeAll { $0.id == wordId }
        return copy
    }

    func topic(containingSentenceId sentenceId: String) -> ContentTopic? {
        topics.first { $0.sentenceIds.contains(sentenceId) }
    }

    enum CodingKeys: String, CodingKey {
        case words
        case topics
        case adhocSentenceIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        words = try container.decode([Word].self, forKey: .words)
        topics = try container.decode([ContentTopic].self, forKey: .topics)
        adhocSentenceIds = try container.decodeIfPresent([String].self, forKey: .adhocSentenceIds) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(words, forKey: .words)
        try container.encode(topics, forKey: .topics)
        try container.encode(adhocSentenceIds, forKey: .adhocSentenceIds)
    }
}
