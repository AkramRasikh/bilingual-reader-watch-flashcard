//
//  LanguageTopicsView.swift
//  bilingual reader watch flashcard Watch App
//
//  After picking a language: All (current behaviour) + content rows with due counts.
//

import SwiftUI

struct LanguageTopicsView: View {
    let language: String
    let bundle: LanguageBundle
    var onSelectReview: (_ contentId: String?) -> Void = { _ in }

    private var displayName: String {
        language.prefix(1).uppercased() + language.dropFirst()
    }

    private var topicsWithDue: [(topic: ContentTopic, count: Int)] {
        bundle.topicsWithDue
    }

    var body: some View {
        List {
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
        .navigationTitle(displayName)
    }
}
