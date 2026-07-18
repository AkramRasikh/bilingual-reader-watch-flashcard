//
//  OnLoadDataClient.swift
//  bilingual reader watch flashcard Watch App
//

import Foundation

enum OnLoadDataClient {
    /// Matches backend `LanguageTypes` / language validation keys.
    static let knownLanguages = ["arabic", "chinese", "french", "japanese"]

    /// Firebase emulator URL for getOnLoadData.
    /// Watch simulator → Mac localhost. Physical watch needs your Mac LAN IP instead.
    private static let endpoint = URL(
        string: "http://127.0.0.1:5001/language-content-storage/us-central1/getOnLoadData"
    )!

    /// Fetches words + content per language, maps `contexts[0]` → sentence like web `initWords`.
    static func fetchWordsByLanguage() async throws -> [String: [Word]] {
        var result: [String: [Word]] = [:]

        try await withThrowingTaskGroup(of: (String, [Word]?).self) { group in
            for language in knownLanguages {
                group.addTask {
                    let words = try await fetchAndMapWords(language: language)
                    return (language, words)
                }
            }

            for try await (language, words) in group {
                if let words, !words.isEmpty {
                    result[language] = words
                }
            }
        }

        return result
    }

    private static func fetchAndMapWords(language: String) async throws -> [Word]? {
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

        // Same idea as web initWords: sentenceId -> metadata from content[].content[]
        let sentenceById = buildSentenceMap(from: rawContent ?? [])

        return rawWords.compactMap { dict -> Word? in
            guard let word = Word(dictionary: dict) else { return nil }
            let sentenceId = word.contexts.first
            let sentence = sentenceId.flatMap { sentenceById[$0] }
            return word.withSentence(sentence)
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
