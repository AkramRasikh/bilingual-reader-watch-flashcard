//
//  WordAudioPlayer.swift
//  bilingual reader watch flashcard Watch App
//
//  Streams topic MP3s from Cloudflare (web getAudioURL) — no disk cache.
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class WordAudioPlayer: ObservableObject {
    static let shared = WordAudioPlayer()

    @Published private(set) var isPlaying = false
    @Published private(set) var activeKey: String?

    private let player = AVPlayer()
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    private init() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.activeKey = nil
            }
        }
    }

    deinit {
        statusObserver?.invalidate()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    /// Same shape as web `getAudioURL(title, language)`.
    static func audioURL(fileName: String, language: String) -> URL? {
        let base = GeneratedEnv.cloudflareAssetsURL.absoluteString
        let trimmedBase = base.hasSuffix("/") ? base : base + "/"
        let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        return URL(string: "\(trimmedBase)\(language)-audio/\(encodedName).mp3")
    }

    func toggle(fileName: String, language: String, cue: TimeInterval) {
        guard let url = Self.audioURL(fileName: fileName, language: language) else { return }
        let key = "\(url.absoluteString)#\(cue)"

        if isPlaying, activeKey == key {
            pause()
            return
        }

        play(url: url, cue: cue, key: key)
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        activeKey = nil
    }

    private func play(url: URL, cue: TimeInterval, key: String) {
        activateSession()

        let needsNewItem: Bool
        if let currentURL = (player.currentItem?.asset as? AVURLAsset)?.url {
            needsNewItem = currentURL != url
        } else {
            needsNewItem = true
        }

        if needsNewItem {
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            statusObserver?.invalidate()
            statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if item.status == .readyToPlay {
                        self.seekAndPlay(cue: cue, key: key)
                    } else if item.status == .failed {
                        print("[WordAudioPlayer] failed: \(item.error?.localizedDescription ?? "?")")
                        self.isPlaying = false
                        self.activeKey = nil
                    }
                }
            }
            activeKey = key
            // Seek once ready; also try immediately in case already ready.
            if item.status == .readyToPlay {
                seekAndPlay(cue: cue, key: key)
            }
        } else {
            seekAndPlay(cue: cue, key: key)
        }
    }

    private func seekAndPlay(cue: TimeInterval, key: String) {
        let time = CMTime(seconds: max(0, cue), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, finished else { return }
                self.activeKey = key
                self.player.play()
                self.isPlaying = true
            }
        }
    }

    private func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("[WordAudioPlayer] session error: \(error)")
        }
    }
}
