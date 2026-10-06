//
//  FlashcardView.swift
//  bilingual reader watch flashcard Watch App
//
//  One due word per screen. Definition starts in the center; swipe left for
//  the target-language form, then transliteration and sentence context.
//  Top bar matches sentence review: due/total, loop, slow, and right-edge play/stop.
//

import SwiftUI
import FSRS

struct FlashcardView: View {
    let word: Word
    var language: String = ""
    var remainingCount: Int = 0
    var totalInReview: Int = 0
    var adhocSentenceIds: [String] = []
    var onBack: () -> Void = {}
    var onReviewed: (String, Card) -> Void = { _, _ in }
    var onDeleted: (String) -> Void = { _ in }

    @ObservedObject private var audioPlayer = WordAudioPlayer.shared
    @ObservedObject private var audioLibrary = AudioLibrary.shared
    @State private var contentPage = 0
    @State private var actionsPage = 0
    @State private var expandedText: ExpandedText?
    @State private var gradeLabels: [Rating: String] = [:]
    @State private var nextCards: [Rating: Card] = [:]
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let gradeButtons: [Rating] = [.again, .hard, .good, .easy]

    private var dueLabel: String {
        "\(remainingCount)/\(max(totalInReview, remainingCount))"
    }

    private var isAudioPlaying: Bool {
        audioPlayer.isPlaying
    }

    private var isLocalAudio: Bool {
        _ = audioLibrary.generation
        guard let fileName = word.audioFileName else { return false }
        return AudioFileStore.hasFile(language: language, fileName: fileName)
    }

