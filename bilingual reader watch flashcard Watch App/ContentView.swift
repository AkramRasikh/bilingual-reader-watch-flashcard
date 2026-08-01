//
//  ContentView.swift
//  bilingual reader watch flashcard Watch App
//
//  Created by Akram Rasikh on 18/07/2026.
//

import SwiftUI

private enum LoadSource {
    case idle
    case local
    case network
}

private enum AppRoute: Hashable {
    case language(String)
    /// `contentId == nil` means All due words for the language.
    case review(language: String, contentId: String?)
}

struct ContentView: View {
    @State private var bundlesByLanguage: [String: LanguageBundle] = [:]
    @State private var status = "Loading…"
    @State private var isLoading = true
    @State private var loadSource: LoadSource = .idle
    @State private var path = NavigationPath()

    private var languages: [String] {
        bundlesByLanguage.keys.sorted()
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                Group {
                    if isLoading {
                        Text(status)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    } else if languages.isEmpty {
                        Text(status)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    } else {
                        List(languages, id: \.self) { language in
                            NavigationLink(value: AppRoute.language(language)) {
                                HStack {
                                    Text(displayName(for: language))
                                    Spacer()
                                    Text("\(bundlesByLanguage[language]?.dueCount ?? 0)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }

                if loadSource != .idle {
                    LoadSourceBadge(source: loadSource)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 2)
                }
            }
            .navigationTitle("Languages")
            .animation(.easeInOut(duration: 0.25), value: loadSource)
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
        .task {
            await loadLanguages()
        }
    }

    private func popRoute() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    private func removeWord(_ wordId: String, language: String) {
        guard var bundle = bundlesByLanguage[language] else { return }
        bundle = bundle.removingWord(id: wordId)
        if bundle.words.isEmpty {
            bundlesByLanguage[language] = nil
        } else {
            bundlesByLanguage[language] = bundle
        }
        if let updated = bundlesByLanguage[language] {
            LocalWordStore.save(language: language, bundle: updated)
        }
    }

    private func displayName(for language: String) -> String {
        language.prefix(1).uppercased() + language.dropFirst()
    }

    private func loadLanguages() async {
        let cached = LocalWordStore.loadAll()
        if !cached.isEmpty {
            bundlesByLanguage = cached
            isLoading = false
            loadSource = .local
            print("[LocalWordStore] hydrated UI from cache \(cached.keys.sorted())")
        } else {
            loadSource = .network
        }

        do {
            let data = try await OnLoadDataClient.loadBundlesByLanguage()
            let keys = data.keys.sorted()
            print("[getOnLoadData] languages = \(keys)")
            bundlesByLanguage = data
            isLoading = false
            if keys.isEmpty {
                status = "No languages found"
            }
            if loadSource == .local {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
            loadSource = .idle
        } catch {
            print("[getOnLoadData] error: \(error)")
            if cached.isEmpty {
                status = "Error:\n\(error.localizedDescription)"
            }
            isLoading = false
            try? await Task.sleep(nanoseconds: 900_000_000)
            loadSource = .idle
        }
    }
}

private struct LoadSourceBadge: View {
    let source: LoadSource

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: source == .local ? "internaldrive" : "icloud.and.arrow.down")
                .font(.system(size: 9, weight: .semibold))
            Text(source == .local ? "Local storage" : "Loading…")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

#Preview {
    ContentView()
}
