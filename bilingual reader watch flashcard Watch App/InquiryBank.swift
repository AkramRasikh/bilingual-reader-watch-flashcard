//
//  InquiryBank.swift
//  bilingual reader watch flashcard Watch App
//
//  Per-language dictated inquiries saved on the watch until Upload all.
//

import Foundation

struct BankedInquiry: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

@MainActor
final class InquiryBank: ObservableObject {
    @Published private(set) var byLanguage: [String: [BankedInquiry]] = [:]

    init() {
        byLanguage = InquiryBankStore.loadAll()
    }

    func inquiries(for language: String) -> [BankedInquiry] {
        byLanguage[language] ?? []
    }

    func add(_ text: String, language: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = inquiries(for: language)
        items.append(BankedInquiry(text: trimmed))
        store(items, language: language)
    }

    func update(id: UUID, text: String, language: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = inquiries(for: language)
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = trimmed
        store(items, language: language)
    }

    func remove(id: UUID, language: String) {
        let items = inquiries(for: language).filter { $0.id != id }
        store(items, language: language)
    }

    func replace(_ items: [BankedInquiry], language: String) {
        store(items, language: language)
    }

    private func store(_ items: [BankedInquiry], language: String) {
        byLanguage[language] = items
        InquiryBankStore.save(language: language, items: items)
    }
}

enum InquiryBankStore {
    private static let folderName = "inquiry-bank"

    static func loadAll() -> [String: [BankedInquiry]] {
        var result: [String: [BankedInquiry]] = [:]
        for language in OnLoadDataClient.knownLanguages {
            result[language] = load(language: language)
        }
        return result
    }

    static func load(language: String) -> [BankedInquiry] {
        guard let url = fileURL(for: language),
              let data = try? Data(contentsOf: url)
        else {
            return []
        }
        return (try? JSONDecoder().decode([BankedInquiry].self, from: data)) ?? []
    }

    static func save(language: String, items: [BankedInquiry]) {
        guard let url = fileURL(for: language) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if items.isEmpty {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                return
            }
            let data = try JSONEncoder().encode(items)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[InquiryBank] save \(language) failed: \(error)")
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
            .appendingPathComponent("\(language).json", isDirectory: false)
    }
}
