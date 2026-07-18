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

    /// Fetches words for each language and returns `data[language].words`.
    static func fetchWordsByLanguage() async throws -> [String: [Word]] {
        var result: [String: [Word]] = [:]

        try await withThrowingTaskGroup(of: (String, [Word]?).self) { group in
            for language in knownLanguages {
                group.addTask {
                    let words = try await fetchWords(language: language)
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

    private static func fetchWords(language: String) async throws -> [Word]? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "language": language,
            "refs": ["words"],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            print("[getOnLoadData] \(language) HTTP \(http.statusCode)")
            return nil
        }

        // Response shape: [{ "words": [ word0, word1, ... ] }]
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let rawWords = root.first?["words"] as? [[String: Any]]
        else {
            return nil
        }

        return rawWords.compactMap(Word.init(dictionary:))
    }
}
