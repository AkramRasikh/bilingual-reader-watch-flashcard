//
//  SentenceFlashcardView.swift
//  bilingual reader watch flashcard Watch App
//
//  One due sentence per screen. Target text by default; swipe right for English.
//  Trash is removeReview (web updateSentence), not delete.
//

import SwiftUI
import FSRS

struct SentenceFlashcardView: View {
    let sentence: ReviewableSentence
    var language: String = ""
    var remainingDue: Int = 0
    var totalInReview: Int = 0
    var onBack: () -> Void = {}
    var onReviewed: (String, Card) -> Void = { _, _ in }
    var onRemovedReview: (String) -> Void = { _ in }

    @ObservedObject private var audioPlayer = WordAudioPlayer.shared
    @ObservedObject private var audioLibrary = AudioLibrary.shared
    @State private var showsEnglish = false
    @State private var actionsPage = 0
    @State private var expandedText: SentenceExpandedText?
    @State private var gradeLabels: [Rating: String] = [:]
    @State private var nextCards: [Rating: Card] = [:]
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let gradeButtons: [Rating] = [.again, .hard, .good, .easy]

    private var isAudioPlaying: Bool {
        audioPlayer.isPlaying
    }

    private var isLocalAudio: Bool {
        _ = audioLibrary.generation
        guard let fileName = sentence.audioFileName else { return false }
        return AudioFileStore.hasFile(language: language, fileName: fileName)
    }

    private var previousDisplayedText: String? {
        let text = showsEnglish ? sentence.previousBaseLang : sentence.previousTargetLang
        return text.isEmpty ? nil : text
    }

    private var currentDisplayedText: String {
        if showsEnglish {
            return sentence.baseLang.isEmpty ? "(no translation)" : sentence.baseLang
        }
        return sentence.targetLang.isEmpty ? "(no sentence)" : sentence.targetLang
    }

    private var nextDisplayedText: String? {
        let text = showsEnglish ? sentence.nextBaseLang : sentence.nextTargetLang
        return text.isEmpty ? nil : text
    }

    @ViewBuilder
    private var sentenceBody: some View {
        VStack(alignment: .center, spacing: 3) {
            if let previous = previousDisplayedText {
                Text(previous)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.pink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Text(currentDisplayedText)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            if let next = nextDisplayedText {
                Text(next)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var expandedBody: String {
        var lines: [String] = []
        if let previous = previousDisplayedText {
            lines.append(previous)
        }
        lines.append(currentDisplayedText)
        if let next = nextDisplayedText {
            lines.append(next)
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text("\(remainingDue)/\(max(totalInReview, remainingDue))")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                    .accessibilityLabel("\(remainingDue) of \(max(totalInReview, remainingDue)) sentences due")

                if sentence.canPlayAudio {
                    VStack(spacing: 0) {
                        Button {
                            guard let fileName = sentence.audioFileName else { return }
                            if isAudioPlaying {
                                audioPlayer.stop()
                            } else {
                                audioPlayer.toggle(
                                    fileName: fileName,
                                    language: language,
                                    cue: sentence.audioCue
                                )
                            }
                        } label: {
                            Image(systemName: isAudioPlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 28, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isAudioPlaying ? "Stop" : "Play")

                        Text(isLocalAudio ? "Local" : "Streaming")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            sentenceBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .gesture(languageSwipeGesture)
                .onLongPressGesture {
                    expandedText = SentenceExpandedText(
                        title: showsEnglish ? "English" : "Sentence",
                        body: expandedBody
                    )
                }
                .opacity(isSubmitting ? 0.45 : 1)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Group {
                if actionsPage == 0 {
                    HStack(spacing: 4) {
                        ForEach(gradeButtons, id: \.self) { rating in
                            Button {
                                Task { await submitGrade(rating) }
                            } label: {
                                Text(gradeLabels[rating] ?? "…")
                                    .font(.system(size: 10).weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSubmitting || nextCards[rating] == nil)
                        }
                    }
                } else {
                    Button {
                        Task { await submitRemoveReview() }
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14).weight(.semibold))
                            .foregroundStyle(Color(red: 0.85, green: 0.65, blue: 0.13))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.85, green: 0.65, blue: 0.13))
                    .disabled(isSubmitting)
                }
            }
            .frame(height: 36)
            .gesture(actionsSwipeGesture)
            .background(.background)
            .opacity(isSubmitting ? 0.45 : 1)
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
        .task(id: sentence.id) {
            showsEnglish = false
            actionsPage = 0
            errorMessage = nil
            await computeNextReviews()
        }
    }

    private var languageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > abs(value.translation.height) else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    showsEnglish = horizontal > 0
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
        guard let card = sentence.card else {
            print("[sentence SRS] no reviewData/card for sentence \(sentence.id)")
            gradeLabels = Dictionary(uniqueKeysWithValues: gradeButtons.map { ($0, "—") })
            nextCards = [:]
            return
        }

        let now = Date()
        print("[sentence SRS] current due = \(card.due)")

        do {
            let cards = try VocabSRS.nextReviewCards(card: card, now: now, contentType: .sentences)
            nextCards = cards
            var labels: [Rating: String] = [:]
            for rating in gradeButtons {
                if let card = cards[rating] {
                    let persistDue = VocabSRS.cardForPersist(card, now: now).due
                    let label = VocabSRS.relativeLabel(from: now, to: persistDue)
                    labels[rating] = label
                    print("[sentence SRS] \(rating.stringValue) -> \(persistDue) (\(label))")
                } else {
                    labels[rating] = "—"
                }
            }
            gradeLabels = labels
        } catch {
            print("[sentence SRS] failed to schedule: \(error)")
            gradeLabels = Dictionary(uniqueKeysWithValues: gradeButtons.map { ($0, "—") })
            nextCards = [:]
        }
    }

    @MainActor
    private func submitGrade(_ rating: Rating) async {
        guard !isSubmitting, let next = nextCards[rating] else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let persisted = VocabSRS.cardForPersist(next)
            try await WordReviewClient.updateSentenceReviewData(
                sentenceId: sentence.id,
                language: language,
                contentId: sentence.contentId,
                card: next
            )
            print("[sentence SRS] saved \(rating.stringValue) for \(sentence.id)")
            onReviewed(sentence.id, persisted)
        } catch {
            print("[sentence SRS] update failed: \(error)")
            errorMessage = "Save failed"
        }
    }

    @MainActor
    private func submitRemoveReview() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await WordReviewClient.removeSentenceReview(
                sentenceId: sentence.id,
                language: language,
                contentId: sentence.contentId
            )
            print("[sentence SRS] removed review \(sentence.id)")
            onRemovedReview(sentence.id)
        } catch {
            print("[sentence SRS] remove review failed: \(error)")
            errorMessage = "Remove failed"
        }
    }
}

private struct SentenceExpandedText: Identifiable {
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
    SentenceFlashcardView(
        sentence: ReviewableSentence(
            dictionary: [
                "id": "preview-sentence",
                "targetLang": "是我们的荣幸，能够在这里见到各位来宾，并一起庆祝这个特别的日子。",
                "baseLang": "It's our honor to meet all of you here and celebrate this special day together.",
                "time": 12.5,
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
            ],
            contentId: "preview-content",
            audioFileName: "Preview Topic",
            previous: (
                targetLang: "他刚才说了什么？",
                baseLang: "What did he just say?"
            ),
            next: (
                targetLang: "请跟我来。",
                baseLang: "Please come with me."
            )
        )!,
        language: "chinese",
        remainingDue: 3,
        totalInReview: 12
    )
}
