//
//  ContentView.swift
//  bilingual reader watch flashcard Watch App
//
//  Created by Akram Rasikh on 18/07/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var wordsByLanguage: [String: [Word]] = [:]
    @State private var status = "Loading…"
    @State private var isLoading = true

    private var languages: [String] {
        wordsByLanguage.keys.sorted()
    }

    var body: some View {
        NavigationStack {
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
                        NavigationLink(value: language) {
                            Text(displayName(for: language))
                        }
                    }
                }
            }
            .navigationTitle("Languages")
            .navigationDestination(for: String.self) { language in
                if let word = wordsByLanguage[language]?.randomElement() {
                    FlashcardView(word: word)
                } else {
                    Text("No words for \(displayName(for: language))")
                        .font(.caption2)
                }
            }
        }
        .task {
            await loadLanguages()
        }
    }

    private func displayName(for language: String) -> String {
        language.prefix(1).uppercased() + language.dropFirst()
    }

    private func loadLanguages() async {
        do {
            let data = try await OnLoadDataClient.fetchWordsByLanguage()
            let keys = data.keys.sorted()
            print("[getOnLoadData] languages = \(keys)")
            wordsByLanguage = data
            isLoading = false
            if keys.isEmpty {
                status = "No languages found"
            }
        } catch {
            print("[getOnLoadData] error: \(error)")
            status = "Error:\n\(error.localizedDescription)"
            isLoading = false
        }
    }
}

#Preview {
    ContentView()
}
