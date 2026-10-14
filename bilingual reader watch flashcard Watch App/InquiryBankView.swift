//
//  InquiryBankView.swift
//  bilingual reader watch flashcard Watch App
//
//  Saved inquiries for one language. Upload all waits here for the batch response.
//

import SwiftUI

struct InquiryBankView: View {
    let language: String
    @ObservedObject var bank: InquiryBank
    var onWordAdded: (Word) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: Phase = .list
    @State private var editing: BankedInquiry?
    @State private var draft = ""
    @State private var results: [ImprovBatchItem] = []
    @State private var banner: String?
    @State private var uploadTask: Task<Void, Never>?

    private var items: [BankedInquiry] {
        bank.inquiries(for: language)
    }

    var body: some View {
        Group {
            switch phase {
            case .list:
                listView
            case .editing:
                editView
            case .uploading:
                waitingView
            case .results:
                resultsView
            }
        }
        .navigationTitle(phase == .editing ? "Edit inquiry" : "Inquiry bank")
        .onDisappear {
            cancelUpload()
        }
        .onChange(of: scenePhase) { _, scene in
            if scene == .background {
                cancelUpload()
            }
        }
    }

    private var listView: some View {
        List {
            if let banner {
                Text(banner)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            ForEach(items) { item in
                Button {
                    editing = item
                    draft = item.text
                    phase = .editing
                } label: {
                    Text(item.text)
                        .font(.caption2)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", role: .destructive) {
                        bank.remove(id: item.id, language: language)
                        if bank.inquiries(for: language).isEmpty {
                            dismiss()
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                Button("Back") { dismiss() }
                Button("Upload all") { uploadAll() }
                    .tint(.blue)
                    .disabled(items.isEmpty)
            }
            .font(.caption2)
            .controlSize(.mini)
        }
    }

    private var editView: some View {
        VStack(spacing: 6) {
            TextField("Inquiry", text: $draft, axis: .vertical)
                .font(.caption2)
            HStack(spacing: 6) {
                Button("Cancel") {
                    editing = nil
                    phase = .list
                }
                Button("Save") { saveEdit() }
                    .tint(.blue)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .font(.caption2)
            .controlSize(.mini)
        }
        .padding(.horizontal, 4)
    }

    private var waitingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Uploading")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var resultsView: some View {
        TabView {
            ForEach(Array(results.enumerated()), id: \.offset) { index, item in
                resultPage(item, index: index)
            }
        }
        .tabViewStyle(.verticalPage)
    }

    private func resultPage(_ item: ImprovBatchItem, index: Int) -> some View {
        VStack(spacing: 6) {
            Text("\(index + 1) of \(results.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    switch item {
                    case .word(let word):
                        Text("Added")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text(word.definition)
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Text(word.surfaceForm)
                            .font(.caption)
                        if let sentence = word.sentence, !sentence.targetLang.isEmpty {
                            Text(sentence.targetLang)
                                .font(.caption2)
                                .padding(.top, 2)
                        }
                    case .failed(let message):
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Back") { dismiss() }
                .font(.caption2)
                .controlSize(.mini)
        }
    }

    private func saveEdit() {
        guard let editing else { return }
        bank.update(id: editing.id, text: draft, language: language)
        self.editing = nil
        phase = .list
    }

    private func uploadAll() {
        let snapshot = items
        guard !snapshot.isEmpty, uploadTask == nil else { return }
        banner = nil
        phase = .uploading
        uploadTask = Task {
            do {
                let batch = try await WordReviewClient.addImprovWords(
                    language: language,
                    inquiries: snapshot.map(\.text)
                )
                guard !Task.isCancelled else { return }
                apply(batch, to: snapshot)
                results = batch
                phase = .results
            } catch {
                guard !Task.isCancelled else { return }
                banner = (error as? LocalizedError)?.errorDescription ?? "Upload failed"
                phase = .list
            }
            uploadTask = nil
        }
    }

    private func apply(_ batch: [ImprovBatchItem], to snapshot: [BankedInquiry]) {
        var kept: [BankedInquiry] = []
        for (index, item) in snapshot.enumerated() {
            let outcome = index < batch.count ? batch[index] : .failed("Upload failed")
            switch outcome {
            case .word(let word):
                onWordAdded(word)
            case .failed(let message) where message == "Word already exists":
                break
            case .failed:
                kept.append(item)
            }
        }
        bank.replace(kept, language: language)
    }

    private func cancelUpload() {
        guard uploadTask != nil else { return }
        uploadTask?.cancel()
        uploadTask = nil
        if phase == .uploading {
            phase = .list
        }
    }

    private enum Phase {
        case list
        case editing
        case uploading
        case results
    }
}
