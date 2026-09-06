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
    var onSelectReview: () -> Void = {}

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

            if download.isDownloading {
                if download.fraction > 0 {
                    ProgressView(value: download.fraction)
                    Text("\(Int(download.fraction * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    ProgressView()
                }
            } else if !isSaved {
                Button("Download") {
                    Task {
                        await download.start(language: language, fileName: fileName)
                    }
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if let errorMessage = download.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Button("Review") {
                onSelectReview()
            }

            Text("\(dueCount) due")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .navigationTitle(topic.title)
    }
}
