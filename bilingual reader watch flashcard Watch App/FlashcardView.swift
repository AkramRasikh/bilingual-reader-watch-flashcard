//
//  FlashcardView.swift
//  bilingual reader watch flashcard Watch App
//

import SwiftUI
import FSRS

struct FlashcardView: View {
    let word: Word

    @Environment(\.dismiss) private var dismiss

    @State private var isRevealed = false
    @State private var formsPage = 0
    @State private var actionsPage = 0
    @State private var expandedText: ExpandedText?
    @State private var gradeLabels: [Rating: String] = [:]

    private let gradeButtons: [Rating] = [.again, .hard, .good, .easy]

    var body: some View {
        VStack(spacing: 4) {
            // Compact back + definition, pinned high
            HStack(alignment: .top, spacing: 4) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .frame(width: 14, height: 14)
                .padding(.top, 1)

                Text(word.definition)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onLongPressGesture {
                        expandedText = ExpandedText(
                            title: "Definition",
                            body: word.definition
                        )
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Middle — content-sized; real blur clipped to this block only
            formsSection
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .drawingGroup()
                .blur(radius: isRevealed ? 0 : 5)
                .padding(5) // keep blur soft-edge inside the mask
                .mask(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .animation(.easeInOut(duration: 0.15), value: isRevealed)
                .contentShape(Rectangle())
                .gesture(formsSwipeGesture)
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

            Spacer(minLength: 0)

            // Bottom — swipe between SRS grades and delete (no TabView; labels update reliably)
            Group {
                if actionsPage == 0 {
                    HStack(spacing: 4) {
                        ForEach(gradeButtons, id: \.self) { rating in
                            Button {
                                print("[vocab SRS] \(rating.stringValue) -> \(gradeLabels[rating] ?? "?")")
                            } label: {
                                Text(gradeLabels[rating] ?? "…")
                                    .font(.system(size: 10).weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    Button {
                        print("[vocab SRS] delete word \(word.id)")
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14).weight(.semibold))
                            .foregroundStyle(Color(red: 0.85, green: 0.65, blue: 0.13))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.85, green: 0.65, blue: 0.13))
                }
            }
            .frame(height: 36)
            .gesture(actionsSwipeGesture)
            .background(.background)
        }
        .padding(.horizontal, 0)
        .padding(.top, -2)
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
        .task(id: word.id) {
            await computeNextReviews()
        }
    }

    private var formsPageCount: Int {
        word.sentence == nil ? 2 : 3
    }

    private var formsSection: some View {
        Group {
            switch formsPage {
            case 0:
                primaryFormsPage
            case 1:
                detailFormsPage
            default:
                sentenceContextPage
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.15), value: formsPage)
    }

    private var formsSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > abs(value.translation.height) else { return }

                if horizontal < 0, formsPage < formsPageCount - 1 {
                    formsPage += 1
                } else if horizontal > 0, formsPage > 0 {
                    formsPage -= 1
                }
            }
    }

    private var actionsSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > abs(value.translation.height) else { return }

                if horizontal < 0 {
                    actionsPage = 1
                } else if horizontal > 0 {
                    actionsPage = 0
                }
            }
    }

    @MainActor
    private func computeNextReviews() async {
        guard let card = word.card else {
            print("[vocab SRS] no reviewData/card for word \(word.id)")
            gradeLabels = Dictionary(uniqueKeysWithValues: gradeButtons.map { ($0, "—") })
            return
        }

        let now = Date()
        print("[vocab SRS] current due = \(card.due)")

        do {
            let options = try VocabSRS.nextReviewOptions(card: card, now: now)
            var labels: [Rating: String] = [:]
            for rating in gradeButtons {
                if let due = options[rating] {
                    let label = VocabSRS.relativeLabel(from: now, to: due)
                    labels[rating] = label
                    print("[vocab SRS] \(rating.stringValue) -> \(due) (\(label))")
                } else {
                    labels[rating] = "—"
                }
            }
            gradeLabels = labels
        } catch {
            print("[vocab SRS] failed to schedule: \(error)")
            gradeLabels = Dictionary(uniqueKeysWithValues: gradeButtons.map { ($0, "—") })
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
        .frame(maxWidth: .infinity)
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
        .frame(maxWidth: .infinity)
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
        .frame(maxWidth: .infinity)
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

private extension Rating {
    var stringValue: String {
        switch self {
        case .manual: return "manual"
        case .again: return "again"
        case .hard: return "hard"
        case .good: return "good"
        case .easy: return "easy"
        }
    }
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
            "reviewData": [
                "due": "2026-03-24T05:00:00.000Z",
                "stability": 105.3,
                "difficulty": 6.16,
                "elapsed_days": 13,
                "scheduled_days": 19,
                "reps": 7,
                "lapses": 0,
                "state": 2,
                "last_review": "2026-03-05T19:22:31.875Z",
            ],
        ], sentence: SentenceContext(
            targetLang: "是我们的荣幸",
            baseLang: "It's our honor"
        ))!
    )
}