    /// Standalone clips start at 0 and loop the whole file. Topic cues loop a
    /// short span from the word so the rest of the article does not repeat.
    private var wordLoopWindow: (start: TimeInterval, end: TimeInterval?) {
        let duration = audioPlayer.clock.duration
        let fileDuration = duration > 0 ? duration : nil
        let cue = word.audioCue
        if cue <= 0.05 {
            return (0, fileDuration)
        }
        let end = cue + 4
        return (cue, fileDuration.map { min($0, end) } ?? end)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text(dueLabel)
                            .font(.system(size: 9, weight: .semibold))
                            .monospacedDigit()
                    }
                    .padding(.top, 6)
                    .frame(minWidth: 40, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Back, \(remainingCount) of \(max(totalInReview, remainingCount)) words due")

                if word.canPlayAudio {
                    HStack(alignment: .top, spacing: 12) {
                        Button {
                            let window = wordLoopWindow
                            print("[word loop] cue=\(word.audioCue) window=\(window.start)->\(window.end as Any)")
                            audioPlayer.toggleLoop(start: window.start, end: window.end)
                        } label: {
                            Image(systemName: "repeat")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 28, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(audioPlayer.isLooping ? .orange : .primary)
                        .accessibilityLabel(audioPlayer.isLooping ? "Stop looping" : "Loop word")
                        .accessibilityAddTraits(audioPlayer.isLooping ? .isSelected : [])

                        Button {
                            audioPlayer.toggleSlowRate()
                        } label: {
                            Text("0.75×")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(minWidth: 36, minHeight: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(audioPlayer.playbackRate < 1 ? .orange : .primary)
                        .accessibilityLabel(audioPlayer.playbackRate < 1 ? "Normal speed" : "Slow to 0.75")
                        .accessibilityAddTraits(audioPlayer.playbackRate < 1 ? .isSelected : [])

                        Image(systemName: isAudioPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isLocalAudio ? Color.green : Color.primary)
                            .frame(width: 22, height: 26, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .zIndex(10)
            .background(.background)
            .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    wordBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                        .gesture(formsSwipeGesture)
                        .onLongPressGesture {
                            expandedText = ExpandedText(
                                title: expandedTitle(for: currentFace),
                                body: expandedBody(for: currentFace)
                            )
                        }

                    if word.canPlayAudio {
                        Color.clear
                            .frame(width: geo.size.width * 0.25)
                            .frame(maxHeight: .infinity)
                            .overlay(alignment: .leading) {
                                PlaybackEdgeGuide()
                            }
                            .contentShape(Rectangle())
                            .gesture(playbackEdgeGesture)
                            .accessibilityLabel(isAudioPlaying ? "Stop" : "Play")
                            .accessibilityHint(isLocalAudio ? "Saved audio" : "Streaming audio")
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isSubmitting ? 0.45 : 1)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            // Bottom — swipe between SRS grades and delete (web ReviewSRSToggles)
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
                    ZStack {
                        Button {} label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14).weight(.semibold))
                                .foregroundStyle(Color(red: 0.85, green: 0.65, blue: 0.13))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color(red: 0.85, green: 0.65, blue: 0.13))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(trashPageGesture)
                            .accessibilityLabel("Delete")
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .frame(height: 36)
            .contentShape(Rectangle())
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
        .task(id: word.id) {
            contentPage = 0
            actionsPage = 0
            errorMessage = nil
            audioPlayer.stop()
            await computeNextReviews()
        }
    }

    private var faces: [WordReviewFace] {
        var pages: [WordReviewFace] = [.definition]
        if !word.surfaceForm.isEmpty || !word.baseForm.isEmpty {
            pages.append(.target)
        }
        if !word.transliteration.isEmpty || word.mnemonic != nil {
            pages.append(.details)
        }
        if let sentence = word.sentence,
           !sentence.targetLang.isEmpty || !sentence.baseLang.isEmpty
        {
            pages.append(.context)
        }
        return pages
    }

    private var currentFace: WordReviewFace {
        let pages = faces
        guard !pages.isEmpty else { return .definition }
        return pages[min(contentPage, pages.count - 1)]
    }

    @ViewBuilder
    private var wordBody: some View {
        switch currentFace {
        case .definition:
            centeredLine(word.definition.isEmpty ? "(no definition)" : word.definition)
        case .target:
            centeredLines(primary: displayedTargetForm, secondary: secondaryTargetForm)
        case .details:
            centeredLines(
                primary: displayedTargetForm,
                secondary: detailsSecondary,
                tertiary: detailsTertiary
            )
        case .context:
            centeredLines(
                primary: word.sentence?.targetLang ?? "",
                secondary: word.sentence?.baseLang
            )
        }
    }

    /// Headline on the target-language screens: surface form, or base form when that is the only one.
    private var displayedTargetForm: String {
        word.surfaceForm.isEmpty ? word.baseForm : word.surfaceForm
    }

    private var secondaryTargetForm: String? {
        guard !word.baseForm.isEmpty, word.baseForm != word.surfaceForm else { return nil }
        return word.baseForm
    }

    /// Reading under the word. A mnemonic-only card uses the mnemonic in that spot.
    private var detailsSecondary: String? {
        if !word.transliteration.isEmpty { return word.transliteration }
        return word.mnemonic
    }

    private var detailsTertiary: String? {
        guard !word.transliteration.isEmpty else { return nil }
        return word.mnemonic
    }

    private func centeredLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func centeredLines(primary: String, secondary: String?, tertiary: String? = nil) -> some View {
        VStack(spacing: 3) {
            if !primary.isEmpty {
                Text(primary)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            }
            if let secondary, !secondary.isEmpty {
                Text(secondary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            }
            if let tertiary, !tertiary.isEmpty {
                Text(tertiary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var formsSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > abs(value.translation.height) else { return }
                applyContentSwipe(horizontal)
            }
    }

    private var playbackEdgeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                if abs(horizontal) > 20, abs(horizontal) > abs(vertical) {
                    applyContentSwipe(horizontal)
                    return
                }
                guard hypot(horizontal, vertical) < 12, !isSubmitting else { return }
                toggleWordPlayback()
            }
    }

    private func applyContentSwipe(_ horizontal: CGFloat) {
        let last = faces.count - 1
        guard last >= 0 else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            if horizontal < 0, contentPage < last {
                contentPage += 1
            } else if horizontal > 0, contentPage > 0 {
                contentPage -= 1
            }
        }
    }

    private func toggleWordPlayback() {
        guard let fileName = word.audioFileName else { return }
        if isAudioPlaying {
            audioPlayer.pause()
        } else {
            audioPlayer.toggle(
                fileName: fileName,
                language: language,
                cue: audioPlayer.isLooping ? wordLoopWindow.start : word.audioCue
            )
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

    private var trashPageGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                if abs(horizontal) > 20, abs(horizontal) > abs(vertical) {
                    if horizontal > 0 {
                        actionsPage = 0
                    }
                    return
                }
                guard hypot(horizontal, vertical) < 12, !isSubmitting else { return }
                Task { await submitDelete() }
            }
    }

    @MainActor
    private func computeNextReviews() async {
        guard let card = word.card else {
            print("[vocab SRS] no reviewData/card for word \(word.id)")
            gradeLabels = Dictionary(uniqueKeysWithValues: gradeButtons.map { ($0, "—") })
            nextCards = [:]
            return
        }

        let now = Date()
        print("[vocab SRS] current due = \(card.due)")

        do {
            let cards = try VocabSRS.nextReviewCards(card: card, now: now)
            nextCards = cards
            var labels: [Rating: String] = [:]
            for rating in gradeButtons {
                if let card = cards[rating] {
                    // Label uses the same due the user would persist (incl. 5am snap).
                    let persistDue = VocabSRS.cardForPersist(card, now: now).due
                    let label = VocabSRS.relativeLabel(from: now, to: persistDue)
                    labels[rating] = label
                    print("[vocab SRS] \(rating.stringValue) -> \(persistDue) (\(label))")
                } else {
                    labels[rating] = "—"
                }
            }
            gradeLabels = labels
        } catch {
            print("[vocab SRS] failed to schedule: \(error)")
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
            try await WordReviewClient.updateReviewData(
                wordId: word.id,
                language: language,
                card: next
            )
            print("[vocab SRS] saved \(rating.stringValue) for \(word.id)")
            audioPlayer.stop()
            onReviewed(word.id, persisted)
        } catch {
            print("[vocab SRS] update failed: \(error)")
            errorMessage = "Save failed"
        }
    }

    @MainActor
    private func submitDelete() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await WordReviewClient.deleteWord(
                wordId: word.id,
                language: language,
                additionalContext: additionalContextForDelete
            )
            print("[vocab SRS] deleted \(word.id)")
            audioPlayer.stop()
            onDeleted(word.id)
        } catch {
            print("[vocab SRS] delete failed: \(error)")
            errorMessage = "Delete failed"
        }
    }

    /// Helper sentence id for `deleteWord.additionalContext` — only Adhoc words.
    private var additionalContextForDelete: [String] {
        guard let sentenceId = word.contexts.first,
              adhocSentenceIds.contains(sentenceId)
        else { return [] }
        return [sentenceId]
    }

    private func joinedLines(_ lines: [String?]) -> String {
        lines.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func expandedTitle(for face: WordReviewFace) -> String {
        switch face {
        case .definition: return "Definition"
        case .target: return "Word"
        case .details: return "Details"
        case .context: return "Sentence"
        }
    }

    private func expandedBody(for face: WordReviewFace) -> String {
        switch face {
        case .definition:
            return word.definition
        case .target:
            return joinedLines([displayedTargetForm, secondaryTargetForm])
        case .details:
            return joinedLines([displayedTargetForm, detailsSecondary, detailsTertiary])
        case .context:
            return joinedLines([word.sentence?.targetLang, word.sentence?.baseLang])
        }
    }
}

private enum WordReviewFace {
    case definition
    case target
    case details
    case context
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
            baseLang: "It's our honor",
            time: 12.5
        ))!,
        language: "chinese",
        remainingCount: 7,
        totalInReview: 20
    )
}
