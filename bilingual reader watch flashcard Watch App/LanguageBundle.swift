//
//  LanguageBundle.swift
//  bilingual reader watch flashcard Watch App
//
//  Per-language due words + content topics (web landing grouping).
//

import Foundation
import FSRS

/// Cue used to seek a word into topic audio. Review fields from older caches are ignored.
struct ContentSnippet: Hashable, Codable {
    var id: String
    var focusedText: String?
    var suggestedFocusText: String?
    var time: TimeInterval
    var isContracted: Bool
    var isPreSnippet: Bool

    init(
        id: String = "",
        focusedText: String?,
        suggestedFocusText: String?,
        time: TimeInterval,
        isContracted: Bool,
        isPreSnippet: Bool
    ) {
        self.id = id
        self.focusedText = focusedText
        self.suggestedFocusText = suggestedFocusText
        self.time = time
        self.isContracted = isContracted
        self.isPreSnippet = isPreSnippet
    }

    enum CodingKeys: String, CodingKey {
        case id, focusedText, suggestedFocusText
        case time, isContracted, isPreSnippet
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        focusedText = try container.decodeIfPresent(String.self, forKey: .focusedText)
        suggestedFocusText = try container.decodeIfPresent(String.self, forKey: .suggestedFocusText)
        time = try container.decode(TimeInterval.self, forKey: .time)
        isContracted = try container.decodeIfPresent(Bool.self, forKey: .isContracted) ?? false
        isPreSnippet = try container.decodeIfPresent(Bool.self, forKey: .isPreSnippet) ?? false
    }
}

struct ContentTopic: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    /// Sentence ids from `content[].content[].id` — words join via `contexts[0]`.
    let sentenceIds: [String]
    var snippets: [ContentSnippet]
}

struct LanguageBundle: Hashable, Codable {
    /// Sentinel `contentId` for the derived Adhoc words queue.
    static let adhocContentId = "adhoc"

    var words: [Word]
    var topics: [ContentTopic]
    /// Sentence ids from `{language}/sentences` with `topic == sentence-helper`.
    var adhocSentenceIds: [String]
    /// Content transcript sentences that already have `reviewData`.
    var sentences: [ReviewableSentence]

    var dueCount: Int {
        words.reduce(0) { $0 + ($1.withFreshDue().isDue ? 1 : 0) }
    }

    var wordReviewCount: Int {
        words.reduce(0) { $0 + ($1.card != nil ? 1 : 0) }
    }

    var sentenceDueCount: Int {
        sentences.reduce(0) { $0 + ($1.withFreshDue().isDue ? 1 : 0) }
    }

    var sentenceReviewCount: Int {
        sentences.count
    }

    var adhocDueCount: Int { words(forContentId: Self.adhocContentId).count }

    init(
        words: [Word],
        topics: [ContentTopic],
        adhocSentenceIds: [String] = [],
        sentences: [ReviewableSentence] = []
    ) {
        self.words = words
        self.topics = topics
        self.adhocSentenceIds = adhocSentenceIds
        self.sentences = sentences
    }

    /// All due words, Adhoc (`adhocContentId`), or a content topic.
    /// All is grouped like the content list (Adhoc first, then most due topics).
    /// Every queue is oldest `card.due` first, with the stored list order as a tie-break.
    func words(forContentId contentId: String?) -> [Word] {
        let due = indexedDueWords(matching: contentId)
        if contentId == nil {
            return orderedAllDueWords(due)
        }
        return due.sorted { oldestDueFirst($0, $1) }.map(\.word)
    }

    /// Topic title for a word, via `contexts[0]` matching a topic's sentence ids.
    func contentTitle(for word: Word) -> String? {
        guard let sentenceId = word.contexts.first else { return nil }
        let title = topics.first { $0.sentenceIds.contains(sentenceId) }?.title
        guard let title, !title.isEmpty else { return nil }
        return title
    }

    func wordReviewCount(forContentId contentId: String?) -> Int {
        wordsMatching(contentId: contentId).filter { $0.card != nil }.count
    }

    private func wordsMatching(contentId: String?) -> [Word] {
        if contentId == Self.adhocContentId {
            let sentenceIds = Set(adhocSentenceIds)
            return words.filter { word in
                guard let context = word.contexts.first else { return false }
                return sentenceIds.contains(context)
            }
        }
        if let contentId {
            guard let topic = topics.first(where: { $0.id == contentId }) else { return [] }
            let sentenceIds = Set(topic.sentenceIds)
            return words.filter { word in
                guard let context = word.contexts.first else { return false }
                return sentenceIds.contains(context)
            }
        }
        return words
    }

    private struct IndexedDueWord {
        let index: Int
        let word: Word
    }

    private func indexedDueWords(matching contentId: String?) -> [IndexedDueWord] {
        wordsMatching(contentId: contentId)
            .enumerated()
            .map { index, word in
                IndexedDueWord(
                    index: index,
                    word: withStandaloneAudioIfNeeded(word).withFreshDue()
                )
            }
            .filter(\.word.isDue)
    }

    /// Oldest due date first. Equal dates keep the stored list order.
    private func oldestDueFirst(_ lhs: IndexedDueWord, _ rhs: IndexedDueWord) -> Bool {
        let left = lhs.word.card?.due ?? .distantFuture
        let right = rhs.word.card?.due ?? .distantFuture
        if left != right { return left < right }
        return lhs.index < rhs.index
    }

