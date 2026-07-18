//
//  Word.swift
//  bilingual reader watch flashcard Watch App
//

import Foundation

struct SentenceContext: Hashable {
    let targetLang: String
    let baseLang: String
}

struct Word: Identifiable, Hashable {
    let id: String
    let definition: String
    let baseForm: String
    let surfaceForm: String
    let transliteration: String
    let mnemonic: String?
    /// First entry is the sentence id used to look up content (same as web `contexts[0]`).
    let contexts: [String]
    /// Sentence resolved from `contexts[0]` via content data.
    let sentence: SentenceContext?

    init?(dictionary: [String: Any], sentence: SentenceContext? = nil) {
        let id = dictionary["id"] as? String ?? UUID().uuidString
        let definition = dictionary["definition"] as? String ?? ""
        let baseForm = dictionary["baseForm"] as? String ?? ""
        let surfaceForm = dictionary["surfaceForm"] as? String ?? ""
        let transliteration = (dictionary["transliteration"] as? String)
            ?? (dictionary["phonetic"] as? String)
            ?? ""
        let mnemonic = dictionary["mnemonic"] as? String
        let contexts = dictionary["contexts"] as? [String] ?? []

        guard !definition.isEmpty || !baseForm.isEmpty || !surfaceForm.isEmpty else {
            return nil
        }

        self.id = id
        self.definition = definition.isEmpty ? "(no definition)" : definition
        self.baseForm = baseForm
        self.surfaceForm = surfaceForm
        self.transliteration = transliteration
        self.mnemonic = mnemonic?.isEmpty == false ? mnemonic : nil
        self.contexts = contexts
        self.sentence = sentence
    }

    func withSentence(_ sentence: SentenceContext?) -> Word {
        Word(
            id: id,
            definition: definition,
            baseForm: baseForm,
            surfaceForm: surfaceForm,
            transliteration: transliteration,
            mnemonic: mnemonic,
            contexts: contexts,
            sentence: sentence
        )
    }

    private init(
        id: String,
        definition: String,
        baseForm: String,
        surfaceForm: String,
        transliteration: String,
        mnemonic: String?,
        contexts: [String],
        sentence: SentenceContext?
    ) {
        self.id = id
        self.definition = definition
        self.baseForm = baseForm
        self.surfaceForm = surfaceForm
        self.transliteration = transliteration
        self.mnemonic = mnemonic
        self.contexts = contexts
        self.sentence = sentence
    }
}
