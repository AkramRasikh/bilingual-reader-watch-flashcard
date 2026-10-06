//
//  SnippetFlashcardView.swift
//  bilingual reader watch flashcard Watch App
//
//  One due snippet. The focus span stays fully opaque; text outside it fades.
//  Play loops the snippet window and restarts at its start when playback crosses the end.
//  SRS matches sentence review, including a swipe to delete the snippet.
//

import FSRS
import SwiftUI

struct SnippetFlashcardView: View {
    let snippet: ReviewableSnippet
    var language: String = ""
    var remainingDue: Int = 0
    var totalInReview: Int = 0
    var onBack: () -> Void = {}
    var savedWordForms: Set<String> = []
    var onReviewed: (String, Card) -> Void = { _, _ in }
    var onDeleted: (String) -> Void = { _ in }
    var onWordSaved: (Word) -> Void = { _ in }

    @ObservedObject private var audioPlayer = WordAudioPlayer.shared
    @ObservedObject private var audioLibrary = AudioLibrary.shared
    @State private var page: SnippetPage = .snippet
    @State private var selectedWordID: Int?
    @State private var sessionSavedForms: Set<String> = []
    @State private var isSavingWord = false
    @State private var actionsPage = 0
    @State private var expandedText: SnippetExpandedText?
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
        guard let fileName = snippet.audioFileName else { return false }
        return AudioFileStore.hasFile(language: language, fileName: fileName)
    }

    private var snippetLoopWindow: (start: TimeInterval, end: TimeInterval) {
        let duration = audioPlayer.clock.duration
        return snippet.loopWindow(fileDuration: duration > 0 ? duration : nil)
    }

    private var focus: SnippetFocus {
        SnippetFocus(
            fullText: snippet.targetLang,
            query: snippet.focusQuery,
            trimmed: SnippetFocus.isTrimmedLanguage(language),
            startOffset: 0,
            lengthAdjustment: 0
        )
    }

    private var textRuns: [SnippetTextRun] {
        SnippetBreakdown.runs(
            text: snippet.targetLang,
            vocab: snippet.vocab,
            matchStart: focus.matchStart,
            matchEnd: focus.matchEnd
        )
    }

    private var selectedWord: SnippetTextRun? {
        textRuns.first { $0.wordID == selectedWordID && $0.meaning != nil }
    }

    private var sentenceContext: SnippetSentenceContext {
        let stored = snippet.sentenceContext
        if !stored.currentTarget.isEmpty || !stored.currentBase.isEmpty {
            return stored
        }
        return SnippetSentenceContext(
            currentTarget: snippet.targetLang,
            currentBase: snippet.baseLang
        )
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(remainingDue)/\(max(totalInReview, remainingDue))")
                            .font(.system(size: 9, weight: .semibold))
                            .monospacedDigit()
                    }
                    .padding(.top, 6)
                    .frame(minWidth: 40, minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back, \(remainingDue) of \(max(totalInReview, remainingDue)) snippets due")

                Spacer(minLength: 0)

                if snippet.canPlayAudio {
                    Button(action: toggleSnippetPlayback) {
                        Image(systemName: isAudioPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isLocalAudio ? Color.green : Color.primary)
                            .frame(width: 28, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isAudioPlaying ? "Stop" : "Play")
                    .accessibilityHint(isLocalAudio ? "Saved audio" : "Streaming audio")
                }
            }
            .zIndex(10)
            .background(.background)

            Group {
                switch page {
                case .sentences:
                    snippetSentenceBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                        .gesture(pageSwipeGesture)
                        .onLongPressGesture {
                            expandedText = SnippetExpandedText(body: expandedSentenceText)
                        }
                case .breakdown:
                    snippetBreakdownBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .contentShape(Rectangle())
                        .simultaneousGesture(pageSwipeGesture)
                        .onLongPressGesture {
                            expandedText = SnippetExpandedText(body: expandedBreakdownText)
                        }
                case .snippet:
                    if snippet.targetLang.isEmpty {
                        Text("(no snippet)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                    } else {
                        SnippetFlowLayout(spacing: 0, lineSpacing: 2) {
                            ForEach(textRuns) { run in
                                snippetRun(run)
                            }
                        }
                        .environment(\.layoutDirection, language == "arabic" ? .rightToLeft : .leftToRight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                        .simultaneousGesture(pageSwipeGesture)
                        .onLongPressGesture {
                            expandedText = SnippetExpandedText(body: snippet.targetLang)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isSubmitting ? 0.45 : 1)

            if page == .snippet, let selectedWord, let meaning = selectedWord.meaning {
                let color = SnippetWordColor.color(at: selectedWord.wordIndex ?? 0)
                VStack(spacing: 2) {
                    Text(meaning)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                    if !isSaved(selectedWord) {
                        Button {
                            Task { await saveSelectedWord() }
                        } label: {
                            if isSavingWord {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Text("Save")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(color)
                        .disabled(isSavingWord || isSubmitting)
                        .accessibilityLabel("Save word")
                    }
                }
            }

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
                                    .font(.system(size: 8).weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(isSubmitting || nextCards[rating] == nil)
                        }
                    }
                } else {
                    ZStack {
                        Button {} label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 11).weight(.semibold))
                                .foregroundStyle(Color(red: 0.85, green: 0.65, blue: 0.13))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(Color(red: 0.85, green: 0.65, blue: 0.13))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(trashPageGesture)
                            .accessibilityLabel("Delete snippet")
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .frame(height: 26)
            .contentShape(Rectangle())
            .gesture(actionsSwipeGesture)
            .opacity(isSubmitting ? 0.45 : 1)
        }
        .sheet(item: $expandedText) { item in
            ScrollView {
                Text(item.body.isEmpty ? "(no snippet)" : item.body)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .task(id: snippet.id) {
            actionsPage = 0
            page = .snippet
            selectedWordID = nil
            errorMessage = nil
            audioPlayer.stop()
            await computeNextReviews()
        }
    }

    private var sentenceLines: [SnippetSentenceLine] {
        if !sentenceContext.lines.isEmpty {
            return sentenceContext.lines
        }
        return [
            SnippetSentenceLine(
                id: snippet.id,
                targetLang: sentenceContext.currentTarget,
                baseLang: sentenceContext.currentBase,
                meaning: "",
                isCurrent: true
            ),
        ]
    }

    private var snippetSentenceBody: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 6) {
                ForEach(sentenceLines) { line in
                    sentenceLineView(line)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .environment(\.layoutDirection, language == "arabic" ? .rightToLeft : .leftToRight)
    }

    private func sentenceLineView(_ line: SnippetSentenceLine) -> some View {
        let primary = line.isCurrent
        return VStack(alignment: .center, spacing: 1) {
            Text(line.targetLang.isEmpty ? "(no sentence)" : line.targetLang)
                .font(.system(size: primary ? 15 : 12, weight: primary ? .bold : .medium))
                .foregroundStyle(primary ? Color.white : Color.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            if !line.baseLang.isEmpty {
                Text(line.baseLang)
                    .font(.system(size: primary ? 12 : 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            }
            if !line.meaning.isEmpty {
                Text("* \(line.meaning)")
                    .font(.system(size: 11, weight: .regular))
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel("AI translation \(line.meaning)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var expandedSentenceText: String {
        sentenceLines.flatMap { line -> [String] in
            var parts = [line.targetLang, line.baseLang]
            if !line.meaning.isEmpty {
                parts.append("* \(line.meaning)")
            }
            return parts.filter { !$0.isEmpty }
        }
        .joined(separator: "\n")
    }

    private var snippetBreakdownBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sentenceContext.breakdowns) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        if sentenceContext.breakdowns.count > 1, !group.targetLang.isEmpty {
                            Text(group.targetLang)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                        }
                        ForEach(Array(group.words.enumerated()), id: \.offset) { index, word in
                            let color = SnippetWordColor.color(at: index)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(word.surfaceForm)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(color)
                                    .underline(isSavedForm(word.surfaceForm))
                                Text(word.meaning)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(color.opacity(0.85))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .environment(\.layoutDirection, language == "arabic" ? .rightToLeft : .leftToRight)
        }
    }

    private var expandedBreakdownText: String {
        sentenceContext.breakdowns
            .flatMap { group in
                group.words.map { "\($0.surfaceForm)  \($0.meaning)" }
            }
            .joined(separator: "\n")
    }

    /// Swipe left advances snippet → sentences → breakdowns. Swipe right steps back.
    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > abs(value.translation.height) else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    if horizontal < 0 {
                        advancePage()
                    } else {
                        retreatPage()
                    }
                }
            }
    }

    private func advancePage() {
        switch page {
        case .snippet:
            page = .sentences
        case .sentences:
            if !sentenceContext.breakdowns.isEmpty {
                page = .breakdown
            }
        case .breakdown:
            break
        }
    }

    private func retreatPage() {
        switch page {
        case .breakdown:
            page = .sentences
        case .sentences:
            page = .snippet
        case .snippet:
            break
        }
    }

    private func isSavedForm(_ surface: String) -> Bool {
        let form = LanguageBundle.normalizedWordForm(surface)
        guard !form.isEmpty else { return false }
        return savedWordForms.contains(form) || sessionSavedForms.contains(form)
    }

    private func isSaved(_ run: SnippetTextRun) -> Bool {
        isSavedForm(run.surfaceForm ?? "")
    }

    private func saveSelectedWord() async {
        guard let selectedWord, !isSavingWord, !isSaved(selectedWord) else { return }
        let surface = selectedWord.surfaceForm?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let meaning = selectedWord.meaning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sentenceId = selectedWord.sentenceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sentenceText = selectedWord.sentenceText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let contextSentence = sentenceText.isEmpty ? snippet.targetLang : sentenceText
        guard !surface.isEmpty, !meaning.isEmpty, !sentenceId.isEmpty, !contextSentence.isEmpty else {
            errorMessage = "Can’t save this word"
            return
        }

        isSavingWord = true
        errorMessage = nil
        defer { isSavingWord = false }

        do {
            var word = try await WordReviewClient.saveBreakdownWord(
                language: language,
                surfaceForm: surface,
                meaning: meaning,
                sentenceId: sentenceId,
                contextSentence: contextSentence
            )
            let sentence = SentenceContext(
                targetLang: contextSentence,
                baseLang: snippet.baseLang,
                time: selectedWord.sentenceTime
            )
            word = word.withSentence(sentence)
            if let fileName = snippet.audioFileName, !fileName.isEmpty {
                let playAt = selectedWord.sentenceTime ?? snippet.time
                word = word.withAudio(fileName: fileName, playAt: max(0, playAt))
            }
            sessionSavedForms.insert(LanguageBundle.normalizedWordForm(surface))
            onWordSaved(word)
        } catch ReviewClientError.alreadyExists {
            sessionSavedForms.insert(LanguageBundle.normalizedWordForm(surface))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func snippetRun(_ run: SnippetTextRun) -> some View {
        let opacity: Double = run.insideFocus ? 1 : 0.35
        let font = Font.system(size: 15, weight: run.insideFocus ? .bold : .medium)
        if let wordIndex = run.wordIndex {
            let color = SnippetWordColor.color(at: wordIndex).opacity(opacity)
            let saved = isSaved(run)
            Button {
                selectedWordID = selectedWordID == run.wordID ? nil : run.wordID
            } label: {
                Text(run.text)
                    .font(font)
                    .foregroundStyle(color)
                    .underline(saved)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(run.text)
            .accessibilityHint(saved ? "Saved" : (run.meaning ?? ""))
        } else {
            Text(run.text)
                .font(font)
                .foregroundStyle(Color.white.opacity(opacity))
        }
    }

    private func toggleSnippetPlayback() {
        guard let fileName = snippet.audioFileName, !fileName.isEmpty else { return }
        if isAudioPlaying {
            audioPlayer.pause()
            return
        }
        let window = snippetLoopWindow
        print("[snippet loop] time=\(snippet.time) contracted=\(snippet.isContracted) window=\(window.start)->\(window.end)")
        audioPlayer.enableLoop(start: window.start, end: window.end)
        audioPlayer.toggle(fileName: fileName, language: language, cue: window.start)
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
        guard let card = snippet.card else {
            gradeLabels = Dictionary(uniqueKeysWithValues: gradeButtons.map { ($0, "—") })
            nextCards = [:]
            return
        }

        let now = Date()
        do {
            let cards = try VocabSRS.nextReviewCards(card: card, now: now, contentType: .snippet)
            nextCards = cards
            var labels: [Rating: String] = [:]
            for rating in gradeButtons {
                if let card = cards[rating] {
                    let persistDue = VocabSRS.cardForPersist(card, now: now).due
                    labels[rating] = VocabSRS.relativeLabel(from: now, to: persistDue)
                } else {
                    labels[rating] = "—"
                }
            }
            gradeLabels = labels
        } catch {
            print("[snippet SRS] failed to schedule: \(error)")
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
            try await WordReviewClient.saveSnippet(
                language: language,
                contentId: snippet.contentId,
                snippet: snippet,
                reviewCard: next
            )
            print("[snippet SRS] saved \(rating.snippetRatingName) for \(snippet.id)")
            onReviewed(snippet.id, persisted)
        } catch {
            print("[snippet SRS] update failed: \(error)")
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
            try await WordReviewClient.deleteSnippet(
                language: language,
                contentId: snippet.contentId,
                snippetId: snippet.id
            )
            print("[snippet SRS] deleted \(snippet.id)")
            onDeleted(snippet.id)
        } catch {
            print("[snippet SRS] delete failed: \(error)")
            errorMessage = "Delete failed"
        }
    }
}

private struct SnippetFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(in: width, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews: subviews) {
            let rowWidth = row.widths.reduce(0, +) + spacing * CGFloat(max(0, row.indexes.count - 1))
            var x = bounds.minX + max(0, (bounds.width - rowWidth) / 2)
            for (offset, index) in row.indexes.enumerated() {
                let size = CGSize(width: row.widths[offset], height: row.height)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += row.widths[offset] + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indexes: [Int] = []
        var widths: [CGFloat] = []
        var height: CGFloat = 0
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var used: CGFloat = 0
        let limit = width > 0 ? width : .greatestFiniteMagnitude
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = current.indexes.isEmpty ? size.width : used + spacing + size.width
            if !current.indexes.isEmpty, next > limit {
                rows.append(current)
                current = Row()
                used = 0
            }
            if !current.indexes.isEmpty {
                used += spacing
            }
            current.indexes.append(index)
            current.widths.append(size.width)
            current.height = max(current.height, size.height)
            used += size.width
        }
        if !current.indexes.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

private enum SnippetPage {
    case snippet
    case sentences
    case breakdown
}

private struct SnippetExpandedText: Identifiable {
    let id = UUID()
    let body: String
}

private extension Rating {
    var snippetRatingName: String {
        switch self {
        case .manual: return "manual"
        case .again: return "again"
        case .hard: return "hard"
        case .good: return "good"
        case .easy: return "easy"
        }
    }
}
