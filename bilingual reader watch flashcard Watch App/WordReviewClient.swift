//
//  WordReviewClient.swift
//  bilingual reader watch flashcard Watch App
//
//  Mirrors web WordCard → updateWordDataProvider / handleDeleteWordDataProvider.
//

import Foundation
import FSRS

enum WordReviewClient {
    /// POST updateWord — same body as web `/api/updateWord`.
    static func updateReviewData(
        wordId: String,
        language: String,
        card: Card
    ) async throws {
        let formatted = VocabSRS.cardForPersist(card)
        let body: [String: Any] = [
            "id": wordId,
            "language": language,
            "fieldToUpdate": [
                "reviewData": VocabSRS.reviewDataDictionary(from: formatted),
            ],
        ]
        try await postJSON(url: GeneratedEnv.updateWordURL, body: body)
    }

    /// POST deleteWord — same as web vocab trash (`isRemoveReview: true`).
    static func deleteWord(wordId: String, language: String) async throws {
        let body: [String: Any] = [
            "id": wordId,
            "language": language,
        ]
        try await postJSON(url: GeneratedEnv.deleteWordURL, body: body)
    }

    private static func postJSON(url: URL, body: [String: Any]) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            print("[WordReviewClient] \(url.lastPathComponent) failed: \(message)")
            throw URLError(.badServerResponse)
        }
    }
}
