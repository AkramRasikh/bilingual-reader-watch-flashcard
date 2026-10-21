//
//  WordReviewClient.swift
//  bilingual reader watch flashcard Watch App
//
//  Mirrors web WordCard → updateWordDataProvider / handleDeleteWordDataProvider.
//

import Foundation
import FSRS

enum ReviewClientError: LocalizedError {
    case alreadyExists
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyExists:
            return "Word already exists"
        case .failed(let message):
            return message
        }
    }
}

enum ImprovBatchItem {
    case word(Word)
    case failed(String)
}

enum WordReviewClient {
    /// POST updateWord — same body as web `/api/updateWord`.
    static func updateReviewData(
        wordId: String,
        language: String,
        card: Card,
        timeout: TimeInterval = 60
    ) async throws {
        let formatted = VocabSRS.cardForPersist(card)
        let body: [String: Any] = [
            "id": wordId,
            "language": language,
            "fieldToUpdate": [
                "reviewData": VocabSRS.reviewDataDictionary(from: formatted),
            ],
        ]
        try await postJSON(url: GeneratedEnv.updateWordURL, body: body, timeout: timeout)
    }

    /// POST updateSentence — same body as web `/api/updateSentence`.
    static func updateSentenceReviewData(
        sentenceId: String,
        language: String,
        contentId: String,
        card: Card
    ) async throws {
        let formatted = VocabSRS.cardForPersist(card)
        let body: [String: Any] = [
            "language": language,
            "indexKey": contentId,
            "id": sentenceId,
            "fieldToUpdate": [
                "reviewData": VocabSRS.reviewDataDictionary(from: formatted),
            ],
        ]
        try await postJSON(url: GeneratedEnv.updateSentenceURL, body: body)
    }

    /// POST updateSentence with `{ removeReview: true }` — strips review, keeps the sentence.
    static func removeSentenceReview(
        sentenceId: String,
        language: String,
        contentId: String
    ) async throws {
        let body: [String: Any] = [
            "language": language,
            "indexKey": contentId,
            "id": sentenceId,
            "fieldToUpdate": [
                "removeReview": true,
            ],
        ]
        print("[WordReviewClient] removeSentenceReview \(body)")
        try await postJSON(url: GeneratedEnv.updateSentenceURL, body: body)
    }

    /// POST deleteWord — same as web vocab trash (`isRemoveReview: true`).
    static func deleteWord(
        wordId: String,
        language: String,
        additionalContext: [String] = [],
        timeout: TimeInterval = 60
    ) async throws {
        var body: [String: Any] = [
            "id": wordId,
            "language": language,
        ]
        if !additionalContext.isEmpty {
            body["additionalContext"] = additionalContext
        }
        print("[WordReviewClient] deleteWord \(body)")
        try await postJSON(url: GeneratedEnv.deleteWordURL, body: body, timeout: timeout)
    }

    /// POST addImprovWord — body `{ language, inquiry }`, 200 `{ word, sentence }`.
    static func addImprovWord(language: String, inquiry: String) async throws -> Word {
        let body: [String: Any] = [
            "language": language,
            "inquiry": inquiry,
        ]
        print("[WordReviewClient] addImprovWord language=\(language)")
        let (data, http) = try await postJSONReturning(
            url: GeneratedEnv.addImprovWordURL,
            body: body,
            timeout: 120
        )

        if http.statusCode == 409 {
            throw ReviewClientError.alreadyExists
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let message = serverMessage(from: data, status: http.statusCode)
            print("[WordReviewClient] addImprovWord failed: \(message)")
            throw ReviewClientError.failed(message)
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let word = wordFromImprovPayload(root)
        else {
            throw ReviewClientError.failed("Couldn’t parse word")
        }
        return word
    }

    /// POST addImprovWord — body `{ language, inquiries }`, 200 `{ results }`.
    static func addImprovWords(language: String, inquiries: [String]) async throws -> [ImprovBatchItem] {
        let body: [String: Any] = [
            "language": language,
            "inquiries": inquiries,
        ]
        let timeout = TimeInterval(max(120, inquiries.count * 120))
        print("[WordReviewClient] addImprovWords language=\(language) count=\(inquiries.count)")
        let (data, http) = try await postJSONReturning(
            url: GeneratedEnv.addImprovWordURL,
            body: body,
            timeout: timeout
        )
        guard (200 ... 299).contains(http.statusCode) else {
            let message = serverMessage(from: data, status: http.statusCode)
            print("[WordReviewClient] addImprovWords failed: \(message)")
            throw ReviewClientError.failed(message)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else {
            throw ReviewClientError.failed("Couldn’t parse results")
        }
        return results.map { entry in
            if let error = entry["error"] as? String, !error.isEmpty {
                return .failed(error)
            }
            if let word = wordFromImprovPayload(entry) {
                return .word(word)
            }
            return .failed("Couldn’t parse word")
        }
    }

    private static func wordFromImprovPayload(_ root: [String: Any]) -> Word? {
        guard let wordDict = root["word"] as? [String: Any],
              var word = Word(dictionary: wordDict)
        else {
            return nil
        }
        if let sentenceDict = root["sentence"] as? [String: Any] {
            let sentence = SentenceContext(
                targetLang: sentenceDict["targetLang"] as? String ?? "",
                baseLang: sentenceDict["baseLang"] as? String ?? "",
                time: nil
            )
            word = word.withSentence(sentence)
            if let sentenceId = (sentenceDict["id"] as? String) ?? word.contexts.first,
               !sentenceId.isEmpty
            {
                word = word.withAudio(fileName: sentenceId, playAt: 0)
            }
        } else if let sentenceId = word.contexts.first {
            word = word.withAudio(fileName: sentenceId, playAt: 0)
        }
        return word
    }

    private static func postJSON(url: URL, body: [String: Any], timeout: TimeInterval = 60) async throws {
        let (data, http) = try await postJSONReturning(url: url, body: body, timeout: timeout)
        guard (200 ... 299).contains(http.statusCode) else {
            let message = serverMessage(from: data, status: http.statusCode)
            print("[WordReviewClient] \(url.lastPathComponent) failed: \(message)")
            throw URLError(.badServerResponse)
        }
    }

    private static func postJSONReturning(
        url: URL,
        body: [String: Any],
        timeout: TimeInterval = 60
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private static func serverMessage(from data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String,
           !error.isEmpty
        {
            return error
        }
        return String(data: data, encoding: .utf8) ?? "HTTP \(status)"
    }
}
