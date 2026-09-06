//
//  ContentView.swift
//  bilingual reader watch flashcard Watch App
//
//  Created by Akram Rasikh on 18/07/2026.
//

import Combine
import FSRS
import SwiftUI

private enum AppRoute: Hashable {
    case language(String)
    case topic(language: String, contentId: String)
    case shadowing(language: String, contentId: String)
    /// `contentId == nil` means All due words for the language.
    case review(language: String, contentId: String?)
    case sentenceReview(language: String, contentId: String)
    case improv(language: String)
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

                            Text(displayName(for: language))
                                .foregroundStyle(.primary)

                            Spacer()

                            if loadingLanguage == language {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else if let bundle = bundlesByLanguage[language] {
                                languageDueLabel(bundle)
                            }
                        }
                    }
                    .disabled(loadingLanguage != nil)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if cachedLanguages.contains(language) {
                            Button("Refresh") {
                                refreshCandidate = language
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Languages")
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
                Text("This replaces local data for \(displayName(for: refreshCandidate ?? "")). Other devices may have newer or older cards.")
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .language(let language):
                    LanguageTopicsView(
                        language: language,
                        bundle: bundlesByLanguage[language] ?? LanguageBundle(words: [], topics: []),
                        dueClock: dueClock,
                        onSelectImprov: {
                            path.append(AppRoute.improv(language: language))
                        },
                        onSelectReview: { contentId in
                            path.append(AppRoute.review(language: language, contentId: contentId))
                        },
                        onSelectTopic: { contentId in
                            path.append(AppRoute.topic(language: language, contentId: contentId))
                        }
                    )

                case .topic(let language, let contentId):
                    if let topic = bundlesByLanguage[language]?.topics.first(where: { $0.id == contentId }) {
                        TopicDetailView(
                            language: language,
                            topic: topic,
                            dueCount: topicDueCount(language: language, contentId: contentId),
                            sentenceDueCount: topicSentenceDueCount(language: language, contentId: contentId),
                            onSelectReview: {
                                path.append(AppRoute.review(language: language, contentId: contentId))
                            },
                            onSelectSentenceReview: {
                                path.append(AppRoute.sentenceReview(language: language, contentId: contentId))
                            },
                            onSelectShadowing: {
                                path.append(AppRoute.shadowing(language: language, contentId: contentId))
                            }
                        )
                    } else {
                        Text("Content unavailable")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                case .shadowing(let language, let contentId):
                    if let topic = bundlesByLanguage[language]?.topics.first(where: { $0.id == contentId }) {
                        ShadowingView(language: language, topic: topic)
                    } else {
                        Text("Content unavailable")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                case .improv(let language):
                    ImprovView(language: language) { word in
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
                        onBack: { popRoute() },
                        onReviewed: { wordId, card in
                            updateReviewedWord(wordId, card: card, language: language)
                        },
                        onDeleted: { wordId in
                            removeWord(wordId, language: language)
                        }
                    )
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)

                case .sentenceReview(let language, let contentId):
                    SentenceReviewSessionView(
                        language: language,
                        initialSentences: bundlesByLanguage[language]?.sentences(forContentId: contentId) ?? [],
                        currentDueSentences: {
                            bundlesByLanguage[language]?.sentences(forContentId: contentId) ?? []
                        },
                        totalInReview: {
                            bundlesByLanguage[language]?.sentenceReviewCount(forContentId: contentId) ?? 0
                        },
                        onBack: { popRoute() },
                        onReviewed: { sentenceId, card in
                            updateReviewedSentence(sentenceId, card: card, language: language)
                        },
                        onRemovedReview: { sentenceId in
                            removeSentenceReview(sentenceId, language: language)
                        }
                    )
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .onAppear {
            hydrateFromCache()
            dueClock = Date()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                dueClock = Date()
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

    private func hydrateFromCache() {
        let cached = LocalWordStore.loadAll()
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
            let bundle = try await OnLoadDataClient.loadLocalOrFetch(language: language)
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
            let bundle = try await OnLoadDataClient.fetchAndCache(language: language)
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

    private func languageDueLabel(_ bundle: LanguageBundle) -> some View {
        let _ = dueClock
        let wordsDue = bundle.dueCount
        let sentencesDue = bundle.sentenceDueCount
        return HStack(spacing: 4) {
            Text("\(wordsDue)")
            if sentencesDue > 0 {
                Text("·")
                Text("\(sentencesDue)")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private func topicDueCount(language: String, contentId: String) -> Int {
        _ = dueClock
        return bundlesByLanguage[language]?.words(forContentId: contentId).count ?? 0
    }

    private func topicSentenceDueCount(language: String, contentId: String) -> Int {
        _ = dueClock
        return bundlesByLanguage[language]?.sentenceDueCount(forContentId: contentId) ?? 0
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
    }

    private func removeWord(_ wordId: String, language: String) {
        guard var bundle = bundlesByLanguage[language] else { return }
        bundle = bundle.removingWord(id: wordId)
        bundlesByLanguage[language] = bundle
        LocalWordStore.save(language: language, bundle: bundle)
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
}

#Preview {
    ContentView()
}
