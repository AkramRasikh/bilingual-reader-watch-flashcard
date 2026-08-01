//
//  LocalWordStore.swift
//  bilingual reader watch flashcard Watch App
//
//  watchOS equivalent of web localStorage for per-language word caches.
//

import Foundation

enum LocalWordStore {
    private static let folderName = "word-cache"

    static func load(language: String) -> LanguageBundle? {
        guard let url = fileURL(for: language),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }

        do {
            var bundle = try JSONDecoder().decode(LanguageBundle.self, from: data)
            bundle.words = bundle.words.map { $0.withFreshDue() }.filter(\.isDue)
            return bundle.words.isEmpty ? nil : bundle
        } catch {
            print("[LocalWordStore] decode \(language) failed: \(error)")
            return nil
        }
    }

    static func save(language: String, bundle: LanguageBundle) {
        guard let url = fileURL(for: language) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(bundle)
            try data.write(to: url, options: [.atomic])
            print("[LocalWordStore] saved \(bundle.words.count) words / \(bundle.topics.count) topics for \(language)")
        } catch {
            print("[LocalWordStore] save \(language) failed: \(error)")
        }
    }

    static func loadAll() -> [String: LanguageBundle] {
        var result: [String: LanguageBundle] = [:]
        for language in OnLoadDataClient.knownLanguages {
            if let bundle = load(language: language) {
                result[language] = bundle
            }
        }
        return result
    }

    private static func fileURL(for language: String) -> URL? {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        // New format (words + topics). Old `{language}-words.json` is ignored.
        return root
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("\(language)-bundle.json", isDirectory: false)
    }
}
