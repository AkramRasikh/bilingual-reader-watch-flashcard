//
//  LanguageBundle.swift
//  bilingual reader watch flashcard Watch App
//
//  Per-language due words + content topics (web landing grouping).
//

import Foundation

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
    var words: [Word]
    var topics: [ContentTopic]

    var dueCount: Int { words.count }

    /// All due words, or only those whose `contexts[0]` belongs to the topic.
    func words(forContentId contentId: String?) -> [Word] {
        guard let contentId else { return words }
        guard let topic = topics.first(where: { $0.id == contentId }) else { return [] }
        let sentenceIds = Set(topic.sentenceIds)
        return words.filter { word in
            guard let context = word.contexts.first else { return false }
            return sentenceIds.contains(context)
        }
    }

    /// Topics that still have due cards, sorted by due count (desc).
    var topicsWithDue: [(topic: ContentTopic, count: Int)] {
        topics.compactMap { topic in
            let count = words(forContentId: topic.id).count
            return count > 0 ? (topic, count) : nil
        }
        .sorted { $0.count > $1.count }
    }

    func removingWord(id wordId: String) -> LanguageBundle {
        var copy = self
        copy.words.removeAll { $0.id == wordId }
        return copy
    }

    func topic(containingSentenceId sentenceId: String) -> ContentTopic? {
        topics.first { $0.sentenceIds.contains(sentenceId) }
    }
}
