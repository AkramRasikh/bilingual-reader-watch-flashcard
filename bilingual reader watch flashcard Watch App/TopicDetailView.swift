//
//  TopicDetailView.swift
//  bilingual reader watch flashcard Watch App
//
//  Per-content audio download, started from the language content list.
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
