//
//  FlashcardView.swift
//  bilingual reader watch flashcard Watch App
//
//  One due word per screen. The English definition starts in the center, with
//  the English sentence under it. Swipe left to add the target-language form,
//  then the transliteration, then the target-language sentence.
//  Long-press shows the full uncut text.
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
    var contentTitle: String? = nil
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
    @State private var replaceEasyWithDelete = false
    /// Set for the rest of this card so a second tap cannot grade it again before the next word appears.
    @State private var didCommit = false

    private let gradeButtons: [Rating] = [.again, .hard, .good, .easy]
    private let deleteTint = Color(red: 0.85, green: 0.65, blue: 0.13)

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
            VStack(alignment: .leading, spacing: 0) {
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

                if let contentTitle, !contentTitle.isEmpty {
                    Text(contentTitle)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

            // Bottom — swipe between SRS grades and delete (web ReviewSRSToggles)
            Group {
                if actionsPage == 0 {
                    HStack(spacing: 4) {
                        ForEach(gradeButtons, id: \.self) { rating in
                            if rating == .easy, replaceEasyWithDelete {
                                Button {
                                    submitDelete()
                                } label: {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 14).weight(.semibold))
                                        .foregroundStyle(deleteTint)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(deleteTint)
                                .disabled(didCommit)
                                .accessibilityLabel("Delete")
                            } else {
                                Button {
                                    submitGrade(rating)
                                } label: {
                                    Text(gradeLabels[rating] ?? "…")
                                        .font(.system(size: 10).weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(didCommit || nextCards[rating] == nil)
                            }
                        }
                    }
                } else {
                    ZStack {
                        Button {} label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14).weight(.semibold))
                                .foregroundStyle(deleteTint)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(deleteTint)
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
            let cardId = word.id
            contentPage = 0
            actionsPage = 0
            didCommit = true
            replaceEasyWithDelete = false
            gradeLabels = [:]
            nextCards = [:]
            audioPlayer.stop()
            await computeNextReviews()
            guard cardId == word.id else { return }
            didCommit = false
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
        if targetSentence != nil {
            pages.append(.context)
        }
        return pages
    }

    private var currentFace: WordReviewFace {
        let pages = faces
        guard !pages.isEmpty else { return .definition }
        return pages[min(contentPage, pages.count - 1)]
    }

    /// English meaning, capped so a long gloss does not fill the watch face.
    private var clippedDefinition: String {
        let text = word.definition.isEmpty ? "(no definition)" : word.definition
        return clipped(text, limit: 60)
    }

    /// English sentence on the first face. The target-language line stays behind a swipe.
    private var englishSentence: String? {
        let sentence = word.sentence?.baseLang
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return sentence.isEmpty ? nil : sentence
    }

    /// Sentence the word belongs to, in the language being studied.
    private var targetSentence: String? {
        let sentence = word.sentence?.targetLang
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return sentence.isEmpty ? nil : sentence
    }

    @ViewBuilder
    private var wordBody: some View {
        switch currentFace {
        case .definition:
            studyStack(showsTarget: false, showsDetails: false, showsEnglishSentence: true)
        case .target:
            studyStack(showsTarget: true, showsDetails: false, showsEnglishSentence: false)
        case .details:
            studyStack(showsTarget: true, showsDetails: true, showsEnglishSentence: false)
        case .context:
            studyStack(
                showsTarget: true,
                showsDetails: true,
                showsEnglishSentence: false,
                showsTargetSentence: true
            )
        }
    }

    /// About `limit` characters, breaking at the last space inside the limit.
    private func clipped(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        let head = trimmed[..<end]
        if let space = head.lastIndex(of: " "), space > head.startIndex {
            return head[..<space].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return String(head).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// Target-language form under the definition: surface form, or base form when that is the only one.
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

    private func studyStack(
        showsTarget: Bool,
        showsDetails: Bool,
        showsEnglishSentence: Bool,
        showsTargetSentence: Bool = false
    ) -> some View {
        VStack(spacing: 3) {
            Text(clippedDefinition)
                .font(.system(size: showsTargetSentence ? 12 : (showsTarget ? 13 : 15), weight: .bold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineLimit(showsTargetSentence ? 1 : (showsTarget ? 2 : 3))
                .minimumScaleFactor(0.7)

            if showsEnglishSentence, let englishSentence {
                Text(englishSentence)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            if showsTarget, !displayedTargetForm.isEmpty {
                Text(displayedTargetForm)
                    .font(.system(size: showsTargetSentence ? 14 : 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(showsTargetSentence ? 1 : 2)
                    .minimumScaleFactor(0.7)
            }

            if showsTarget, let secondaryTargetForm {
                Text(secondaryTargetForm)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            if showsDetails, let detailsSecondary {
                Text(detailsSecondary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            if showsDetails, let detailsTertiary {
                Text(detailsTertiary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(showsTargetSentence ? 1 : 2)
                    .minimumScaleFactor(0.7)
            }

            if showsTargetSentence, let targetSentence {
                Text(targetSentence)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
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
                guard hypot(horizontal, vertical) < 12 else { return }
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
                guard hypot(horizontal, vertical) < 12, !didCommit else { return }
                submitDelete()
            }
    }

    @MainActor
    private func computeNextReviews() async {
        guard let card = word.card else {
            print("[vocab SRS] no reviewData/card for word \(word.id)")
            gradeLabels = Dictionary(uniqueKeysWithValues: gradeButtons.map { ($0, "—") })
            nextCards = [:]
            replaceEasyWithDelete = false
            return
        }

        let now = Date()
        print("[vocab SRS] current due = \(card.due)")

        do {
            let cards = try VocabSRS.nextReviewCards(card: card, now: now)
            nextCards = cards
            var labels: [Rating: String] = [:]
            var offerDelete = false
            for rating in gradeButtons {
                if let card = cards[rating] {
                    // Label uses the same due the user would persist (incl. 5am snap).
                    let persistDue = VocabSRS.cardForPersist(card, now: now).due
                    let label = VocabSRS.relativeLabel(from: now, to: persistDue)
                    labels[rating] = label
                    if rating == .easy {
                        offerDelete = VocabSRS.shouldReplaceEasyWithDelete(
                            easyDue: persistDue,
                            now: now,
                            contentType: .vocab
                        )
                    }
                    print("[vocab SRS] \(rating.stringValue) -> \(persistDue) (\(label))")
                } else {
                    labels[rating] = "—"
                }
            }
            gradeLabels = labels
            replaceEasyWithDelete = offerDelete
        } catch {
            print("[vocab SRS] failed to schedule: \(error)")
            gradeLabels = Dictionary(uniqueKeysWithValues: gradeButtons.map { ($0, "—") })
            nextCards = [:]
            replaceEasyWithDelete = false
        }
    }

    private func submitGrade(_ rating: Rating) {
        guard !didCommit, let next = nextCards[rating] else { return }
        didCommit = true
        let persisted = VocabSRS.cardForPersist(next)
        ReviewOutbox.shared.enqueueGrade(language: language, wordId: word.id, card: persisted)
        print("[vocab SRS] committed \(rating.stringValue) for \(word.id)")
        audioPlayer.stop()
        onReviewed(word.id, persisted)
        Task { await ReviewOutbox.shared.flush(language: language) }
    }

    private func submitDelete() {
        guard !didCommit else { return }
        didCommit = true
        ReviewOutbox.shared.enqueueDelete(
            language: language,
            wordId: word.id,
            additionalContext: additionalContextForDelete
        )
        print("[vocab SRS] committed delete \(word.id)")
        audioPlayer.stop()
        onDeleted(word.id)
        Task { await ReviewOutbox.shared.flush(language: language) }
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
            return joinedLines([word.definition, englishSentence])
        case .target:
            return joinedLines([word.definition, displayedTargetForm, secondaryTargetForm])
        case .details:
            return joinedLines([
                word.definition,
                displayedTargetForm,
                secondaryTargetForm,
                detailsSecondary,
                detailsTertiary,
            ])
        case .context:
            return joinedLines([
                word.definition,
                displayedTargetForm,
                secondaryTargetForm,
                detailsSecondary,
                detailsTertiary,
                targetSentence,
            ])
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
