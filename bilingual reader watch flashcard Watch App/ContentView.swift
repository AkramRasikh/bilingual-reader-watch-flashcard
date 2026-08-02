//
//  ContentView.swift
//  bilingual reader watch flashcard Watch App
//
//  Created by Akram Rasikh on 18/07/2026.
//

import SwiftUI

private enum AppRoute: Hashable {
    case language(String)
    /// `contentId == nil` means All due words for the language.
    case review(language: String, contentId: String?)
}

struct ContentView: View {
    @State private var bundlesByLanguage: [String: LanguageBundle] = [:]
    @State private var cachedLanguages: Set<String> = []
    @State private var loadingLanguage: String?
    @State private var loadError: String?
    @State private var refreshCandidate: String?
    @State private var path = NavigationPath()

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
                                Text("\(bundle.dueCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
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
                        onSelectReview: { contentId in
                            path.append(AppRoute.review(language: language, contentId: contentId))
                        }
                    )

                case .review(let language, let contentId):
                    let words = bundlesByLanguage[language]?.words(forContentId: contentId) ?? []
                    ReviewSessionView(
                        language: language,
                        initialWords: words,
                        onBack: { popRoute() },
                        onWordRemoved: { wordId in
                            removeWord(wordId, language: language)
                        }
                    )
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .onAppear {
            hydrateFromCache()
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

    private func removeWord(_ wordId: String, language: String) {
        guard var bundle = bundlesByLanguage[language] else { return }
        bundle = bundle.removingWord(id: wordId)
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
