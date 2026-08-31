//
//  LanguageTopicsView.swift
//  bilingual reader watch flashcard Watch App
//
//  After picking a language: Improv, then All + content rows with due counts.
//

import SwiftUI

struct LanguageTopicsView: View {
    let language: String
    let bundle: LanguageBundle
    var onSelectImprov: () -> Void = {}
    var onSelectReview: (_ contentId: String?) -> Void = { _ in }

    private var displayName: String {
        language.prefix(1).uppercased() + language.dropFirst()
    }

    private var topicsWithDue: [(topic: ContentTopic, count: Int)] {
        bundle.topicsWithDue
    }

    var body: some View {
        List {
            Section("Improv") {
                Button(action: onSelectImprov) {
                    Text("Dictation")
                }
            }

            if bundle.dueCount == 0 && bundle.topics.isEmpty {
                emptyMessage("No data for \(displayName)")
            } else if bundle.dueCount == 0 {
                emptyMessage("No words due")
            } else {
                Button {
                    onSelectReview(nil)
                } label: {
                    HStack {
                        Text("All")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(bundle.dueCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                if !topicsWithDue.isEmpty {
                    Section("Content") {
                        ForEach(topicsWithDue, id: \.topic.id) { row in
                            Button {
                                onSelectReview(row.topic.id)
                            } label: {
                                HStack(alignment: .top, spacing: 6) {
                                    Text(row.topic.title)
                                        .font(.caption2)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                    Spacer(minLength: 4)
                                    Text("\(row.count)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(displayName)
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
