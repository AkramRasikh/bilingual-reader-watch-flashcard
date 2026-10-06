//
//  SnippetFocus.swift
//  bilingual reader watch flashcard Watch App
//
//  Focus window inside a snippet's targetLang. Mirrors web
//  highlightSnippetTextApprox + SnippetReview boundary moves.
//  Chinese and Japanese step one character; other languages step one word.
//

import SwiftUI

/// Same rotating palette as web `getColorByIndex`.
enum SnippetWordColor {
    static let palette: [Color] = [
        Color(red: 31 / 255, green: 119 / 255, blue: 180 / 255),
        Color(red: 255 / 255, green: 127 / 255, blue: 14 / 255),
        Color(red: 44 / 255, green: 160 / 255, blue: 44 / 255),
        Color(red: 214 / 255, green: 39 / 255, blue: 40 / 255),
        Color(red: 148 / 255, green: 103 / 255, blue: 189 / 255),
        Color(red: 140 / 255, green: 86 / 255, blue: 75 / 255),
        Color(red: 227 / 255, green: 119 / 255, blue: 194 / 255),
        Color(red: 127 / 255, green: 127 / 255, blue: 127 / 255),
        Color(red: 188 / 255, green: 189 / 255, blue: 34 / 255),
        Color(red: 23 / 255, green: 190 / 255, blue: 207 / 255),
    ]

    static func color(at index: Int) -> Color {
        palette[index % palette.count]
    }
}

struct SnippetTextRun: Identifiable, Equatable {
    let id: Int
    /// First character index of this word occurrence. Parts split by the focus edge share it.
    let wordID: Int
    let text: String
    let wordIndex: Int?
    let meaning: String?
    let surfaceForm: String?
    let sentenceId: String?
    let sentenceText: String?
    let sentenceTime: TimeInterval?
    let insideFocus: Bool
}

enum SnippetBreakdown {
    /// Longer surface forms win. Unmatched characters stay uncolored.
    static func runs(
        text: String,
        vocab: [BreakdownWord],
        matchStart: Int,
        matchEnd: Int
    ) -> [SnippetTextRun] {
        let chars = Array(text)
        guard !chars.isEmpty else { return [] }
        let marks = marks(in: chars, vocab: vocab)
        var runs: [SnippetTextRun] = []
        var index = 0
        while index < chars.count {
            let mark = marks[index]
            let inside = index >= matchStart && index < matchEnd
            var end = index + 1
            while end < chars.count {
                let nextInside = end >= matchStart && end < matchEnd
                if marks[end]?.origin != mark?.origin || nextInside != inside {
                    break
                }
                end += 1
            }
            runs.append(
                SnippetTextRun(
                    id: runs.count,
                    wordID: mark?.origin ?? index,
                    text: String(chars[index..<end]),
                    wordIndex: mark?.wordIndex,
                    meaning: mark?.meaning,
                    surfaceForm: mark?.surfaceForm,
                    sentenceId: mark?.sentenceId,
                    sentenceText: mark?.sentenceText,
                    sentenceTime: mark?.sentenceTime,
                    insideFocus: inside
                )
            )
            index = end
        }
        return runs
    }

    private struct Mark {
        let wordIndex: Int
        let origin: Int
        let meaning: String
        let surfaceForm: String
        let sentenceId: String
        let sentenceText: String
        let sentenceTime: TimeInterval
    }

    private static func marks(in chars: [Character], vocab: [BreakdownWord]) -> [Mark?] {
        var marks = [Mark?](repeating: nil, count: chars.count)
        let ordered = vocab.enumerated().sorted {
            $0.element.surfaceForm.count > $1.element.surfaceForm.count
        }
        for (wordIndex, word) in ordered {
            let needle = Array(word.surfaceForm)
            guard !needle.isEmpty, needle.count <= chars.count else { continue }
            var cursor = 0
            while cursor + needle.count <= chars.count {
                let end = cursor + needle.count
                let free = (cursor..<end).allSatisfy { marks[$0] == nil }
                if free, Array(chars[cursor..<end]) == needle {
                    for offset in 0..<needle.count {
                        marks[cursor + offset] = Mark(
                            wordIndex: wordIndex,
                            origin: cursor,
                            meaning: word.meaning,
                            surfaceForm: word.surfaceForm,
                            sentenceId: word.sentenceId,
                            sentenceText: word.sentenceText,
                            sentenceTime: word.sentenceTime
                        )
                    }
                    cursor = end
                } else {
                    cursor += 1
                }
            }
        }
        return marks
    }
}

struct SnippetFocus: Equatable {
    let fullText: String
    let query: String
    let trimmed: Bool
    var startOffset: Int
    var lengthAdjustment: Int

    private var characters: [Character] { Array(fullText) }
    private var queryCharacters: [Character] { Array(query) }

    var suggestedStart: Int {
        Self.findApproxIndex(in: characters, query: queryCharacters)
    }

    var canAdjust: Bool {
        suggestedStart >= 0 && !queryCharacters.isEmpty
    }

