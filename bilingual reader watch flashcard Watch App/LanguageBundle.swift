//
//  LanguageBundle.swift
//  bilingual reader watch flashcard Watch App
//
//  Per-language due words + content topics (web landing grouping).
//

import Foundation
import FSRS

struct ContentSnippet: Hashable, Codable {
    var id: String
    var targetLang: String
    var baseLang: String
    var focusedText: String?
    var suggestedFocusText: String?
    var time: TimeInterval
    var isContracted: Bool
    var isPreSnippet: Bool
    var card: Card?
    var vocab: [BreakdownWord]
    var sentenceContext: SnippetSentenceContext

    /// Older caches only stored cue fields. Missing review fields stay empty until the next reload.
    init(
        id: String = "",
        targetLang: String = "",
        baseLang: String = "",
        focusedText: String?,
        suggestedFocusText: String?,
        time: TimeInterval,
        isContracted: Bool,
        isPreSnippet: Bool,
        card: Card? = nil,
        vocab: [BreakdownWord] = [],
        sentenceContext: SnippetSentenceContext = SnippetSentenceContext()
    ) {
        self.id = id
        self.targetLang = targetLang
        self.baseLang = baseLang
        self.focusedText = focusedText
        self.suggestedFocusText = suggestedFocusText
        self.time = time
        self.isContracted = isContracted
        self.isPreSnippet = isPreSnippet
        self.card = card
        self.vocab = vocab
        self.sentenceContext = sentenceContext
    }

    enum CodingKeys: String, CodingKey {
        case id, targetLang, baseLang, focusedText, suggestedFocusText
        case time, isContracted, isPreSnippet, card, vocab, sentenceContext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        targetLang = try container.decodeIfPresent(String.self, forKey: .targetLang) ?? ""
        baseLang = try container.decodeIfPresent(String.self, forKey: .baseLang) ?? ""
        focusedText = try container.decodeIfPresent(String.self, forKey: .focusedText)
        suggestedFocusText = try container.decodeIfPresent(String.self, forKey: .suggestedFocusText)
        time = try container.decode(TimeInterval.self, forKey: .time)
        isContracted = try container.decodeIfPresent(Bool.self, forKey: .isContracted) ?? false
        isPreSnippet = try container.decodeIfPresent(Bool.self, forKey: .isPreSnippet) ?? false
        card = try container.decodeIfPresent(Card.self, forKey: .card)
        vocab = try container.decodeIfPresent([BreakdownWord].self, forKey: .vocab) ?? []
        sentenceContext = try container.decodeIfPresent(SnippetSentenceContext.self, forKey: .sentenceContext) ?? SnippetSentenceContext()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(targetLang, forKey: .targetLang)
        try container.encode(baseLang, forKey: .baseLang)
        try container.encodeIfPresent(focusedText, forKey: .focusedText)
        try container.encodeIfPresent(suggestedFocusText, forKey: .suggestedFocusText)
        try container.encode(time, forKey: .time)
        try container.encode(isContracted, forKey: .isContracted)
        try container.encode(isPreSnippet, forKey: .isPreSnippet)
        try container.encodeIfPresent(card, forKey: .card)
        try container.encode(vocab, forKey: .vocab)
        try container.encode(sentenceContext, forKey: .sentenceContext)
    }

    func withCard(_ card: Card) -> ContentSnippet {
        var copy = self
        copy.card = card
        return copy
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
    func words(forContentId contentId: String?) -> [Word] {
        wordsMatching(contentId: contentId)
            .map { withStandaloneAudioIfNeeded($0).withFreshDue() }
            .filter(\.isDue)
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

    /// Cached bundles may predate audio attachment; clip is `{sentenceId}.mp3`.
    func withStandaloneAudioIfNeeded(_ word: Word) -> Word {
        if word.canPlayAudio { return word }
        guard let sentenceId = word.contexts.first,
              adhocSentenceIds.contains(sentenceId)
        else { return word }
        return word.withAudio(fileName: sentenceId, playAt: 0)
    }

    /// All topics, sorted by combined due count (desc). Zero-due topics stay in the list.
    var topicsByDueCount: [(topic: ContentTopic, words: (due: Int, total: Int), sentences: (due: Int, total: Int), snippets: (due: Int, total: Int))] {
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
                    ),
                    snippets: (
                        due: snippetDueCount(forContentId: topic.id),
                        total: snippetReviewCount(forContentId: topic.id)
                    )
                )
            }
            .sorted {
                let left = $0.words.due + $0.sentences.due + $0.snippets.due
                let right = $1.words.due + $1.sentences.due + $1.snippets.due
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

    func sentences(forContentId contentId: String) -> [ReviewableSentence] {
        sentences
            .filter { $0.contentId == contentId }
            .map { $0.withFreshDue() }
            .filter(\.isDue)
    }

    func sentenceDueCount(forContentId contentId: String) -> Int {
        sentences(forContentId: contentId).count
    }

    func sentenceReviewCount(forContentId contentId: String) -> Int {
        sentences.filter { $0.contentId == contentId && $0.card != nil }.count
    }

    func snippets(forContentId contentId: String) -> [ReviewableSnippet] {
        guard let topic = topics.first(where: { $0.id == contentId }) else { return [] }
        return topic.snippets
            .compactMap { ReviewableSnippet(contentId: contentId, snippet: $0, audioFileName: topic.title) }
            .map { $0.withFreshDue() }
            .filter(\.isDue)
            .sorted { $0.time < $1.time }
    }

    func snippetDueCount(forContentId contentId: String) -> Int {
        snippets(forContentId: contentId).count
    }

    func snippetReviewCount(forContentId contentId: String) -> Int {
        guard let topic = topics.first(where: { $0.id == contentId }) else { return 0 }
        return topic.snippets.filter { !$0.id.isEmpty && $0.card != nil }.count
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

    func updatingSnippetCard(snippetId: String, card: Card) -> LanguageBundle {
        var copy = self
        copy.topics = copy.topics.map { topic in
            var topic = topic
            topic.snippets = topic.snippets.map { snippet in
                snippet.id == snippetId ? snippet.withCard(card) : snippet
            }
            return topic
        }
        return copy
    }

    func removingSnippet(id snippetId: String) -> LanguageBundle {
        var copy = self
        copy.topics = copy.topics.map { topic in
            var topic = topic
            topic.snippets.removeAll { $0.id == snippetId }
            return topic
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

    /// Forms used to underline snippet breakdown words (base and surface).
    func savedWordForms() -> Set<String> {
        Set(words.flatMap { word in
            [word.baseForm, word.surfaceForm]
                .map(Self.normalizedWordForm)
                .filter { !$0.isEmpty }
        })
    }

    static func normalizedWordForm(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func insertingWord(_ word: Word) -> LanguageBundle {
        var copy = self
        if !copy.words.contains(where: { $0.id == word.id }) {
            copy.words.insert(word, at: 0)
        }
        return copy
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
