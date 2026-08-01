//
//  LocalWordStore.swift
//  bilingual reader watch flashcard Watch App
//
//  watchOS equivalent of web localStorage for per-language word caches.
//

import Foundation

enum LocalWordStore {
    private static let folderName = "word-cache"

    static func load(language: String) -> [Word]? {
        guard let url = fileURL(for: language),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }

        do {
            let words = try JSONDecoder().decode([Word].self, from: data)
            let fresh = words.map { $0.withFreshDue() }.filter(\.isDue)
            return fresh.isEmpty ? nil : fresh
        } catch {
            print("[LocalWordStore] decode \(language) failed: \(error)")
            return nil
        }
    }

    static func save(language: String, words: [Word]) {
        guard let url = fileURL(for: language) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(words)
            try data.write(to: url, options: [.atomic])
            print("[LocalWordStore] saved \(words.count) words for \(language)")
        } catch {
            print("[LocalWordStore] save \(language) failed: \(error)")
        }
    }

    static func loadAll() -> [String: [Word]] {
        var result: [String: [Word]] = [:]
        for language in OnLoadDataClient.knownLanguages {
            if let words = load(language: language) {
                result[language] = words
            }
        }
        return result
    }

    static func saveAll(_ wordsByLanguage: [String: [Word]]) {
        for (language, words) in wordsByLanguage {
            save(language: language, words: words)
        }
    }

    private static func fileURL(for language: String) -> URL? {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return root
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("\(language)-words.json", isDirectory: false)
    }
}
