//
//  TopicDetailView.swift
//  bilingual reader watch flashcard Watch App
//
//  Per-content audio download. Review still uses the existing flashcard player.
//

import SwiftUI

@MainActor
final class TopicAudioSession: ObservableObject {
    @Published var isDownloading = false
    @Published var fraction: Double = 0
    @Published var errorMessage: String?

    func start(language: String, fileName: String) async {
        guard !isDownloading else { return }
        isDownloading = true
        fraction = 0
        errorMessage = nil
        do {
            try await AudioFileStore.download(language: language, fileName: fileName) { [weak self] value in
                Task { @MainActor in
                    self?.fraction = value
                }
            }
        } catch {
            print("[AudioFileStore] download failed: \(error)")
            errorMessage = "Download failed"
        }
        isDownloading = false
    }
}

struct TopicDetailView: View {
    let language: String
    let topic: ContentTopic
    let dueCount: Int
    let sentenceDueCount: Int
    var onSelectReview: () -> Void = {}
    var onSelectSentenceReview: () -> Void = {}
    var onSelectShadowing: () -> Void = {}

    @ObservedObject private var library = AudioLibrary.shared
    @StateObject private var download = TopicAudioSession()

    private var fileName: String { topic.title }

    private var isSaved: Bool {
        _ = library.generation
        return AudioFileStore.hasFile(language: language, fileName: fileName)
    }

    private var statusText: String {
        if isSaved { return "Audio saved" }
        if download.isDownloading { return "Downloading…" }
        return "Audio not saved"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusText)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(isSaved ? Color.green : Color.secondary)

            if let errorMessage = download.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            HStack(alignment: .center, spacing: 6) {
                Button("Review") {
                    onSelectReview()
                }
                .frame(maxWidth: .infinity)

                if download.isDownloading {
                    downloadProgress
                } else if !isSaved {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 36)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            Task {
                                await download.start(language: language, fileName: fileName)
                            }
                        }
                        .accessibilityLabel("Download audio")
                        .accessibilityHint("Double tap to download")
                }
            }

            Button("Sentences") {
                onSelectSentenceReview()
            }

            Button("Shadowing") {
                onSelectShadowing()
            }

            Text("\(dueCount) words · \(sentenceDueCount) sentences")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .navigationTitle(topic.title)
        .raisedWatchBackButton()
    }

    @ViewBuilder
    private var downloadProgress: some View {
        if download.fraction > 0 {
            ProgressView(value: download.fraction)
                .frame(width: 28, height: 36)
        } else {
            ProgressView()
                .frame(width: 28, height: 36)
        }
    }
}

/// Keeps the back chevron in the top nav chrome and above page content so
/// overlapping labels/buttons cannot steal the tap.
extension View {
    func raisedWatchBackButton() -> some View {
        modifier(RaisedWatchBackButtonModifier())
    }
}

private struct RaisedWatchBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 44, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
            }
            .overlay(alignment: .topLeading) {
                Button {
                    dismiss()
                } label: {
                    Color.clear
                        .frame(width: 48, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: -6, y: -20)
                .zIndex(1000)
                .accessibilityHidden(true)
            }
    }
}
