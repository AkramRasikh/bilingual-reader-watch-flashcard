//
//  ContentView.swift
//  bilingual reader watch flashcard Watch App
//
//  Created by Akram Rasikh on 18/07/2026.
//

import Combine
import FSRS
import SwiftUI

private enum ContinueStudy {
    case words
    case sentences
}

private enum AppRoute: Hashable {
    case language(String)
    case shadowing(language: String, contentId: String)
    /// `contentId == nil` means All due words for the language.
    case review(language: String, contentId: String?)
    /// `contentId == nil` means All due sentences for the language.
    case sentenceReview(language: String, contentId: String?)
    case improv(language: String)
    case inquiryBank(language: String)
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var bundlesByLanguage: [String: LanguageBundle] = [:]
    @State private var cachedLanguages: Set<String> = []
    @State private var loadingLanguage: String?
    @State private var loadError: String?
    @State private var refreshCandidate: String?
    @State private var path = NavigationPath()
    @State private var dueClock = Date()
    @StateObject private var inquiryBank = InquiryBank()
    @ObservedObject private var reviewOutbox = ReviewOutbox.shared

    private var languages: [String] {
        OnLoadDataClient.knownLanguages
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(languages, id: \.self) { language in
                    Button {
                        Task { await openLanguage(language) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(cachedLanguages.contains(language) ? Color.green : Color.clear)
                                .frame(width: 7, height: 7)
                                .overlay(
                                    Circle()
                                        .stroke(Color.secondary.opacity(0.35), lineWidth: cachedLanguages.contains(language) ? 0 : 1)
                                )

                            Text(flag(for: language))
                                .font(.title3)
                                .accessibilityLabel(displayName(for: language))

                            Spacer()

                            if loadingLanguage == language {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else if let bundle = bundlesByLanguage[language] {
                                VStack(alignment: .trailing, spacing: 0) {
                                    languageDueLabel(bundle)
                                    if reviewOutbox.count(for: language) > 0 {
                                        Text("\(reviewOutbox.count(for: language)) to upload")
                                            .font(.system(size: 8))
                                            .foregroundStyle(.orange)
                                            .monospacedDigit()
                                    }
                                }
                            }
                        }
                    }
                    .disabled(loadingLanguage != nil)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if reviewOutbox.count(for: language) > 0 {
                            Button("Upload") {
                                Task { await reviewOutbox.flush(language: language) }
                            }
                            .tint(.green)
                        }
                        if cachedLanguages.contains(language) {
                            Button("Refresh") {
                                refreshCandidate = language
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if let loadError {
                    Text(loadError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
            }
            .confirmationDialog(
                refreshTitle,
                isPresented: Binding(
                    get: { refreshCandidate != nil },
                    set: { if !$0 { refreshCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Reload from server", role: .destructive) {
                    if let language = refreshCandidate {
                        Task { await refreshLanguage(language) }
                    }
                    refreshCandidate = nil
                }
                Button("Cancel", role: .cancel) {
                    refreshCandidate = nil
                }
            } message: {
                Text("This replaces local data for \(displayName(for: refreshCandidate ?? "")). Word reviews still waiting to upload are kept. Other devices may have newer or older cards.")
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .language(let language):
                    LanguageTopicsView(
                        language: language,
                        bundle: bundlesByLanguage[language] ?? LanguageBundle(words: [], topics: []),
                        dueClock: dueClock,
                        inquiryCount: inquiryBank.inquiries(for: language).count,
                        onSelectImprov: {
                            path.append(AppRoute.improv(language: language))
                        },
                        onSelectInquiryBank: {
                            path.append(AppRoute.inquiryBank(language: language))
                        },
                        onSelectReview: { contentId in
                            path.append(AppRoute.review(language: language, contentId: contentId))
                        },
                        onSelectSentenceReview: { contentId in
                            path.append(AppRoute.sentenceReview(language: language, contentId: contentId))
                        },
                        onSelectShadowing: { contentId in
                            path.append(AppRoute.shadowing(language: language, contentId: contentId))
                        }
                    )

                case .shadowing(let language, let contentId):
                    if let topic = bundlesByLanguage[language]?.topics.first(where: { $0.id == contentId }) {
                        ShadowingView(language: language, topic: topic)
                    } else {
                        Text("Content unavailable")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                case .improv(let language):
                    ImprovView(language: language, inquiryBank: inquiryBank) { word in
                        insertAdhocWord(word, language: language)
                    }

                case .inquiryBank(let language):
                    InquiryBankView(language: language, bank: inquiryBank) { word in
                        insertAdhocWord(word, language: language)
                    }

                case .review(let language, let contentId):
                    let words = bundlesByLanguage[language]?.words(forContentId: contentId) ?? []
                    ReviewSessionView(
                        language: language,
                        initialWords: words,
                        adhocSentenceIds: bundlesByLanguage[language]?.adhocSentenceIds ?? [],
                        currentDueWords: {
                            bundlesByLanguage[language]?.words(forContentId: contentId) ?? []
                        },
                        contentTitle: { word in
                            guard contentId == nil else { return nil }
                            return bundlesByLanguage[language]?.contentTitle(for: word)
                        },
                        totalInReview: {
                            bundlesByLanguage[language]?.wordReviewCount(forContentId: contentId) ?? 0
                        },
                        continuation: {
                            studyContinuation(language: language, contentId: contentId)
                        },
                        onBack: { popRoute() },
                        onStudyWords: {
                            openSameContent(.words, language: language, contentId: contentId)
                        },
                        onStudySentences: {
                            openSameContent(.sentences, language: language, contentId: contentId)
                        },
                        onStudyNextWords: {
                            openNextWords(language: language, after: contentId)
                        },
                        onReviewed: { wordId, card in
                            updateReviewedWord(wordId, card: card, language: language)
                        },
                        onDeleted: { wordId in
                            removeWord(wordId, language: language)
                        }
                    )
                    .id("words-\(contentId ?? "all")")
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)

                case .sentenceReview(let language, let contentId):
                    SentenceReviewSessionView(
                        language: language,
                        initialSentences: bundlesByLanguage[language]?.sentences(forContentId: contentId) ?? [],
                        currentDueSentences: {
                            bundlesByLanguage[language]?.sentences(forContentId: contentId) ?? []
                        },
                        contentTitle: { sentence in
                            guard contentId == nil else { return nil }
                            return bundlesByLanguage[language]?.contentTitle(for: sentence)
                        },
                        totalInReview: {
                            bundlesByLanguage[language]?.sentenceReviewCount(forContentId: contentId) ?? 0
                        },
                        continuation: {
                            studyContinuation(language: language, contentId: contentId)
                        },
                        onBack: { popRoute() },
                        onStudyWords: {
                            openSameContent(.words, language: language, contentId: contentId)
                        },
                        onStudySentences: {
                            openSameContent(.sentences, language: language, contentId: contentId)
                        },
                        onStudyNextWords: {
                            openNextWords(language: language, after: contentId)
                        },
                        onReviewed: { sentenceId, card in
                            updateReviewedSentence(sentenceId, card: card, language: language)
                        },
                        onRemovedReview: { sentenceId in
                            removeSentenceReview(sentenceId, language: language)
                        }
                    )
                    .id("sentences-\(contentId ?? "all")")
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .onAppear {
            hydrateFromCache()
            dueClock = Date()
            Task { await reviewOutbox.flushAll() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                dueClock = Date()
                Task { await reviewOutbox.flushAll() }
            }
        }
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { date in
            dueClock = date
        }
    }

    private var refreshTitle: String {
        let name = displayName(for: refreshCandidate ?? "")
        return "Refresh \(name)?"
    }

    private func popRoute() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    private func studyContinuation(language: String, contentId: String?) -> StudyContinuation {
        guard let contentId, let bundle = bundlesByLanguage[language] else {
            return StudyContinuation()
        }
        let next = bundle.nextTopicWithDueWords(after: contentId)
        return StudyContinuation(
            wordsDue: bundle.words(forContentId: contentId).count,
            sentencesDue: bundle.sentenceDueCount(forContentId: contentId),
            nextWordsTitle: next?.title,
            nextWordsDue: next?.due ?? 0
        )
    }

    private func openSameContent(_ kind: ContinueStudy, language: String, contentId: String?) {
        guard let contentId else { return }
        switch kind {
        case .words:
            replaceTop(with: .review(language: language, contentId: contentId))
        case .sentences:
            replaceTop(with: .sentenceReview(language: language, contentId: contentId))
        }
    }

    private func openNextWords(language: String, after contentId: String?) {
        guard let contentId,
              let next = bundlesByLanguage[language]?.nextTopicWithDueWords(after: contentId)
        else { return }
        replaceTop(with: .review(language: language, contentId: next.id))
    }

    private func replaceTop(with route: AppRoute) {
        if !path.isEmpty {
            path.removeLast()
        }
        path.append(route)
    }

    private func hydrateFromCache() {
        var cached = LocalWordStore.loadAll()
        for language in Array(cached.keys) {
            if let bundle = cached[language] {
                cached[language] = bundleIncludingPending(bundle, language: language)
            }
        }
        bundlesByLanguage = cached
        cachedLanguages = Set(
            OnLoadDataClient.knownLanguages.filter { LocalWordStore.hasCached(language: $0) }
        )
        print("[LocalWordStore] ready languages = \(cachedLanguages.sorted())")
    }

    private func openLanguage(_ language: String) async {
        loadError = nil
        loadingLanguage = language
        defer { loadingLanguage = nil }

        do {
            let loaded = try await OnLoadDataClient.loadLocalOrFetch(language: language)
            let bundle = bundleIncludingPending(loaded, language: language)
            bundlesByLanguage[language] = bundle
            cachedLanguages.insert(language)
            path.append(AppRoute.language(language))
        } catch {
            print("[openLanguage] \(language) error: \(error)")
            loadError = "Couldn’t load \(displayName(for: language))"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            loadError = nil
        }
    }

    private func refreshLanguage(_ language: String) async {
        loadError = nil
        loadingLanguage = language
        defer { loadingLanguage = nil }

        do {
            let fetched = try await OnLoadDataClient.fetchAndCache(language: language)
            let bundle = bundleIncludingPending(fetched, language: language)
            bundlesByLanguage[language] = bundle
            cachedLanguages.insert(language)
            print("[refresh] \(language) → \(bundle.dueCount) due")
        } catch {
            print("[refresh] \(language) error: \(error)")
            loadError = "Refresh failed"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            loadError = nil
        }
    }

    /// Pending word grades and deletes survive a server reload. Sentences stay as fetched.
    private func bundleIncludingPending(_ bundle: LanguageBundle, language: String) -> LanguageBundle {
        let merged = reviewOutbox.apply(language: language, to: bundle)
        if merged != bundle {
            LocalWordStore.save(language: language, bundle: merged)
        }
        return merged
    }

    private func languageDueLabel(_ bundle: LanguageBundle) -> some View {
        let _ = dueClock
        let wordsDue = bundle.dueCount
        let sentencesDue = bundle.sentenceDueCount
        return HStack(spacing: 4) {
            Text("\(wordsDue) (W)")
            Text("\(sentencesDue) (S)")
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .accessibilityLabel("\(wordsDue) words, \(sentencesDue) sentences")
    }

    private func updateReviewedWord(_ wordId: String, card: Card, language: String) {
        guard var bundle = bundlesByLanguage[language] else { return }
        bundle = bundle.updatingCard(wordId: wordId, card: card)
        bundlesByLanguage[language] = bundle
        LocalWordStore.save(language: language, bundle: bundle)
    }

    private func updateReviewedSentence(_ sentenceId: String, card: Card, language: String) {
        guard var bundle = bundlesByLanguage[language] else { return }
        bundle = bundle.updatingSentenceCard(sentenceId: sentenceId, card: card)
        bundlesByLanguage[language] = bundle
        LocalWordStore.save(language: language, bundle: bundle)
    }

    private func insertAdhocWord(_ word: Word, language: String) {
        var bundle = bundlesByLanguage[language] ?? LanguageBundle(words: [], topics: [])
        bundle = bundle.insertingAdhocWord(word)
        bundlesByLanguage[language] = bundle
        LocalWordStore.save(language: language, bundle: bundle)
        saveAdhocAudio(for: word, language: language)
    }

    /// Best-effort clip save. Word persistence does not wait on this.
    private func saveAdhocAudio(for word: Word, language: String) {
        guard let fileName = word.audioFileName, !fileName.isEmpty else { return }
        Task {
            do {
                try await AudioFileStore.download(language: language, fileName: fileName)
            } catch AudioFileStoreError.badStatus(404) {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                do {
                    try await AudioFileStore.download(language: language, fileName: fileName)
                } catch {
                    print("[AudioFileStore] adhoc download failed: \(error)")
                }
            } catch {
                print("[AudioFileStore] adhoc download failed: \(error)")
            }
        }
    }

    private func removeWord(_ wordId: String, language: String) {
        guard var bundle = bundlesByLanguage[language] else { return }
        let adhocAudio = adhocAudioFileName(in: bundle, wordId: wordId)
        bundle = bundle.removingWord(id: wordId)
        bundlesByLanguage[language] = bundle
        LocalWordStore.save(language: language, bundle: bundle)
        if let adhocAudio {
            AudioFileStore.remove(language: language, fileName: adhocAudio)
        }
    }

    /// Sentence clip for an Adhoc word. Topic audio is shared and stays on disk.
    private func adhocAudioFileName(in bundle: LanguageBundle, wordId: String) -> String? {
        guard let word = bundle.words.first(where: { $0.id == wordId }),
              let sentenceId = word.contexts.first,
              bundle.adhocSentenceIds.contains(sentenceId)
        else { return nil }
        let fileName = word.audioFileName ?? sentenceId
        return fileName.isEmpty ? nil : fileName
    }

    private func removeSentenceReview(_ sentenceId: String, language: String) {
        guard var bundle = bundlesByLanguage[language] else { return }
        bundle = bundle.removingSentenceReview(id: sentenceId)
        bundlesByLanguage[language] = bundle
        LocalWordStore.save(language: language, bundle: bundle)
    }

    private func displayName(for language: String) -> String {
        guard !language.isEmpty else { return "" }
        return language.prefix(1).uppercased() + language.dropFirst()
    }

    /// Arabic uses the Sudanese flag.
    private func flag(for language: String) -> String {
        switch language {
        case "arabic": return "🇸🇩"
        case "chinese": return "🇨🇳"
        case "french": return "🇫🇷"
        case "japanese": return "🇯🇵"
        default: return ""
        }
    }
}

#Preview {
    ContentView()
}
