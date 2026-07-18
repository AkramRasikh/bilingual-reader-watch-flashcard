//
//  Word.swift
//  bilingual reader watch flashcard Watch App
//

import Foundation

struct Word: Identifiable, Hashable {
    let id: String
    let definition: String
    let baseForm: String
    let surfaceForm: String
    let transliteration: String
    let mnemonic: String?

    init?(dictionary: [String: Any]) {
        let id = dictionary["id"] as? String ?? UUID().uuidString
        let definition = dictionary["definition"] as? String ?? ""
        let baseForm = dictionary["baseForm"] as? String ?? ""
        let surfaceForm = dictionary["surfaceForm"] as? String ?? ""
        let transliteration = (dictionary["transliteration"] as? String)
            ?? (dictionary["phonetic"] as? String)
            ?? ""
        let mnemonic = dictionary["mnemonic"] as? String

        guard !definition.isEmpty || !baseForm.isEmpty || !surfaceForm.isEmpty else {
            return nil
        }

        self.id = id
        self.definition = definition.isEmpty ? "(no definition)" : definition
        self.baseForm = baseForm
        self.surfaceForm = surfaceForm
        self.transliteration = transliteration
        self.mnemonic = mnemonic?.isEmpty == false ? mnemonic : nil
    }
}