    var hasChanged: Bool {
        startOffset != 0 || lengthAdjustment != 0
    }

    /// Inclusive start of the focus span.
    var matchStart: Int {
        let start = suggestedStart
        guard start >= 0, !queryCharacters.isEmpty else { return 0 }
        return clamp(start + startOffset, min: 0, max: characters.count)
    }

    /// Exclusive end of the focus span.
    var matchEnd: Int {
        guard canAdjust else { return characters.count }
        let raw = matchStart + queryCharacters.count + lengthAdjustment
        return clamp(raw, min: matchStart, max: characters.count)
    }

    var textMatch: String {
        guard canAdjust else { return fullText }
        return String(characters[matchStart..<matchEnd])
    }

    var displayText: AttributedString {
        let chars = characters
        guard canAdjust else {
            return fullOpacity(String(chars))
        }
        guard matchStart < matchEnd else {
            return faded(String(chars))
        }
        var result = AttributedString()
        result.append(faded(String(chars[0..<matchStart])))
        result.append(fullOpacity(String(chars[matchStart..<matchEnd])))
        result.append(faded(String(chars[matchEnd..<chars.count])))
        return result
    }

    mutating func moveLeft() {
        guard canAdjust, matchStart > 0 else { return }
        if trimmed {
            startOffset -= 1
            return
        }
        var cursor = matchStart - 1
        while cursor >= 0 && characters[cursor].isWhitespace {
            cursor -= 1
        }
        while cursor >= 0 && !characters[cursor].isWhitespace {
            cursor -= 1
        }
        let previousWordStart = max(0, cursor + 1)
        startOffset = previousWordStart - suggestedStart
    }

    mutating func moveRight() {
        guard canAdjust, matchEnd < characters.count else { return }
        if trimmed {
            guard matchStart < characters.count - 1 else { return }
            startOffset += 1
            return
        }
        var cursor = matchStart + 1
        while cursor < characters.count && !characters[cursor].isWhitespace {
            cursor += 1
        }
        while cursor < characters.count && characters[cursor].isWhitespace {
            cursor += 1
        }
        let nextWordStart = min(cursor, characters.count - 1)
        guard nextWordStart != matchStart else { return }
        startOffset = nextWordStart - suggestedStart
    }

    mutating func expand() {
        guard canAdjust, matchEnd < characters.count else { return }
        if trimmed {
            lengthAdjustment += 1
            return
        }
        var cursor = matchEnd
        while cursor < characters.count && characters[cursor].isWhitespace {
            cursor += 1
        }
        while cursor < characters.count && !characters[cursor].isWhitespace {
            cursor += 1
        }
        let delta = cursor - matchEnd
        guard delta > 0 else { return }
        lengthAdjustment += delta
    }

    mutating func contract() {
        guard canAdjust, matchEnd - matchStart >= 1 else { return }
        if trimmed {
            lengthAdjustment -= 1
            return
        }
        var cursor = matchEnd - 1
        while cursor >= matchStart && characters[cursor].isWhitespace {
            cursor -= 1
        }
        while cursor >= matchStart && !characters[cursor].isWhitespace {
            cursor -= 1
        }
        let previousWordStart = max(matchStart + 1, cursor + 1)
        let delta = previousWordStart - matchEnd
        guard delta < 0 else { return }
        lengthAdjustment += delta
    }

    mutating func reset() {
        startOffset = 0
        lengthAdjustment = 0
    }

    static func isTrimmedLanguage(_ language: String) -> Bool {
        language == "chinese" || language == "japanese"
    }

    /// Exact substring, otherwise a sliding-window score above 0.4. `-1` when nothing fits.
    static func findApproxIndex(in text: [Character], query: [Character]) -> Int {
        guard !query.isEmpty, query.count <= text.count else { return -1 }
        if let exact = indexOf(query, in: text) {
            return exact
        }

        var bestIndex = 0
        var bestScore = 0.0
        let last = text.count - query.count
        for index in 0...last {
            var matches = 0
            for offset in 0..<query.count where text[index + offset] == query[offset] {
                matches += 1
            }
            let score = Double(matches) / Double(query.count)
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return bestScore > 0.4 ? bestIndex : -1
    }

    private static func indexOf(_ query: [Character], in text: [Character]) -> Int? {
        guard !query.isEmpty, query.count <= text.count else { return nil }
        let last = text.count - query.count
        for index in 0...last {
            if Array(text[index..<(index + query.count)]) == query {
                return index
            }
        }
        return nil
    }

    private func clamp(_ value: Int, min lower: Int, max upper: Int) -> Int {
        Swift.min(upper, Swift.max(lower, value))
    }

    private func fullOpacity(_ text: String) -> AttributedString {
        var string = AttributedString(text)
        string.foregroundColor = .white
        string.font = .system(size: 15, weight: .bold)
        return string
    }

    private func faded(_ text: String) -> AttributedString {
        var string = AttributedString(text)
        string.foregroundColor = .white.opacity(0.35)
        string.font = .system(size: 15, weight: .medium)
        return string
    }
}
