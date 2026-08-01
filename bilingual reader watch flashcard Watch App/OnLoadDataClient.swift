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

    /// Always fetch every language from the API and persist.
    /// Returns the refreshed map, falling back to any existing cache when a language fails.
    static func loadBundlesByLanguage() async throws -> [String: LanguageBundle] {
        var result = LocalWordStore.loadAll()

        try await withThrowingTaskGroup(of: (String, LanguageBundle?).self) { group in
            for language in knownLanguages {
                group.addTask {
                    let bundle = try await fetchBundle(language: language)
                    return (language, bundle)
                }
            }

            for try await (language, bundle) in group {
                if let bundle, !bundle.words.isEmpty {
                    LocalWordStore.save(language: language, bundle: bundle)
                    result[language] = bundle
                } else if result[language] == nil {
                    print("[getOnLoadData] no data for \(language)")
                }
            }
        }

        return result
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
            guard let word = Word(dictionary: dict, now: now) else { return nil }
            let sentenceId = word.contexts.first
            let sentence = sentenceId.flatMap { sentenceById[$0] }
            return word.withSentence(sentence)
        }

        let dueWords = mapped.filter(\.isDue)
        print("[getOnLoadData] \(language): \(dueWords.count)/\(mapped.count) due, \(topics.count) topics")
        guard !dueWords.isEmpty else { return nil }

        return LanguageBundle(words: dueWords, topics: topics)
    }

    /// Content rows: id + title + sentence ids (for word → content join).
    private static func buildTopics(from contentItems: [[String: Any]]) -> [ContentTopic] {
        contentItems.compactMap { item in
            let id = item["id"] as? String ?? ""
            let title = item["title"] as? String ?? ""
            let sentences = item["content"] as? [[String: Any]] ?? []
            let sentenceIds = sentences.compactMap { $0["id"] as? String }
            guard !id.isEmpty, !sentenceIds.isEmpty else { return nil }
            return ContentTopic(
                id: id,
                title: title.isEmpty ? "Untitled" : title,
                sentenceIds: sentenceIds
            )
        }
    }

    /// Mirrors `initWords` sentenceId map, but keeps targetLang/baseLang instead of title.
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
                map[id] = SentenceContext(targetLang: targetLang, baseLang: baseLang)
            }
        }

        return map
    }
}
