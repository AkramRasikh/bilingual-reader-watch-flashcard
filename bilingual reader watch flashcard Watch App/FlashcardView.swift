//
//  FlashcardView.swift
//  bilingual reader watch flashcard Watch App
//

import SwiftUI

struct FlashcardView: View {
    let word: Word

    @State private var isRevealed = false
    @State private var formsPage = 0
    @State private var expandedText: ExpandedText?

    var body: some View {
        VStack(spacing: 6) {
            // Topic — definition
            Text(word.definition)
                .font(.caption2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onLongPressGesture {
                    expandedText = ExpandedText(
                        title: "Definition",
                        body: word.definition
                    )
                }

            Spacer(minLength: 2)

            // Middle — swipe for forms / details / sentence; tap to reveal
            TabView(selection: $formsPage) {
                primaryFormsPage
                    .tag(0)

                detailFormsPage
                    .tag(1)

                if word.sentence != nil {
                    sentenceContextPage
                        .tag(2)
                }
            }
            .tabViewStyle(.page)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .blur(radius: isRevealed ? 0 : 8)
            .animation(.easeInOut(duration: 0.2), value: isRevealed)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                isRevealed.toggle()
            }
            .onTapGesture(count: 1) {
                isRevealed = true
            }
            .onLongPressGesture {
                guard isRevealed else { return }
                expandedText = ExpandedText(
                    title: expandedTitle(for: formsPage),
                    body: expandedBody(for: formsPage)
                )
            }
            .accessibilityLabel(isRevealed ? "Answer revealed" : "Answer hidden, tap to reveal")

            Spacer(minLength: 2)

            // Bottom — placeholder multiple-choice
            HStack(spacing: 4) {
                ForEach(["A", "B", "C", "D"], id: \.self) { option in
                    Button(option) {}
                        .buttonStyle(.bordered)
                        .font(.caption2)
                }
            }
        }
        .padding(.horizontal, 2)
        .sheet(item: $expandedText) { item in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                    Text(item.body)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
        }
    }

    private var primaryFormsPage: some View {
        VStack(spacing: 2) {
            if !word.surfaceForm.isEmpty {
                Text(word.surfaceForm)
                    .font(.headline)
                    .lineLimit(2)
            }
            if !word.baseForm.isEmpty, word.baseForm != word.surfaceForm {
                Text(word.baseForm)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailFormsPage: some View {
        VStack(spacing: 2) {
            if !word.surfaceForm.isEmpty {
                Text(word.surfaceForm)
                    .font(.headline)
                    .lineLimit(1)
            }
            if !word.transliteration.isEmpty {
                Text(word.transliteration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let mnemonic = word.mnemonic {
                Text(mnemonic)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sentenceContextPage: some View {
        VStack(spacing: 2) {
            if let targetLang = word.sentence?.targetLang, !targetLang.isEmpty {
                Text(targetLang)
                    .font(.headline)
                    .lineLimit(2)
            }
            if let baseLang = word.sentence?.baseLang, !baseLang.isEmpty {
                Text(baseLang)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func expandedTitle(for page: Int) -> String {
        switch page {
        case 0: return "Forms"
        case 1: return "Details"
        default: return "Sentence"
        }
    }

    private func expandedBody(for page: Int) -> String {
        switch page {
        case 0: return primaryFormsFullText
        case 1: return detailFormsFullText
        default: return sentenceContextFullText
        }
    }

    private var primaryFormsFullText: String {
        var lines: [String] = []
        if !word.surfaceForm.isEmpty { lines.append(word.surfaceForm) }
        if !word.baseForm.isEmpty, word.baseForm != word.surfaceForm {
            lines.append(word.baseForm)
        }
        return lines.joined(separator: "\n")
    }

    private var detailFormsFullText: String {
        var lines: [String] = []
        if !word.surfaceForm.isEmpty { lines.append(word.surfaceForm) }
        if !word.transliteration.isEmpty { lines.append(word.transliteration) }
        if let mnemonic = word.mnemonic { lines.append(mnemonic) }
        return lines.joined(separator: "\n")
    }

    private var sentenceContextFullText: String {
        var lines: [String] = []
        if let targetLang = word.sentence?.targetLang, !targetLang.isEmpty {
            lines.append(targetLang)
        }
        if let baseLang = word.sentence?.baseLang, !baseLang.isEmpty {
            lines.append(baseLang)
        }
        return lines.joined(separator: "\n")
    }
}

private struct ExpandedText: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

#Preview {
    FlashcardView(
        word: Word(dictionary: [
            "id": "preview",
            "definition": "Our honor — a longer definition that would normally get truncated on the watch face",
            "baseForm": "我们的荣幸",
            "surfaceForm": "我们的荣幸",
            "transliteration": "wǒ men de róng xìng",
            "mnemonic": "Think of a royal honor ceremony with a long mnemonic explanation",
            "contexts": ["preview-sentence"],
        ], sentence: SentenceContext(
            targetLang: "是我们的荣幸",
            baseLang: "It's our honor"
        ))!
    )
}
