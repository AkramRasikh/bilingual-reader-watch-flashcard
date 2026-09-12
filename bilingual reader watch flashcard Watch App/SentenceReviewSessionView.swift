//
//  SentenceReviewSessionView.swift
//  bilingual reader watch flashcard Watch App
//
//  Queues currently due sentences. Graded cards stay in the local cache with
//  their next due; they re-enter the queue when that time arrives.
//  Trash removes reviewData only.
//

import AVFoundation
import Combine
import FSRS
import SwiftUI
import WatchKit

struct SentenceReviewSessionView: View {
    let language: String
    let initialSentences: [ReviewableSentence]
    var currentDueSentences: () -> [ReviewableSentence] = { [] }
    var totalInReview: () -> Int = { 0 }
    var onBack: () -> Void = {}
    var onReviewed: (String, Card) -> Void = { _, _ in }
    var onRemovedReview: (String) -> Void = { _ in }

    @State private var queue: [ReviewableSentence] = []
    @State private var waiting: [ReviewableSentence] = []
    @State private var didInit = false

    private let duePoll = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let sentence = queue.first {
                SentenceFlashcardView(
                    sentence: sentence,
                    language: language,
                    remainingDue: queue.count,
                    totalInReview: totalInReview(),
                    onBack: leaveSession,
                    onReviewed: { sentenceId, card in
                        parkReviewed(sentenceId: sentenceId, card: card)
                        onReviewed(sentenceId, card)
                    },
                    onRemovedReview: { sentenceId in
                        queue.removeAll { $0.id == sentenceId }
                        waiting.removeAll { $0.id == sentenceId }
                        onRemovedReview(sentenceId)
                    }
                )
            } else {
                VStack(spacing: 8) {
                    Text(queue.isEmpty && didInit ? "Done for now" : "No sentences due")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button("Back", action: leaveSession)
                        .font(.caption2)
                }
            }
        }
        .onAppear {
            guard !didInit else { return }
            queue = initialSentences
            didInit = true
        }
        .onChange(of: queue.first?.id) { oldId, newId in
            guard didInit, oldId != nil, newId != nil, oldId != newId else { return }
            SentenceAdvanceCue.play()
        }
        .onDisappear {
            WordAudioPlayer.shared.stop()
        }
        .onReceive(duePoll) { _ in
            enqueueNewlyDue()
        }
    }

    private func leaveSession() {
        WordAudioPlayer.shared.stop()
        onBack()
    }

    private func parkReviewed(sentenceId: String, card: Card) {
        if let current = queue.first(where: { $0.id == sentenceId }) {
            waiting.append(current.withCard(card))
        }
        queue.removeAll { $0.id == sentenceId }
        enqueueNewlyDue()
    }

    private func enqueueNewlyDue() {
        let now = Date()
        let inQueue = Set(queue.map(\.id))

        var ready: [ReviewableSentence] = []
        var stillWaiting: [ReviewableSentence] = []
        for sentence in waiting {
            if sentence.withFreshDue(now: now).isDue, !inQueue.contains(sentence.id) {
                ready.append(sentence)
            } else {
                stillWaiting.append(sentence)
            }
        }
        waiting = stillWaiting

        let heldIds = inQueue.union(ready.map(\.id)).union(Set(waiting.map(\.id)))
        let fromStore = currentDueSentences().filter { !heldIds.contains($0.id) }

        let fresh = ready + fromStore
        guard !fresh.isEmpty else { return }
        queue.append(contentsOf: fresh)
        print("[sentence review] re-queued \(fresh.count) due sentence(s)")
    }
}

/// Tiny “boof” plus Watch click when the next sentence card appears.
private enum SentenceAdvanceCue {
    private static var player: AVAudioPlayer?

    static func play() {
        WKInterfaceDevice.current().play(.click)
        playBoof()
    }

    private static func playBoof() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let next = try AVAudioPlayer(data: boofWav())
            next.volume = 0.65
            next.prepareToPlay()
            next.play()
            player = next
        } catch {
            print("[SentenceAdvanceCue] \(error)")
        }
    }

    private static func boofWav() -> Data {
        let sampleRate: Double = 8_000
        let duration = 0.12
        let count = Int(sampleRate * duration)
        var pcm = Data(count: count * MemoryLayout<Int16>.size)
        pcm.withUnsafeMutableBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<count {
                let t = Double(i) / sampleRate
                let envelope = exp(-t * 28)
                let freq = 165.0 - 70.0 * (t / duration)
                let value = sin(2 * Double.pi * freq * t) * envelope * 0.55
                samples[i] = Int16(clamping: Int(value * Double(Int16.max)))
            }
        }

        let dataSize = UInt32(pcm.count)
        var wav = Data()
        func ascii(_ s: String) { wav.append(contentsOf: s.utf8) }
        func u16(_ v: UInt16) {
            var x = v.littleEndian
            wav.append(Data(bytes: &x, count: 2))
        }
        func u32(_ v: UInt32) {
            var x = v.littleEndian
            wav.append(Data(bytes: &x, count: 4))
        }
        ascii("RIFF")
        u32(36 + dataSize)
        ascii("WAVE")
        ascii("fmt ")
        u32(16)
        u16(1)
        u16(1)
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate) * 2)
        u16(2)
        u16(16)
        ascii("data")
        u32(dataSize)
        wav.append(pcm)
        return wav
    }
}
