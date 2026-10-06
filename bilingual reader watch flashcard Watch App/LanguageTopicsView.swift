//
//  LanguageTopicsView.swift
//  bilingual reader watch flashcard Watch App
//
//  After picking a language: Improv, Adhoc words, then All + content rows.
//

import SwiftUI

struct LanguageTopicsView: View {
    let language: String
    let bundle: LanguageBundle
    var dueClock: Date = Date()
    var onSelectImprov: () -> Void = {}
    var onSelectReview: (_ contentId: String?) -> Void = { _ in }
    var onSelectSentenceReview: (_ contentId: String) -> Void = { _ in }
    var onSelectSnippetReview: (_ contentId: String) -> Void = { _ in }
    var onSelectShadowing: (_ contentId: String) -> Void = { _ in }

    private var displayName: String {
        language.prefix(1).uppercased() + language.dropFirst()
    }

    private var topicsByDueCount: [(topic: ContentTopic, words: (due: Int, total: Int), sentences: (due: Int, total: Int), snippets: (due: Int, total: Int))] {
        _ = dueClock
        return bundle.topicsByDueCount
    }

    var body: some View {
        let _ = dueClock
        List {
            Section("Improv") {
                Button(action: onSelectImprov) {
                    Text("Dictation")
                }
            }

            if bundle.adhocDueCount > 0 {
                Section("Adhoc words") {
                    Button {
                        onSelectReview(LanguageBundle.adhocContentId)
                    } label: {
                        HStack {
                            Text("Review")
                                .fontWeight(.semibold)
                            Spacer()
                            dueTotalLabel(
                                due: bundle.adhocDueCount,
                                total: bundle.wordReviewCount(forContentId: LanguageBundle.adhocContentId),
                                suffix: "w"
                            )
                        }
                    }
                }
            }

            if bundle.dueCount == 0 && bundle.sentenceDueCount == 0 && bundle.topics.isEmpty {
                emptyMessage("No data for \(displayName)")
            } else {
                if bundle.dueCount > 0 {
                    Button {
                        onSelectReview(nil)
                    } label: {
                        HStack {
                            Text("All")
                                .fontWeight(.semibold)
                            Spacer()
                            dueTotalLabel(due: bundle.dueCount, total: bundle.wordReviewCount, suffix: "w")
                        }
                    }
                }

                if !topicsByDueCount.isEmpty {
                    Section("Content") {
                        ForEach(topicsByDueCount, id: \.topic.id) { row in
                            ContentTopicRow(
                                language: language,
                                topic: row.topic,
                                words: row.words,
                                sentences: row.sentences,
                                snippets: row.snippets,
                                onWords: { onSelectReview(row.topic.id) },
                                onSentences: { onSelectSentenceReview(row.topic.id) },
                                onSnippets: { onSelectSnippetReview(row.topic.id) },
                                onShadowing: { onSelectShadowing(row.topic.id) }
                            )
                        }
                    }
                } else if bundle.dueCount == 0 && bundle.sentenceDueCount == 0 {
                    emptyMessage("Nothing due")
                }
            }
        }
        .navigationTitle(displayName)
    }

    private func dueTotalLabel(due: Int, total: Int, suffix: String) -> some View {
        Text("\(due)/\(max(total, due)) \(suffix)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    @ViewBuilder
    private func emptyMessage(_ text: String) -> some View {
        Section {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        }
    }
}

private struct ContentTopicRow: View {
    let language: String
    let topic: ContentTopic
    let words: (due: Int, total: Int)
    let sentences: (due: Int, total: Int)
    let snippets: (due: Int, total: Int)
    var onWords: () -> Void
    var onSentences: () -> Void
    var onSnippets: () -> Void
    var onShadowing: () -> Void

    @ObservedObject private var library = AudioLibrary.shared
    @StateObject private var download = TopicAudioSession()

    private var isSaved: Bool {
        _ = library.generation
        return AudioFileStore.hasFile(language: language, fileName: topic.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(isSaved ? Color.green : Color.clear)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .stroke(Color.secondary.opacity(0.35), lineWidth: isSaved ? 0 : 1)
                    )
                    .padding(.top, 3)

                Text(topic.title)
                    .font(.caption2)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    studyButton(
                        label: "W",
                        due: words.due,
                        total: words.total,
                        name: "Words",
                        action: onWords
                    )
                    studyButton(
                        label: "S",
                        due: sentences.due,
                        total: sentences.total,
                        name: "Sentences",
                        action: onSentences
                    )
                }
                HStack(spacing: 3) {
                    studyButton(
                        label: "✂",
                        due: snippets.due,
                        total: snippets.total,
                        name: "Snippets",
                        action: onSnippets
                    )
                    Button(action: onShadowing) {
                        Text("👻")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .accessibilityLabel("Shadowing")

                    if download.isDownloading {
                        downloadProgress
                    } else if !isSaved {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(download.errorMessage == nil ? Color.secondary : Color.red)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                Task {
                                    await download.start(language: language, fileName: topic.title)
                                }
                            }
                            .accessibilityLabel("Download audio")
                            .accessibilityHint("Double tap to download")
                    }
                }
            }
        }
    }

    private func studyButton(
        label: String,
        due: Int,
        total: Int,
        name: String,
        action: @escaping () -> Void
    ) -> some View {
        let shownTotal = max(total, due)
        return Button(action: action) {
            Text("\(label) \(due)/\(shownTotal)")
                .font(.system(size: 9))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .accessibilityLabel("\(name), \(due) of \(shownTotal)")
    }

    @ViewBuilder
    private var downloadProgress: some View {
        if download.fraction > 0 {
            ProgressView(value: download.fraction)
                .frame(width: 22, height: 22)
        } else {
            ProgressView()
                .frame(width: 22, height: 22)
        }
    }
}
