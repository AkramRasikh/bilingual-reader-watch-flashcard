//
//  ImprovView.swift
//  bilingual reader watch flashcard Watch App
//
//  Opens system dictation immediately, then text + Upload / Delete.
//

import SwiftUI

struct ImprovView: View {
    let language: String

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var recorder: ImprovRecorder

    init(language: String) {
        self.language = language
        _recorder = StateObject(wrappedValue: ImprovRecorder(language: language))
    }

    var body: some View {
        Group {
            switch recorder.phase {
            case .idle:
                VStack(spacing: 8) {
                    Button("Dictation", action: recorder.start)
                    if let errorMessage = recorder.errorMessage {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }

            case .dictating:
                ProgressView()

            case .ready:
                readyReview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Dictation")
        .accessibilityIdentifier("improv-\(language)")
        .task {
            recorder.start()
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

    private var readyReview: some View {
        VStack(spacing: 6) {
            transcriptArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let errorMessage = recorder.errorMessage {
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

                Button("Delete", role: .destructive) {
                    recorder.deleteClip()
                }
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

    /// Wired to an async upload in a later slice.
    private func uploadTapped() async {
        print("[Improv] upload pending language=\(language) text=\(recorder.transcript)")
    }
}

#Preview {
    NavigationStack {
        ImprovView(language: "french")
    }
}
