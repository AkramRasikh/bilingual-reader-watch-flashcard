//
//  OnLoadDataClient.swift
//  bilingual reader watch flashcard Watch App
//

import Foundation

enum OnLoadDataClient {
    /// Matches backend `LanguageTypes` / language validation keys.
    static let knownLanguages = ["arabic", "chinese", "french", "japanese"]

    /// Loaded from `.env` → `GeneratedEnv` at build time.
    private static let endpoint = GeneratedEnv.getOnLoadDataURL

    /// Fetch one language from the API, persist, and return the bundle.
    /// Successful responses are saved even when there are 0 due words.
    static func fetchAndCache(language: String) async throws -> LanguageBundle {
        guard let bundle = try await fetchBundle(language: language) else {
            throw URLError(.cannotParseResponse)
        }
        LocalWordStore.save(language: language, bundle: bundle)
        return bundle
    }

    /// Use local cache when present; otherwise hit the API.
    static func loadLocalOrFetch(language: String) async throws -> LanguageBundle {
        if let cached = LocalWordStore.load(language: language) {
            print("[LocalWordStore] hit \(language) (\(cached.words.count) due)")
            return cached
        }
        print("[getOnLoadData] fetching \(language)")
        return try await fetchAndCache(language: language)
    }

    private static func fetchBundle(language: String) async throws -> LanguageBundle? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "language": language,
            "refs": ["words", "content"],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            print("[getOnLoadData] \(language) HTTP \(http.statusCode)")
            return nil
        }

        // Response shape: [{ "words": [...] }, { "content": [...] }] (order follows refs)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        let rawWords = root.first(where: { $0["words"] != nil })?["words"] as? [[String: Any]]
        let rawContent = root.first(where: { $0["content"] != nil })?["content"] as? [[String: Any]]

        guard let rawWords else { return nil }

        let topics = buildTopics(from: rawContent ?? [])
        let sentenceById = buildSentenceMap(from: rawContent ?? [])
        let now = Date()

        let mapped = rawWords.compactMap { dict -> Word? in
            guard var word = Word(dictionary: dict, now: now) else { return nil }
            let sentenceId = word.contexts.first
            let sentence = sentenceId.flatMap { sentenceById[$0] }
            word = word.withSentence(sentence)

            if let sentenceId,
               let topic = topics.first(where: { $0.sentenceIds.contains(sentenceId) })
            {
                let playAt = resolvePlayAt(word: word, topic: topic, sentence: sentence)
                word = word.withAudio(fileName: topic.title, playAt: playAt)
            }

            return word
        }

        let dueWords = mapped.filter(\.isDue)
        print("[getOnLoadData] \(language): \(dueWords.count)/\(mapped.count) due, \(topics.count) topics")
        return LanguageBundle(words: dueWords, topics: topics)
    }

    /// Prefer snippet cue (LearningScreenWordCard), else sentence time.
    private static func resolvePlayAt(
        word: Word,
        topic: ContentTopic,
        sentence: SentenceContext?
    ) -> TimeInterval? {
        if let snippetCue = snippetPlayAt(for: word, in: topic.snippets) {
            return max(0, snippetCue)
        }
        if let time = sentence?.time {
            return max(0, time)
        }
        return nil
    }

    /// Same matching as web LearningScreenWordCard.wordHasOverlappingSnippetTime.
    private static func snippetPlayAt(for word: Word, in snippets: [ContentSnippet]) -> TimeInterval? {
        func matches(_ item: ContentSnippet) -> Bool {
            let texts = [item.focusedText, item.suggestedFocusText].compactMap { $0 }
            return texts.contains { text in
                (!word.surfaceForm.isEmpty && text.contains(word.surfaceForm))
                    || (!word.baseForm.isEmpty && text.contains(word.baseForm))
            }
        }

        let matched = snippets.first(where: { matches($0) && !$0.isPreSnippet })
            ?? snippets.first(where: matches)

        guard let matched else { return nil }
        let padding: TimeInterval = matched.isContracted ? 0.75 : 1.5
        return matched.time - padding
    }

    /// Content rows: id + title + sentence ids + snippets.
    private static func buildTopics(from contentItems: [[String: Any]]) -> [ContentTopic] {
        contentItems.compactMap { item in
            let id = item["id"] as? String ?? ""
            let title = item["title"] as? String ?? ""
            let sentences = item["content"] as? [[String: Any]] ?? []
            let sentenceIds = sentences.compactMap { $0["id"] as? String }
            guard !id.isEmpty, !sentenceIds.isEmpty else { return nil }

            let rawSnippets = item["snippets"] as? [[String: Any]] ?? []
            let snippets = rawSnippets.compactMap { snippet -> ContentSnippet? in
                guard let time = doubleValue(snippet["time"]) else { return nil }
                let isContracted = boolValue(snippet["isContracted"])
                    || boolValue(snippet["isContract"])
                return ContentSnippet(
                    focusedText: snippet["focusedText"] as? String,
                    suggestedFocusText: snippet["suggestedFocusText"] as? String,
                    time: time,
                    isContracted: isContracted,
                    isPreSnippet: boolValue(snippet["isPreSnippet"])
                )
            }

            return ContentTopic(
                id: id,
                title: title.isEmpty ? "Untitled" : title,
                sentenceIds: sentenceIds,
                snippets: snippets
            )
        }
    }

    /// Mirrors `initWords` sentenceId map, keeping targetLang/baseLang + time.
    private static func buildSentenceMap(
        from contentItems: [[String: Any]]
    ) -> [String: SentenceContext] {
        var map: [String: SentenceContext] = [:]

        for contentItem in contentItems {
            let sentences = contentItem["content"] as? [[String: Any]] ?? []
            for sentence in sentences {
                guard let id = sentence["id"] as? String else { continue }
                let targetLang = sentence["targetLang"] as? String ?? ""
                let baseLang = sentence["baseLang"] as? String ?? ""
                guard !targetLang.isEmpty || !baseLang.isEmpty else { continue }
                map[id] = SentenceContext(
                    targetLang: targetLang,
                    baseLang: baseLang,
                    time: doubleValue(sentence["time"])
                )
            }
        }

        return map
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }
}
