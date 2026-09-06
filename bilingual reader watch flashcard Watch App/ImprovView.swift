//
//  ImprovView.swift
//  bilingual reader watch flashcard Watch App
//
//  Opens system dictation immediately, then text + Upload / Delete.
//

import SwiftUI

struct ImprovView: View {
    let language: String
    var onWordAdded: (Word) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var recorder: ImprovRecorder
    @State private var isUploading = false
    @State private var addedWord: Word?
    @State private var banner: StatusBanner?

    init(language: String, onWordAdded: @escaping (Word) -> Void = { _ in }) {
        self.language = language
        self.onWordAdded = onWordAdded
        _recorder = StateObject(wrappedValue: ImprovRecorder(language: language))
    }

    var body: some View {
        Group {
            if isUploading {
                uploadingView
            } else if let addedWord {
                successView(addedWord)
            } else {
                switch recorder.phase {
                case .idle:
                    idleView
                case .dictating:
                    ProgressView()
                case .ready:
                    readyReview
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Dictation")
        .accessibilityIdentifier("improv-\(language)")
        .task {
            if addedWord == nil, !isUploading {
                recorder.start()
            }
        }
        .onDisappear {
            if recorder.phase != .dictating {
                recorder.abandon()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                recorder.abandon()
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Button("Dictation", action: recorder.start)
            if let errorMessage = recorder.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var uploadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Uploading")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var readyReview: some View {
        VStack(spacing: 6) {
            transcriptArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let banner {
                statusBanner(banner)
            } else if let errorMessage = recorder.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 6) {
                Button("Upload") {
                    Task { await uploadTapped() }
                }
                .tint(.blue)
                .disabled(recorder.transcript.isEmpty)

                Button("Delete", role: .destructive) {
                    banner = nil
                    recorder.deleteClip()
                }
            }
            .font(.caption2)
            .controlSize(.mini)
        }
    }

    private func successView(_ word: Word) -> some View {
        VStack(spacing: 6) {
            statusBanner(StatusBanner(text: "Added", isError: false))

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text(word.definition)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(word.surfaceForm)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if word.baseForm != word.surfaceForm, !word.baseForm.isEmpty {
                        Text(word.baseForm)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if !word.transliteration.isEmpty {
                        Text(word.transliteration)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let sentence = word.sentence {
                        if !sentence.targetLang.isEmpty {
                            Text(sentence.targetLang)
                                .font(.caption2)
                                .padding(.top, 2)
                        }
                        if !sentence.baseLang.isEmpty {
                            Text(sentence.baseLang)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !word.isDue {
                        Text("Not due yet")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 6) {
                Button("Again", action: againTapped)
                    .tint(.blue)
                Button("Back") { dismiss() }
            }
            .font(.caption2)
            .controlSize(.mini)
        }
    }

    @ViewBuilder
    private var transcriptArea: some View {
        if recorder.transcript.isEmpty {
            Text("No text")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                Text(recorder.transcript)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func statusBanner(_ banner: StatusBanner) -> some View {
        HStack(spacing: 4) {
            Image(systemName: banner.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
            Text(banner.text)
                .lineLimit(2)
        }
        .font(.caption2)
        .foregroundStyle(banner.isError ? .red : .green)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(
            (banner.isError ? Color.red : Color.green).opacity(0.18),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    @MainActor
    private func uploadTapped() async {
        let inquiry = recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inquiry.isEmpty, !isUploading else { return }

        banner = nil
        isUploading = true

        do {
            let word = try await WordReviewClient.addImprovWord(
                language: language,
                inquiry: inquiry
            )
            print("[Improv] uploaded \(word.id) \(word.surfaceForm)")
            onWordAdded(word)
            addedWord = word
        } catch let error as ReviewClientError {
            print("[Improv] upload failed: \(error)")
            banner = StatusBanner(
                text: error.errorDescription ?? "Upload failed",
                isError: true
            )
        } catch {
            print("[Improv] upload failed: \(error)")
            banner = StatusBanner(text: "Upload failed", isError: true)
        }

        isUploading = false
    }

    private func againTapped() {
        addedWord = nil
        banner = nil
        recorder.deleteClip()
        recorder.start()
    }
}

private struct StatusBanner: Equatable {
    let text: String
    let isError: Bool
}

#Preview {
    NavigationStack {
        ImprovView(language: "french")
    }
}