    /// Adhoc and words with no topic first, then `topicsByDueCount` order.
    /// The per-topic path of `words(forContentId:)` does not call this, so
    /// `topicsByDueCount` can count those queues without recursing.
    private func orderedAllDueWords(_ due: [IndexedDueWord]) -> [Word] {
        var topicIdBySentence: [String: String] = [:]
        for topic in topics {
            for sentenceId in topic.sentenceIds where topicIdBySentence[sentenceId] == nil {
                topicIdBySentence[sentenceId] = topic.id
            }
        }

        var unassigned: [IndexedDueWord] = []
        var byTopic: [String: [IndexedDueWord]] = [:]
        for item in due {
            if let sentenceId = item.word.contexts.first,
               let topicId = topicIdBySentence[sentenceId] {
                byTopic[topicId, default: []].append(item)
            } else {
                unassigned.append(item)
            }
        }

        var ordered = unassigned.sorted { oldestDueFirst($0, $1) }.map(\.word)
        for row in topicsByDueCount {
            let group = byTopic[row.topic.id] ?? []
            ordered.append(contentsOf: group.sorted { oldestDueFirst($0, $1) }.map(\.word))
        }
        return ordered
    }

    /// Cached bundles may predate audio attachment; clip is `{sentenceId}.mp3`.
    func withStandaloneAudioIfNeeded(_ word: Word) -> Word {
        if word.canPlayAudio { return word }
        guard let sentenceId = word.contexts.first,
              adhocSentenceIds.contains(sentenceId)
        else { return word }
        return word.withAudio(fileName: sentenceId, playAt: 0)
    }

    /// All topics, sorted by combined word and sentence due count (desc). Zero-due topics stay in the list.
    var topicsByDueCount: [(topic: ContentTopic, words: (due: Int, total: Int), sentences: (due: Int, total: Int))] {
        topics
            .map { topic in
                (
                    topic: topic,
                    words: (
                        due: words(forContentId: topic.id).count,
                        total: wordReviewCount(forContentId: topic.id)
                    ),
                    sentences: (
                        due: sentenceDueCount(forContentId: topic.id),
                        total: sentenceReviewCount(forContentId: topic.id)
                    )
                )
            }
            .sorted {
                let left = $0.words.due + $0.sentences.due
                let right = $1.words.due + $1.sentences.due
                if left != right { return left > right }
                return $0.topic.title < $1.topic.title
            }
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

    /// Due sentences for one topic, or every topic when `contentId` is nil.
    /// All follows the content list: each topic's sentences stay in transcript order.
    func sentences(forContentId contentId: String?) -> [ReviewableSentence] {
        if let contentId {
            return dueSentences(in: contentId)
        }
        return orderedAllDueSentences()
    }

    func sentenceDueCount(forContentId contentId: String?) -> Int {
        sentences(forContentId: contentId).count
    }

    func sentenceReviewCount(forContentId contentId: String?) -> Int {
        let matching = contentId.map { id in sentences.filter { $0.contentId == id } } ?? sentences
        return matching.filter { $0.card != nil }.count
    }

    func contentTitle(for sentence: ReviewableSentence) -> String? {
        let title = topics.first { $0.id == sentence.contentId }?.title
        guard let title, !title.isEmpty else { return nil }
        return title
    }

    private func dueSentences(in contentId: String) -> [ReviewableSentence] {
        sentences
            .filter { $0.contentId == contentId }
            .map { $0.withFreshDue() }
            .filter(\.isDue)
    }

    /// Content-list order, transcript order inside each topic. Unassigned sentences come first.
    private func orderedAllDueSentences() -> [ReviewableSentence] {
        let topicIds = Set(topics.map(\.id))
        var unassigned: [ReviewableSentence] = []
        var byTopic: [String: [ReviewableSentence]] = [:]
        for sentence in sentences {
            let fresh = sentence.withFreshDue()
            guard fresh.isDue else { continue }
            if topicIds.contains(fresh.contentId) {
                byTopic[fresh.contentId, default: []].append(fresh)
            } else {
                unassigned.append(fresh)
            }
        }

        var ordered = unassigned
        for row in topicsByDueCount {
            ordered.append(contentsOf: byTopic[row.topic.id] ?? [])
        }
        return ordered
    }

    func updatingCard(wordId: String, card: Card) -> LanguageBundle {
        var copy = self
        copy.words = copy.words.map { word in
            word.id == wordId ? word.withCard(card) : word
        }
        return copy
    }

    func updatingSentenceCard(sentenceId: String, card: Card) -> LanguageBundle {
        var copy = self
        copy.sentences = copy.sentences.map { sentence in
            sentence.id == sentenceId ? sentence.withCard(card) : sentence
        }
        return copy
    }

    func removingSentenceReview(id sentenceId: String) -> LanguageBundle {
        var copy = self
        copy.sentences.removeAll { $0.id == sentenceId }
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

    /// Bumped when snippet review fields must be re-read from the server.
    /// 6 attaches each sentence's AI meaning on the snippet sentence swipe.
    private static let snippetSchemaVersion = 6

    enum CodingKeys: String, CodingKey {
        case words
        case topics
        case adhocSentenceIds
        case sentences
        case snippetSchema
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decodeIfPresent(Int.self, forKey: .snippetSchema) ?? 0
        guard schema >= Self.snippetSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .snippetSchema,
                in: container,
                debugDescription: "Snippet cache is missing review fields"
            )
        }
        words = try container.decode([Word].self, forKey: .words)
        topics = try container.decode([ContentTopic].self, forKey: .topics)
        adhocSentenceIds = try container.decodeIfPresent([String].self, forKey: .adhocSentenceIds) ?? []
        sentences = try container.decodeIfPresent([ReviewableSentence].self, forKey: .sentences) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(words, forKey: .words)
        try container.encode(topics, forKey: .topics)
        try container.encode(adhocSentenceIds, forKey: .adhocSentenceIds)
        try container.encode(sentences, forKey: .sentences)
        try container.encode(Self.snippetSchemaVersion, forKey: .snippetSchema)
    }
}
